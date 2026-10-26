#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
test_dir=$(mktemp -d "$PWD/build/swift-network.XXXXXX")
cargo build -p windows-receiver --locked
target/debug/windows-receiver --serve --host 127.0.0.1 --port 0 --seconds 90 \
  --no-discovery --output "$test_dir" > "$test_dir/receiver.log" 2>&1 &
receiver_pid=$!
trap 'kill "$receiver_pid" 2>/dev/null || true' EXIT
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
  apps/ios/Sources/WireProtocol.swift apps/ios/Sources/PacketProtection.swift apps/ios/Sources/AudioStreamer.swift \
  tests/interoperability/SwiftNetworkCheck.swift "$test_dir/queue.o" "$test_dir/capture.o" \
  -framework AudioToolbox -framework Network -framework Security -o "$test_dir/client"
"$test_dir/client" "$pairing"
"$test_dir/client" "$pairing" --bad-pin
python3 - "$test_dir" <<'PY'
import array, json, pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
reports = list(root.glob('covoo-*.json'))
assert len(reports) == 1
report = json.loads(reports[0].read_text())
assert report['source_frames_written'] == 48000 and report['packets_not_written'] == 0
assert report['rejected_datagrams'] == 0 and report['malformed_packets'] == 0
assert report['silence_frames_inserted'] == 0 and report['discontinuities'] == 0
assert 0 < report['authenticated_duplicates'] <= 200 and report['authenticated_too_old'] == 0
with reports[0].with_suffix('.wav').open('rb') as f:
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
print('Swift-to-Rust PCM verified: 200 encrypted packets, all 48000 samples exact')
PY
