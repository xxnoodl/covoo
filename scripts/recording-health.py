"""Inspect receiver recording finalization without repairing files or reading PCM."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('covoo_wav_info', Path(__file__).with_name('compare-recordings.py'))
wav_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wav_module)


def inspect(base):
    base = Path(base)
    result = {'state': 'unfinalized_or_invalid', 'wav_bytes_on_disk': None,
              'sample_rate_hz': None, 'wav_frames': None,
              'whole_phone_take_verified': None, 'vst_playback_verified': None, 'reasons': []}
    reasons = result['reasons']
    wav = base.with_suffix('.wav')
    valid_wav = False
    if wav.exists():
        result['wav_bytes_on_disk'] = wav.stat().st_size
        try:
            rate, _, frames = wav_module.wav_info(wav)
            result.update(sample_rate_hz=rate, wav_frames=frames)
            valid_wav = frames > 0
            if not valid_wav:
                reasons.append('WAV is empty')
        except (ValueError, OSError) as error:
            reasons.append(str(error))
    else:
        reasons.append('WAV is missing')
    report_path = base.with_suffix('.json')
    if not report_path.exists():
        reasons.append('Final report is missing; recording may still be active or was interrupted')
        return result
    try:
        if report_path.stat().st_size > 1024 * 1024:
            raise ValueError('Final report exceeds size limit')
        report = json.loads(report_path.read_text(encoding='utf-8-sig'))
        if not isinstance(report, dict):
            raise ValueError('Final report must be an object')
    except (ValueError, OSError) as error:
        reasons.append(str(error))
        return result
    for key in ['pcm_continuity_verified', 'sender_final_summary_received', 'sender_summary_valid']:
        if report.get(key) is not True:
            reasons.append(f'{key} is false or unknown')
    for key in ['silence_frames_inserted', 'large_gap_frames_omitted', 'leading_frames_not_received',
                'trailing_frames_not_received', 'packets_not_written', 'missing_packets_detected']:
        if type(report.get(key)) is not int or report[key] != 0:
            reasons.append(f'{key} is nonzero or unknown')
    if 'error' not in report or report['error'] is not None:
        reasons.append('Receiver error is present or unknown')
    for key, expected in [('wav_frames', result['wav_frames']),
                          ('source_frames_written', result['wav_frames']),
                          ('sample_rate_hz', result['sample_rate_hz'])]:
        if type(report.get(key)) is not int or report[key] != expected:
            reasons.append(f'{key} does not match a valid WAV')
    first, last = report.get('sender_first_position'), report.get('sender_last_position')
    if (type(first) is not int or type(last) is not int or first < 0 or last < first
            or last - first != result['wav_frames']):
        reasons.append('Sender range does not match WAV frames')
    if valid_wav and not reasons:
        result['state'] = 'finalized_contiguous_segment'
    elif valid_wav:
        result['state'] = 'finalized_unverified_segment'
    return result


def audit(directory):
    directory = Path(directory)
    if not directory.is_dir():
        raise ValueError('Supply an existing receiver recordings directory')
    bases = {p.with_suffix('') for p in directory.rglob('covoo-*')
             if p.is_file() and re.fullmatch(r'covoo-[0-9a-f]{16}\.(wav|csv|json)', p.name)}
    rows = []
    for base in sorted(bases):
        row = inspect(base)
        row['recording'] = base.relative_to(directory).as_posix()
        rows.append(row)
    return {'recordings': rows, 'note': 'Finalized segments are not proof of whole phone takes or VST playback. '
            'Missing/invalid finalization may mean active recording or interruption. Writer liveness is not checked. '
            'Originals are unchanged; no PCM payload is read or recovered.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(audit(args.directory), indent=2))
    except (ValueError, OSError) as error:
        parser.exit(1, f'Recording audit failed: {error}\n')
