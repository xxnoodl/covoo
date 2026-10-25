#!/bin/bash
# macOS only. Never enable shell tracing: this script handles signing secrets.
set -euo pipefail
umask 077
: "${IOS_CERTIFICATE_BASE64:?Missing certificate secret}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${IOS_PROFILE_BASE64:?Missing provisioning profile secret}"
: "${IOS_TEAM_ID:?Missing team variable}"
: "${IOS_BUNDLE_ID:?Missing bundle ID variable}"
: "${RUNNER_TEMP:?Run in a disposable macOS Actions runner}"
task_tmp=$(mktemp -d "$RUNNER_TEMP/phonemic-sign.XXXXXX")
keychain="$task_tmp/build.keychain-db"
profile_path=""
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [ -n "$profile_path" ]; then rm -f "$profile_path"; fi
  rm -rf "$task_tmp"
}
trap cleanup EXIT
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$task_tmp/cert.p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 --decode > "$task_tmp/profile.mobileprovision"
security cms -D -i "$task_tmp/profile.mobileprovision" > "$task_tmp/profile.plist"
uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$task_tmp/profile.plist")
[[ "$uuid" =~ ^[A-Fa-f0-9-]+$ ]] || { echo 'Invalid profile UUID'; exit 1; }
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
profile_path="$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
cp "$task_tmp/profile.mobileprovision" "$profile_path"
password=$(openssl rand -hex 32)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$task_tmp/cert.p12" -P "$IOS_CERTIFICATE_PASSWORD" -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
(cd apps/ios && xcodegen generate)
mkdir -p build/signed
xcodebuild -version
xcodebuild -project apps/ios/PhoneMic.xcodeproj -scheme PhoneMic -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/PhoneMic.xcarchive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  DEVELOPMENT_TEAM="$IOS_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$uuid" archive
export IOS_PROFILE_UUID="$uuid"
python3 - <<'PY'
import os, plistlib
with open('build/ExportOptions.plist', 'wb') as f:
    plistlib.dump({
        'method': 'debugging', 'signingStyle': 'manual',
        'teamID': os.environ['IOS_TEAM_ID'],
        'signingCertificate': 'Apple Development',
        'provisioningProfiles': {os.environ['IOS_BUNDLE_ID']: os.environ['IOS_PROFILE_UUID']}
    }, f)
PY
xcodebuild -exportArchive -archivePath build/PhoneMic.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/signed
