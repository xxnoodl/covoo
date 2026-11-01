#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
test_dir=$(mktemp -d "$PWD/build/swift-network.XXXXXX")
cargo build -p windows-receiver --locked
target/debug/windows-receiver --serve --host 127.0.0.1 --port 0 --seconds 90 \
  --no-discovery --output "$test_dir" > "$test_dir/receiver.log" 2>&1 &
receiver_pid=$!
proxy_pid=""
trap 'kill "$receiver_pid" 2>/dev/null || true; if [ -n "$proxy_pid" ]; then kill "$proxy_pid" 2>/dev/null || true; fi' EXIT
for _ in {1..100}; do
  if [ -f "$test_dir/pairing.html" ]; then break; fi
  sleep 0.1
done
pairing=$(python3 - "$test_dir/pairing.html" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
print(re.search(r'<textarea[^>]*>([^<]+)</textarea>', text).group(1))
PY
)
clang -std=c11 -Wall -Wextra -Werror -I apps/ios/Native -c apps/ios/Native/PCMQueue.c -o "$test_dir/queue.o"
clang -std=c11 -Wall -Wextra -Werror -I apps/ios/Native -c apps/ios/Native/CaptureBridge.c -o "$test_dir/capture.o"
swiftc -swift-version 5 -import-objc-header apps/ios/Native/PhoneMic-Bridging-Header.h \
  apps/ios/Sources/WireProtocol.swift apps/ios/Sources/PacketProtection.swift apps/ios/Sources/TakeDelivery.swift apps/ios/Sources/AudioStreamer.swift \
  tests/interoperability/SwiftNetworkCheck.swift "$test_dir/queue.o" "$test_dir/capture.o" \
  -framework AudioToolbox -framework Network -framework Security -o "$test_dir/client"
"$test_dir/client" "$pairing"
"$test_dir/client" "$pairing" --fast
"$test_dir/client" "$pairing" --bad-pin
"$test_dir/client" "$pairing" --fast --idle-pause
python3 - "$test_dir" <<'PY'
import array, json, pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
reports = list(root.glob('covoo-*.json'))
assert len(reports) == 3
for path in reports:
    report = json.loads(path.read_text())
    assert report['pcm_continuity_verified'] and report['source_frames_written'] == 48000
    assert report['packets_not_written'] == 0
    assert report['rejected_datagrams'] == 0 and report['malformed_packets'] == 0
    assert report['silence_frames_inserted'] == 0 and report['discontinuities'] == 0
    assert 0 < report['authenticated_duplicates'] <= 200 and report['authenticated_too_old'] == 0
    with path.with_suffix('.wav').open('rb') as f:
        assert f.read(4) == b'RIFF'
        f.read(8)
        while True:
            name, size = struct.unpack('<4sI', f.read(8))
            if name == b'data':
                samples = array.array('f'); samples.frombytes(f.read(size)); break
            f.seek(size+(size&1),1)
    if sys.byteorder != 'little': samples.byteswap()
    assert len(samples) == 48000
    assert all(v == (i%31-15)/32 for i,v in enumerate(samples))
print('Swift-to-Rust PCM verified: stable, fast and idle pause/resume, 144000 exact samples total')
PY

target_port=$(python3 - "$pairing" <<'PY'
import sys, urllib.parse
print(urllib.parse.parse_qs(urllib.parse.urlsplit(sys.argv[1]).query)['port'][0])
PY
)
python3 tests/interoperability/control_drop_proxy.py --target-port "$target_port" \
  --port-file "$test_dir/proxy.port" --trigger "$test_dir/drop-trigger" &
proxy_pid=$!
for _ in {1..100}; do
  if [ -f "$test_dir/proxy.port" ]; then break; fi
  sleep 0.1
done
proxy_pairing=$(python3 - "$pairing" "$test_dir/proxy.port" <<'PY'
import pathlib, sys, urllib.parse
url = urllib.parse.urlsplit(sys.argv[1])
query = urllib.parse.parse_qsl(url.query)
port = pathlib.Path(sys.argv[2]).read_text().strip()
print(urllib.parse.urlunsplit(url._replace(query=urllib.parse.urlencode([(k, port if k == 'port' else v) for k,v in query]))))
PY
)
"$test_dir/client" "$proxy_pairing" --fast --reconnect --drop-trigger "$test_dir/drop-trigger"
python3 - "$test_dir" <<'PY'
import json, pathlib, sys
reports = [json.loads(p.read_text()) for p in pathlib.Path(sys.argv[1]).glob('covoo-*.json')]
assert len(reports) == 5
assert sum(not r['sender_final_summary_received'] for r in reports) == 1
assert sum(r['pcm_continuity_verified'] and r['sender_first_position'] > 0 for r in reports) == 1
print('Receiver reports retain aborted segment and separately finalized resumed segment')
PY
