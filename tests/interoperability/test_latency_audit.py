import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('audit', Path(__file__).parents[2] / 'scripts/latency-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class LatencyAuditTests(unittest.TestCase):
    def test_shutdown_and_partial_settings_do_not_replace_complete_state(self):
        def block(input_latency, complete=True):
            body = ('date: info: Audio In Out: Begin of UpdateAudioStateStatic\n'
                    'date: info: Audio In Out: Driver Type: ASIO\n'
                    'date: info: Audio In Out: Input Device: Test\n'
                    'date: info: Audio In Out: Output Device: Test\n'
                    f'date: info: Audio In Out: Input Latency: {input_latency} ms\n'
                    'date: info: Audio In Out: Output Latency: 12 ms\n'
                    'date: info: Audio In Out: Input Buffer Size: 128 Samples\n'
                    'date: info: Audio In Out: Output Buffer Size: 128 Samples\n')
            return body + ('date: info: Audio In Out: End of UpdateAudioStateStatic\n' if complete else '')
        result = audit.ableton_state(block(10) + block(0) + block(999, False))
        self.assertEqual(result['Input Latency'], '10 ms')

    def test_missing_diagnostics_never_become_a_latency_measurement(self):
        result = audit.audit('', {'target_buffer_ms': 8}, {})
        self.assertIsNone(result['physical_monitoring_latency_ms'])
        self.assertIsNone(result['last_complete_active_ableton_state'])
        self.assertIsNone(result['receiver']['effective_buffer_target_ms'])
        self.assertIsNone(result['phone']['network_capture_age_ms_mean'])


if __name__ == '__main__':
    unittest.main()
