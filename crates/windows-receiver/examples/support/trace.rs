use std::error::Error;

pub fn parse_trace(text: &str) -> Result<Vec<(u64, u64)>, Box<dyn Error>> {
    if text.lines().next() != Some("counter,sample_position,capture_ns,frames,arrival_elapsed_ns") {
        return Err("Unexpected receiver CSV header".into());
    }
    let mut arrivals = Vec::new();
    let mut position = 0u64;
    let mut previous_ns = 0u64;
    for (index, line) in text.lines().skip(1).enumerate() {
        let row = line
            .split(',')
            .map(str::parse::<u64>)
            .collect::<Result<Vec<_>, _>>()?;
        if row.len() != 5
            || row[0] != index as u64
            || row[1] != position
            || row[3] == 0
            || row[3] > 240
            || row[4] < previous_ns
        {
            return Err(
                "Replay requires contiguous ordered packets and monotonic arrival times".into(),
            );
        }
        position = position
            .checked_add(row[3])
            .ok_or("Sample position overflow")?;
        previous_ns = row[4];
        arrivals.push((row[4], row[3]));
    }
    if arrivals.is_empty() {
        return Err("Empty packet trace".into());
    }
    // Normalize away setup time. The model starts when the first packet arrives.
    let origin = arrivals[0].0;
    for (ns, _) in &mut arrivals {
        *ns -= origin;
    }
    if arrivals.last().unwrap().0 > 86_400_000_000_000 {
        return Err("Trace exceeds the 24 hour replay limit".into());
    }
    Ok(arrivals)
}
