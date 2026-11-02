//! Local status publishing. A bounded worker owns all dashboard file I/O.
use std::{
    fs, io,
    path::PathBuf,
    sync::mpsc::{self, SyncSender},
    thread::{self, JoinHandle},
    time::{SystemTime, UNIX_EPOCH},
};

pub(crate) struct Snapshot {
    pub sampled_at: SystemTime,
    pub state: &'static str,
    pub stopped: bool,
    pub rows: Vec<(&'static str, String)>,
}

pub(crate) struct Dashboard {
    sender: SyncSender<Snapshot>,
    worker: JoinHandle<()>,
}

impl Dashboard {
    pub fn start(directory: PathBuf) -> io::Result<Self> {
        let (sender, receiver) = mpsc::sync_channel::<Snapshot>(1);
        let worker = thread::Builder::new()
            .name("covoo-dashboard".into())
            .spawn(move || {
                let mut failed = false;
                for snapshot in receiver {
                    let result = publish(&directory, &snapshot);
                    if let Err(error) = result {
                        if !failed {
                            eprintln!("Dashboard update failed: {error}. Audio continues; status may be stale.");
                        }
                        failed = true;
                    } else {
                        failed = false;
                    }
                }
            })?;
        Ok(Self { sender, worker })
    }

    /// Never wait for the browser or disk. Skip a display update if I/O lags.
    pub fn update(&self, snapshot: Snapshot) {
        let _ = self.sender.try_send(snapshot);
    }

    /// Called after streaming workers stop; preserve the final stopped state.
    pub fn finish(self, snapshot: Snapshot) {
        let _ = self.sender.send(snapshot);
        drop(self.sender);
        if self.worker.join().is_err() {
            eprintln!("Dashboard worker stopped unexpectedly");
        }
    }
}

fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn render(snapshot: &Snapshot, updated_ms: u128) -> String {
    let mut rows = String::new();
    for (name, value) in &snapshot.rows {
        rows.push_str(&format!(
            "<div><dt>{}</dt><dd>{}</dd></div>",
            escape(name),
            escape(value)
        ));
    }
    // Substitute user-derived text last so it cannot become template syntax.
    include_str!("dashboard.html")
        .replace("{{updated_ms}}", &updated_ms.to_string())
        .replace(
            "{{stopped}}",
            if snapshot.stopped { "true" } else { "false" },
        )
        .replace("{{state}}", &escape(snapshot.state))
        .replace("{{rows}}", &rows)
}

fn publish(directory: &std::path::Path, snapshot: &Snapshot) -> io::Result<()> {
    fs::create_dir_all(directory)?;
    let updated_ms = snapshot
        .sampled_at
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_millis();
    let temporary = directory.join("dashboard.pending");
    fs::write(&temporary, render(snapshot, updated_ms))?;
    // Same-directory replacement prevents readers seeing partially written HTML.
    fs::rename(temporary, directory.join("dashboard.html"))?;
    // Separate read-only desktop snapshot; contains no pairing credentials.
    let status = serde_json::json!({
        "updated_ms": updated_ms,
        "stopped": snapshot.stopped,
        "state": snapshot.state,
        "rows": snapshot.rows,
    });
    fs::write(
        directory.join("status.pending"),
        serde_json::to_vec(&status)?,
    )?;
    fs::rename(
        directory.join("status.pending"),
        directory.join("status.json"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_is_escaped_and_unknowns_stay_unknown() {
        let snapshot = Snapshot {
            sampled_at: UNIX_EPOCH,
            state: "Waiting for audio",
            stopped: false,
            rows: vec![
                ("Output", "<script>alert('x')</script>&\"{{stopped}}".into()),
                ("Physical latency", "Not measured".into()),
            ],
        };
        let page = render(&snapshot, 123);
        assert!(!page.contains("<script>alert"));
        assert!(
            page.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;&amp;&quot;{{stopped}}")
        );
        assert!(page.contains("Not measured"));
        assert!(page.contains("const updated = 123"));
        assert!(page.contains("const stopped = false"));
    }

    #[test]
    fn worker_replaces_snapshot_and_finalizes_without_touching_pairing() {
        let directory =
            std::env::temp_dir().join(format!("covoo-dashboard-{:016x}", rand::random::<u64>()));
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("pairing.html"), "private pairing data").unwrap();
        let dashboard = Dashboard::start(directory.clone()).unwrap();
        dashboard.update(Snapshot {
            sampled_at: UNIX_EPOCH,
            state: "Receiving",
            stopped: false,
            rows: vec![],
        });
        dashboard.finish(Snapshot {
            sampled_at: UNIX_EPOCH,
            state: "Receiver stopped",
            stopped: true,
            rows: vec![],
        });
        let page = fs::read_to_string(directory.join("dashboard.html")).unwrap();
        assert!(page.contains("Receiver stopped"));
        assert!(page.contains("const stopped = true"));
        assert!(page.contains("const updated = 0"));
        assert!(!page.contains("private pairing data"));
        assert_eq!(
            fs::read_to_string(directory.join("pairing.html")).unwrap(),
            "private pairing data"
        );
        assert!(!directory.join("dashboard.pending").exists());
        fs::remove_dir_all(directory).unwrap();
    }
}
