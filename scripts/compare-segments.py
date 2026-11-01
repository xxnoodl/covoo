"""Verify received segments against a complete phone WAV; report omitted ranges."""
import argparse
import csv
import json
from pathlib import Path
import runpy

wav_info = runpy.run_path(str(Path(__file__).with_name('compare-recordings.py')))['wav_info']


def verify(phone_path, pc_paths):
    phone_path = Path(phone_path)
    report = json.loads(phone_path.with_suffix('.json').read_text())
    rate, offset, total = wav_info(phone_path)
    if total == 0 or report.get('frames_written') != total or any(report.get(k) != 0 for k in
            ['dropped_frames', 'render_errors', 'discontinuities', 'unwritten_rendered_frames']):
        raise ValueError('Phone reference must be complete and continuous for position mapping')
    if not pc_paths:
        raise ValueError('Supply at least one PC segment')
    segments = []
    for path in map(Path, pc_paths):
        pc_rate, pc_offset, count = wav_info(path)
        if pc_rate != rate or count == 0:
            raise ValueError('PC segment rate differs or segment is empty')
        start = position = None
        with path.with_suffix('.csv').open(newline='') as timeline:
            for row in csv.DictReader(timeline):
                current, frames = int(row['sample_position']), int(row['frames'])
                if current < 0 or not 1 <= frames <= 240:
                    raise ValueError('Invalid packet position or frame count')
                if position is None:
                    start = position = current
                if position != current:
                    raise ValueError('Internal segment gap/reorder requires separate analysis')
                position += frames
        if start is None or position - start != count or position > total:
            raise ValueError('Segment timeline does not match WAV or phone bounds')
        pc_report = json.loads(path.with_suffix('.json').read_text())
        with phone_path.open('rb') as source, path.open('rb') as received:
            source.seek(offset + start * 4)
            received.seek(pc_offset)
            remaining = count * 4
            while remaining:
                size = min(remaining, 65536)
                if source.read(size) != received.read(size):
                    raise ValueError(f'PC PCM differs from phone reference: {path.name}')
                remaining -= size
        segments.append({'file': path.name, 'first_frame': start, 'end_frame': position,
                         'pcm_bit_exact': True,
                         'final_summary_received': pc_report.get('sender_final_summary_received')})
    segments.sort(key=lambda segment: segment['first_frame'])
    cursor = 0
    gaps = []
    for segment in segments:
        if segment['first_frame'] < cursor:
            raise ValueError('Overlapping or duplicate segments')
        if segment['first_frame'] > cursor:
            gaps.append([cursor, segment['first_frame']])
        cursor = segment['end_frame']
    if cursor < total:
        gaps.append([cursor, total])
    missing = sum(end - start for start, end in gaps)
    return {'sample_rate_hz': rate, 'phone_frames': total, 'segments': segments,
            'missing_ranges_half_open': gaps, 'missing_pc_frames': missing,
            'missing_pc_seconds': missing / rate,
            'whole_take_pcm_verified': missing == 0,
            'phone_reported_sender_dropped_frames': report.get('network_dropped_frames'),
            'note': 'Received bytes verified against phone offsets. Missing ranges are absent from supplied PC files. Sender drop counters do not include every in-transit loss. Final summaries remain separate control evidence.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phone_wav', type=Path)
    parser.add_argument('pc_wavs', type=Path, nargs='+')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.phone_wav, args.pc_wavs), indent=2))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Segment verification failed: {error}\n')
