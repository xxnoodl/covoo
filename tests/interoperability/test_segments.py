import json
from pathlib import Path
import runpy
import struct
import tempfile
import unittest

verify = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'scripts/compare-segments.py'))['verify']


def write_wav(path, samples, start, phone=False):
    data = struct.pack('<' + 'f' * len(samples), *samples)
    fmt = struct.pack('<HHIIHH', 3, 1, 48000, 192000, 4, 32)
    path.write_bytes(b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' +
                     struct.pack('<I', 16) + fmt + b'data' + struct.pack('<I', len(data)) + data)
    path.with_suffix('.json').write_text(json.dumps({
        'frames_written': len(samples), 'dropped_frames': 0, 'render_errors': 0,
        'discontinuities': 0, 'unwritten_rendered_frames': 0,
        'sender_final_summary_received': False}))
    if not phone:
        path.with_suffix('.csv').write_text('sample_position,frames\n' + f'{start},{len(samples)}\n')


class SegmentTests(unittest.TestCase):
    def test_exact_segments_do_not_hide_missing_middle(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            phone, first, last = [root / name for name in ['phone.wav', 'first.wav', 'last.wav']]
            write_wav(phone, [0.125] * 10, 0, phone=True)
            write_wav(first, [0.125] * 4, 0)
            write_wav(last, [0.125] * 3, 7)
            result = verify(phone, [last, first])
            self.assertEqual(result['missing_ranges_half_open'], [[4, 7]])
            self.assertEqual(result['missing_pc_frames'], 3)
            self.assertFalse(result['whole_take_pcm_verified'])
            self.assertTrue(all(part['pcm_bit_exact'] for part in result['segments']))

    def test_corruption_overlap_and_discontinuous_reference_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            phone, pc = [Path(folder) / name for name in ['phone.wav', 'pc.wav']]
            write_wav(phone, [0.125] * 10, 0, phone=True)
            write_wav(pc, [0.25] * 10, 0)
            with self.assertRaisesRegex(ValueError, 'PCM differs'):
                verify(phone, [pc])
            write_wav(pc, [0.125] * 10, 0)
            self.assertTrue(verify(phone, [pc])['whole_take_pcm_verified'])
            with self.assertRaisesRegex(ValueError, 'Overlapping'):
                verify(phone, [pc, pc])
            meta = json.loads(phone.with_suffix('.json').read_text())
            meta['discontinuities'] = 1
            phone.with_suffix('.json').write_text(json.dumps(meta))
            with self.assertRaisesRegex(ValueError, 'Phone reference'):
                verify(phone, [pc])
