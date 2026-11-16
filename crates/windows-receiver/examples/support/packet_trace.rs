use std::error::Error;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Packet {
    pub counter: u64,
    pub position: u64,
    pub capture_ns: u64,
    pub frames: u16,
    pub arrival_ns: u64,
}

pub fn parse_trace(text: &str) -> Result<Vec<Packet>, Box<dyn Error>> {
    if text.lines().next() != Some("counter,sample_position,capture_ns,frames,arrival_elapsed_ns") {
        return Err("Unexpected receiver CSV header".into());
    }
    let mut packets = Vec::new();
    let mut position = 0u64;
    for (index, line) in text.lines().skip(1).enumerate() {
        let row = line
            .split(',')
            .map(str::parse::<u64>)
            .collect::<Result<Vec<_>, _>>()?;
        if row.len() != 5
            || row[0] != index as u64
            || row[1] != position
            || !(1..=240).contains(&row[3])
        {
            return Err("Replay requires unique contiguous source counters and positions".into());
        }
        position = position
            .checked_add(row[3])
            .ok_or("Sample position overflow")?;
        packets.push(Packet {
            counter: row[0],
            position: row[1],
            capture_ns: row[2],
            frames: row[3] as u16,
            arrival_ns: row[4],
        });
    }
    let origin = packets
        .iter()
        .map(|p| p.arrival_ns)
        .min()
        .ok_or("Empty trace")?;
    // Stable ties retain file order. Identity/source positions are never renumbered.
    packets.sort_by_key(|p| p.arrival_ns);
    for packet in &mut packets {
        packet.arrival_ns -= origin;
    }
    if packets.last().unwrap().arrival_ns > 86_400_000_000_000 {
        return Err("Trace exceeds the 24 hour replay limit".into());
    }
    Ok(packets)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn chronology_preserves_identity_timestamps_and_source_positions() {
        let text = "counter,sample_position,capture_ns,frames,arrival_elapsed_ns\n0,0,100,128,1000\n1,128,200,128,2000\n2,256,300,128,1974\n3,384,400,128,2000";
        let packets = parse_trace(text).unwrap();
        assert_eq!(
            packets.iter().map(|p| p.counter).collect::<Vec<_>>(),
            [0, 2, 1, 3]
        );
        assert_eq!(
            packets[1],
            Packet {
                counter: 2,
                position: 256,
                capture_ns: 300,
                frames: 128,
                arrival_ns: 974
            }
        );
        assert_eq!(packets[2].arrival_ns, 1000);
        for body in [
            "",
            "0,0,0,0,1",
            "0,0,0,241,1",
            "0,0,0,1,1\n0,1,0,1,2",
            "0,0,0,1,1\n2,1,0,1,2",
            "0,1,0,1,1",
        ] {
            assert!(
                parse_trace(&format!(
                    "counter,sample_position,capture_ns,frames,arrival_elapsed_ns\n{body}"
                ))
                .is_err()
            );
        }
    }
}
