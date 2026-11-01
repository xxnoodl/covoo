"""Offline receiver dashboard. Reads completed reports, never pairing files or PCM."""
import argparse
import html
import json
from pathlib import Path


def display(value):
    if value is None:
        return 'Not reported'
    if isinstance(value, bool):
        return 'Yes' if value else 'No'
    if isinstance(value, float):
        return f'{value:.3f}'
    return str(value)


def render(folder):
    rows = []
    errors = []
    # Only archive report filenames; never load pairing.html or arbitrary JSON.
    for path in sorted(Path(folder).glob('covoo-*.json')):
        if path.name.endswith('.live.json'):
            continue
        try:
            if path.stat().st_size > 1_048_576:
                raise ValueError('Report exceeds 1 MiB limit')
            report = json.loads(path.read_text(encoding='utf-8'))
            if not isinstance(report, dict):
                raise ValueError('Report must be an object')
            live_path = path.with_suffix('.live.json')
            live = {}
            if live_path.exists():
                if live_path.stat().st_size > 1_048_576:
                    raise ValueError('Live report exceeds 1 MiB limit')
                live = json.loads(live_path.read_text(encoding='utf-8'))
                if not isinstance(live, dict):
                    raise ValueError('Live report must be an object')
            values = [path.stem, report.get('duration_seconds'),
                      report.get('pcm_continuity_verified'), report.get('missing_packets_detected'),
                      live.get('endpoint'), live.get('actual_engine_period_ms'),
                      live.get('effective_buffer_target_ms'), live.get('underruns'),
                      live.get('recovery_silence_output_frames'), live.get('output_errors'),
                      report.get('error')]
            rows.append('<tr>' + ''.join(f'<td>{html.escape(display(v))}</td>' for v in values) + '</tr>')
        except (OSError, ValueError, TypeError) as error:
            errors.append(f'{path.name}: {error}')
    headings = ['Session', 'Seconds', 'Archive continuity verified', 'Missing packets',
                'Output', 'Engine period ms', 'Source target ms', 'Source underruns',
                'Recovery silence frames', 'Output errors', 'Archive error']
    return '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>covoo session reports</title><style>
body{font:16px system-ui;margin:2rem;background:#151718;color:#eee}table{border-collapse:collapse}
td,th{padding:.6rem;border:1px solid #666;text-align:left}th{background:#303638}
.table{overflow:auto}li{color:#ffbd99}</style><h1>covoo session reports</h1>
<p>Offline snapshot of completed report files. Refresh by running the command again.
Missing values are not reported, not zero. Archive continuity does not prove glitch-free monitoring.</p>
<p>Physical monitoring latency: not measured. CPU, memory and current connection state: not collected.</p>
<div class="table"><table><thead><tr>''' + ''.join(f'<th>{h}</th>' for h in headings) + \
        '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table></div><ul>' + \
        ''.join(f'<li>{html.escape(e)}</li>' for e in errors) + '</ul></html>'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recordings', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        if not args.recordings.is_dir():
            raise ValueError('Recordings folder does not exist')
        if args.output.exists():
            raise ValueError('Choose a new output file; existing files are not overwritten')
        page = render(args.recordings)
        with args.output.open('x', encoding='utf-8') as output:
            output.write(page)
        print(args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Dashboard failed: {error}\n')
