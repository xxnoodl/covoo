"""Verify an uninterrupted M2 phone/PC recording pair without uploading audio."""
import argparse
import json
from pathlib import Path
import struct


def wav_info(path):
    path = Path(path)
    with path.open('rb') as stream:
        header = stream.read(12)
        if len(header) != 12:
            raise ValueError('Truncated WAV header')
        magic, size, kind = struct.unpack('<4sI4s', header)
        if magic != b'RIFF' or kind != b'WAVE' or size + 8 != path.stat().st_size:
            raise ValueError('Invalid RIFF sizes or format')
        fmt = payload = None
        while stream.tell() + 8 <= size + 8:
            name, length = struct.unpack('<4sI', stream.read(8))
            offset = stream.tell()
            if offset + length > size + 8:
                raise ValueError('Truncated WAV chunk')
            if name == b'fmt ':
                if fmt is not None or length < 16 or length > 1024:
                    raise ValueError('Invalid or duplicate WAV format')
                fmt = stream.read(length)
            elif name == b'data':
                if payload is not None:
                    raise ValueError('Multiple audio payloads are unsupported')
                payload = (offset, length)
            stream.seek(offset + length + (length & 1))
        if fmt is None or payload is None:
            raise ValueError('Missing WAV format or payload')
        tag, channels, rate, byte_rate, block, bits = struct.unpack('<HHIIHH', fmt[:16])
        is_float = tag == 3 or (tag == 0xfffe and len(fmt) >= 40 and
            fmt[24:40] == bytes.fromhex('0300000000001000800000aa00389b71'))
        if not is_float or channels != 1 or bits != 32 or block != 4 or byte_rate != rate * 4:
            raise ValueError('Expected mono Float32 WAV')
        if rate == 0 or payload[1] % 4:
            raise ValueError('Invalid audio rate or frame alignment')
        return rate, payload[0], payload[1] // 4


def verify(phone_path, pc_path):
    phone_path, pc_path = Path(phone_path), Path(pc_path)
    phone = json.loads(phone_path.with_suffix('.json').read_text())
    pc = json.loads(pc_path.with_suffix('.json').read_text())
    if phone.get('network_completed') is not True or pc.get('pcm_continuity_verified') is not True:
        raise ValueError('A completed, continuous network recording is required')
    for key in ['dropped_frames', 'render_errors', 'discontinuities', 'network_dropped_frames',
                'network_send_errors', 'network_reconnects']:
        if phone.get(key) != 0:
            raise ValueError(f'Phone {key} is nonzero or missing')
    rate, phone_offset, frames = wav_info(phone_path)
    pc_rate, pc_offset, pc_frames = wav_info(pc_path)
    if frames == 0 or (rate, frames) != (pc_rate, pc_frames):
        raise ValueError('Phone and PC formats/frame counts differ or recording is empty')
    if phone.get('frames_written') != frames or pc.get('source_frames_written') != frames:
        raise ValueError('Reported frame counts do not match WAV data')
    if pc.get('sender_first_position') != 0 or pc.get('sender_last_position') != frames:
        raise ValueError('PC does not cover the complete local phone take')
    with phone_path.open('rb') as source, pc_path.open('rb') as received:
        source.seek(phone_offset)
        received.seek(pc_offset)
        remaining = frames * 4
        compared = 0
        while remaining:
            count = min(remaining, 65536)
            left, right = source.read(count), received.read(count)
            if len(left) != count or len(right) != count or left != right:
                raise ValueError(f'PCM differs in block starting at frame {compared // 4}')
            compared += count
            remaining -= count
    return {'sample_rate_hz': rate, 'frames_verified': frames,
            'duration_seconds': frames / rate, 'pcm_bit_exact': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phone_wav', type=Path)
    parser.add_argument('pc_wav', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.phone_wav, args.pc_wav), indent=2))
    except (ValueError, OSError, KeyError, struct.error) as error:
        parser.exit(1, f'Recording verification failed: {error}\n')
