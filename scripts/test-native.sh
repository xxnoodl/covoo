#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cc -std=c11 -Wall -Wextra -Werror -pedantic -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  -I apps/ios/Native apps/ios/Native/PCMQueue.c tests/native/pcm_queue_test.c \
  -o build/pcm-queue-test
./build/pcm-queue-test
cc -std=c11 -Wall -Wextra -Werror -pedantic -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  -I apps/ios/Native apps/ios/Native/MonitorGate.c tests/native/monitor_gate_test.c \
  -o build/monitor-gate-test -lm
./build/monitor-gate-test
