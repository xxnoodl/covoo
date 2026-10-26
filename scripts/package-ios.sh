#!/bin/bash
# macOS build artifact for local re-signing. This does not sign or install an app.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/device/Build/Products/Debug-iphoneos/PhoneMic.app
python3 - "$app" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
    sys.exit('Expected a device app, not a simulator app')
if not (app / info['CFBundleExecutable']).is_file():
    sys.exit('App executable is missing')
PY
stage=$(mktemp -d "$PWD/build/ipa-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/PhoneMic.app"
ditto -c -k --keepParent --norsrc "$stage/Payload" build/covoo-unsigned.ipa
python3 - <<'PY'
import plistlib, zipfile
with zipfile.ZipFile('build/covoo-unsigned.ipa') as archive:
    assert archive.testzip() is None
    info = plistlib.loads(archive.read('Payload/PhoneMic.app/Info.plist'))
    assert 'Payload/PhoneMic.app/' + info['CFBundleExecutable'] in archive.namelist()
    assert all(name.startswith('Payload/') for name in archive.namelist())
print('Unsigned device IPA packaged. Local signing is required before installation.')
PY
