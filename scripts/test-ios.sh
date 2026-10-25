#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../apps/ios"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
runtime="com.apple.CoreSimulator.SimRuntime.iOS-${sdk//./-}"
export PM_SIM_RUNTIME="$runtime"
device=$(xcrun simctl list devices available --json | python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"].get(os.environ["PM_SIM_RUNTIME"], [])
matches = [d["udid"] for d in devices if d["name"].startswith("iPhone")]
if not matches:
    sys.exit("No iPhone simulator for selected SDK runtime")
print(matches[0])
')
xcodebuild -project PhoneMic.xcodeproj -scheme PhoneMic -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath ../../build/simulator-tests -resultBundlePath ../../build/ios-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee ../../build/ios-tests.log
