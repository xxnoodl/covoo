import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('recording_health', Path(__file__).parents[2] / 'scripts/recording-health.py')
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class RecordingHealthTests(unittest.TestCase):
    def fixture(self, directory):
        base = Path(directory) / 'covoo-0123456789abcdef'
        fmt = struct.pack('<HHIIHH', 3, 1, 48000, 192000, 4, 32)
        body = b'WAVEfmt ' + struct.pack('<I', len(fmt)) + fmt + b'data' + struct.pack('<I', 12) + struct.pack('<3f', .25, .5, .75)
        base.with_suffix('.wav').write_bytes(b'RIFF' + struct.pack('<I', len(body)) + body)
        report = dict(pcm_continuity_verified=True, sender_final_summary_received=True, sender_summary_valid=True,
                      silence_frames_inserted=0, large_gap_frames_omitted=0, leading_frames_not_received=0,
                      trailing_frames_not_received=0, packets_not_written=0, missing_packets_detected=0,
                      error=None, wav_frames=3, source_frames_written=3, sample_rate_hz=48000,
                      sender_first_position=100, sender_last_position=103)
        return base, report

    def test_finalized_segment_does_not_accept_whole_take_or_playback(self):
        with tempfile.TemporaryDirectory() as directory:
            base, report = self.fixture(directory)
            base.with_suffix('.json').write_text(json.dumps(report), encoding='utf-8-sig')
            result = health.inspect(base)
            self.assertEqual(result['state'], 'finalized_contiguous_segment')
            self.assertIsNone(result['whole_phone_take_verified'])
            self.assertIsNone(result['vst_playback_verified'])

    def test_missing_final_report_and_crash_header_are_not_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            base, report = self.fixture(directory)
            before = base.with_suffix('.wav').read_bytes()
            self.assertEqual(health.inspect(base)['state'], 'unfinalized_or_invalid')
            self.assertEqual(base.with_suffix('.wav').read_bytes(), before)
            base.with_suffix('.json').write_text(json.dumps(report))
            base.with_suffix('.wav').write_bytes(before[:4] + b'\x00'*4 + before[8:])
            self.assertEqual(health.inspect(base)['state'], 'unfinalized_or_invalid')

    def test_unknown_counts_false_summary_and_mismatched_frames_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            base, report = self.fixture(directory)
            for changes in [dict(sender_summary_valid=False), dict(wav_frames=99), dict(missing_packets_detected=True),
                            dict(missing_packets_detected=None), dict(sender_last_position=104)]:
                base.with_suffix('.json').write_text(json.dumps(dict(report, **changes)))
                self.assertNotEqual(health.inspect(base)['state'], 'finalized_contiguous_segment')

    def test_audit_filters_credentials_and_invalid_reports_without_copying_content(self):
        with tempfile.TemporaryDirectory() as directory:
            base, _ = self.fixture(directory)
            base.with_suffix('.json').write_text('[]')
            (Path(directory) / 'pairing.json').write_text('secret-token')
            (Path(directory) / 'covoo-0123456789abcdef.plugin.json').write_text('secret-token')
            result = health.audit(directory)
            self.assertEqual(len(result['recordings']), 1)
            self.assertNotIn('secret-token', json.dumps(result))
            self.assertNotEqual(result['recordings'][0]['state'], 'finalized_contiguous_segment')


if __name__ == '__main__':
    unittest.main()
