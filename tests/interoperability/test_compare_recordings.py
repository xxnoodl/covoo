import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('compare', ROOT / 'scripts/compare-recordings.py')
COMPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPARE)


class RecordingComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='covoo-compare-')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.phone, self.pc = root / 'phone.wav', root / 'pc.wav'
        payload = struct.pack('<4f', 0.0, 0.125, -0.5, 1.0)
        fmt = struct.pack('<HHIIHH', 3, 1, 48000, 192000, 4, 32)
        wav = b'RIFF' + struct.pack('<I', 36 + len(payload)) + b'WAVEfmt ' + struct.pack('<I', 16) + fmt + b'data' + struct.pack('<I', len(payload)) + payload
        self.phone.write_bytes(wav)
        self.pc.write_bytes(wav)
        self.phone.with_suffix('.json').write_text(json.dumps(dict(network_completed=True,
            dropped_frames=0, render_errors=0, discontinuities=0, network_dropped_frames=0,
            network_send_errors=0, network_reconnects=0, frames_written=4)))
        self.pc.with_suffix('.json').write_text(json.dumps(dict(pcm_continuity_verified=True,
            source_frames_written=4, sender_first_position=0, sender_last_position=4)))

    def test_exact_pcm(self):
        self.assertTrue(COMPARE.verify(self.phone, self.pc)['pcm_bit_exact'])

    def test_sample_change_is_detected(self):
        wav = bytearray(self.pc.read_bytes())
        wav[-4] ^= 1
        self.pc.write_bytes(wav)
        with self.assertRaisesRegex(ValueError, 'PCM differs'):
            COMPARE.verify(self.phone, self.pc)

    def test_truncation_and_loss_cannot_pass(self):
        report = json.loads(self.phone.with_suffix('.json').read_text())
        report['network_dropped_frames'] = 1
        self.phone.with_suffix('.json').write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, 'network_dropped_frames'):
            COMPARE.verify(self.phone, self.pc)
        self.pc.write_bytes(self.pc.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, 'RIFF'):
            COMPARE.wav_info(self.pc)


if __name__ == '__main__':
    unittest.main()
