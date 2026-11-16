import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('audit', Path(__file__).parents[2] / 'scripts/latency-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class LatencyAuditTests(unittest.TestCase):
    def test_receiver_plugin_drops_remain_visible_with_complete_archive(self):
        result = audit.audit(receiver={'pcm_continuity_verified': True, 'plugin_queue_drops': 18},
                             plugin={'packet_channel_capacity': 32})
        self.assertTrue(result['archive']['pcm_continuity_verified'])
        self.assertEqual(result['receiver_plugin_route']['plugin_queue_drops'], 18)
        self.assertEqual(result['plugin']['packet_channel_capacity'], 32)
        self.assertIsNone(result['plugin']['packet_age_limit_ms'])
        self.assertEqual(len(result['plugin_findings']), 1)
        self.assertIn('fanout queue drops', result['plugin_findings'][0])
        self.assertIsNone(result['physical_monitoring_latency_ms'])

    def test_complete_archive_does_not_hide_silent_or_starved_plugin(self):
        result = audit.audit(receiver={'pcm_continuity_verified': True}, plugin={
            'host_clock_frames': 0, 'source_starvation_events': 5,
            'source_discarded_frames': 100, 'pairing_token': 'must-not-export'})
        self.assertTrue(result['archive']['pcm_continuity_verified'])
        self.assertEqual(len(result['plugin_findings']), 3)
        self.assertIsNone(result['physical_monitoring_latency_ms'])
        self.assertNotIn('must-not-export', json.dumps(result))

    def test_old_report_keeps_new_metrics_unknown_and_avoids_playback_pass(self):
        result = audit.audit(plugin={'sent_host_frames_including_silence': 999})
        self.assertIsNone(result['plugin']['host_readiness_changes'])
        self.assertIsNone(result['plugin']['host_lifetime_silence_frames'])
        self.assertEqual(result['plugin_findings'], [])
        self.assertIn('do not prove audible playback', result['plugin_note'])
        for invalid in [[], 'not a report', 7]:
            with self.assertRaises(ValueError):
                audit.audit(plugin=invalid)

    def test_plugin_cli_reads_bom_and_rejects_invalid_report_shape(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / 'plugin.json'
            report.write_text('{"host_clock_frames":0}', encoding='utf-8-sig')
            command = [sys.executable, str(spec.origin), '--plugin-report', str(report)]
            completed = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIsNone(json.loads(completed.stdout)['physical_monitoring_latency_ms'])
            report.write_text('[]', encoding='utf-8')
            completed = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn('must be a JSON object', completed.stderr)

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
