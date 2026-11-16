"""Read component diagnostics. Never infer full monitoring latency from them."""
import argparse
import json
from pathlib import Path


def ableton_state(text):
    states = []
    current = None
    marker = 'Audio In Out: '
    for line in text.splitlines():
        if marker not in line:
            continue
        timestamp, body = line.split(marker, 1)
        if body == 'Begin of UpdateAudioStateStatic':
            current = {'log_timestamp': timestamp.split(': info:')[0]}
        elif body == 'End of UpdateAudioStateStatic':
            if current is not None:
                states.append(current)
            current = None
        elif current is not None and ': ' in body:
            key, value = body.split(': ', 1)
            current[key] = value
    for state in reversed(states):
        try:
            active = all(float(state[k].split()[0]) > 0 for k in
                         ['Input Latency', 'Output Latency', 'Input Buffer Size', 'Output Buffer Size'])
            if active and all(state.get(k) not in [None, 'No Device'] for k in ['Input Device', 'Output Device']):
                return state
        except (KeyError, ValueError):
            continue
    return None


def audit(log=None, receiver=None, phone=None, plugin=None):
    for name, report in [('receiver', receiver), ('phone', phone), ('plugin', plugin)]:
        if report is not None and not isinstance(report, dict):
            raise ValueError(f'{name} report must be a JSON object')
    result = {'physical_monitoring_latency_ms': None,
              'note': 'Reported settings, software timing and OS timestamp estimates are not a physical end-to-end measurement.'}
    if log is not None:
        result['last_complete_active_ableton_state'] = ableton_state(log)
        result['ableton_note'] = 'Historical log state; may not be the current settings. DAW latency excludes upstream phone/transport stages.'
    if receiver is not None:
        keys = ['target_buffer_ms', 'effective_buffer_target_ms', 'requested_device_buffer_frames',
                'endpoint_rate_hz', 'callback_frames_min', 'callback_frames_max',
                'driver_timestamp_lead_ms_min', 'driver_timestamp_lead_ms_max',
                'resampler_delay_output_frames', 'underruns', 'overruns', 'output_errors',
                'queue_high_water_frames', 'tail_drain_complete']
        keys += ['packet_live_worker_wait_ms_mean', 'packet_live_worker_wait_ms_max']
        keys += ['backend', 'engine_period_min_frames', 'selected_engine_period_frames',
                 'actual_engine_period_frames', 'actual_engine_period_ms',
                 'endpoint_buffer_capacity_frames', 'client_queue_target_frames',
                 'native_event_gap_ms_max', 'thread_scheduler']
        keys += ['underrun_events_first_32', 'underrun_timeline_note',
                 'startup_silence_output_frames', 'recovery_silence_output_frames']
        keys += ['asrc_adjustment_ppm_min', 'asrc_adjustment_ppm_max',
                 'device_clock_rate_ratio', 'device_clock_errors', 'device_clock_note']
        result['receiver'] = {k: receiver.get(k) for k in keys}
    if phone is not None:
        keys = ['latency_profile', 'actual_io_buffer_ms', 'capture_worker_interval_ms',
                'network_capture_age_ms_mean', 'network_capture_age_ms_max',
                'network_dropped_frames', 'network_send_errors']
        result['phone'] = {k: phone.get(k) for k in keys}
    if plugin is not None:
        keys = ['source_rate', 'host_rate', 'host_clock_frames', 'host_queued_frames',
                'host_block_frames', 'host_feedback_observations',
                'host_not_ready_observations', 'host_readiness_changes',
                'host_lifetime_silence_frames', 'host_lifetime_discarded_frames',
                'source_target_frames', 'source_starvation_events',
                'source_discarded_frames', 'source_queue_overflow_frames',
                'stale_or_paused_packets', 'sent_host_frames_including_silence',
                'asrc_adjustment_ppm', 'error']
        result['plugin'] = {k: plugin.get(k) for k in keys}
        result['plugin_note'] = (
            'Source counters describe the feeder take; old reports may retain only the last adapter epoch. '
            'Host lifetime counters include other takes and startup. Feedback counts are observations, '
            'not durations. Sent frames can include silence and do not prove audible playback. '
            'ASRC correction is a software control value, not measured clock drift or physical latency.')
        findings = []
        for key, message in [
                ('source_starvation_events', 'Source starvation was reported.'),
                ('source_discarded_frames', 'Source frames were discarded.'),
                ('source_queue_overflow_frames', 'The feeder source queue overflowed.'),
                ('stale_or_paused_packets', 'Packets were discarded as stale or while the host was not ready.')]:
            value = plugin.get(key)
            if type(value) in (int, float) and value > 0:
                findings.append(message)
        if plugin.get('host_clock_frames') == 0:
            findings.append('No advancing live host frames were reported; the cause is not identified.')
        if plugin.get('error'):
            findings.append('The feeder reported an error; inspect plugin.error.')
        result['plugin_findings'] = findings
        if receiver is not None:
            keys = ['duration_seconds', 'source_frames_written', 'wav_frames',
                    'pcm_continuity_verified', 'sender_final_summary_received',
                    'sender_summary_valid', 'missing_packets_detected',
                    'silence_frames_inserted', 'leading_frames_not_received',
                    'trailing_frames_not_received', 'error']
            result['archive'] = {k: receiver.get(k) for k in keys}
            result['archive_note'] = (
                'Archive continuity is separate from VST playback. These reports were supplied '
                'by the caller; matching take identity and phone/PC PCM require separate verification.')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ableton-log', type=Path)
    parser.add_argument('--receiver-report', type=Path)
    parser.add_argument('--phone-report', type=Path)
    parser.add_argument('--plugin-report', type=Path)
    args = parser.parse_args()
    if not any([args.ableton_log, args.receiver_report, args.phone_report, args.plugin_report]):
        parser.error('Supply at least one log/report')
    try:
        print(json.dumps(audit(
            args.ableton_log.read_text(errors='replace') if args.ableton_log else None,
            json.loads(args.receiver_report.read_text(encoding='utf-8-sig')) if args.receiver_report else None,
            json.loads(args.phone_report.read_text(encoding='utf-8-sig')) if args.phone_report else None,
            json.loads(args.plugin_report.read_text(encoding='utf-8-sig')) if args.plugin_report else None), indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f'Audit failed: {error}\n')
