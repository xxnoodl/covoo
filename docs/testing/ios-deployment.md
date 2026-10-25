# iOS builds, signing and physical installation

## What is possible now

Windows can edit Swift and project.yml, and run Rust checks. macOS with full
Xcode is required to generate/compile this app. Generic simulator/device builds
in build.yml disable signing and need no Apple credentials. Neither proves
installation or microphone operation. Hosted macOS CI has no access to the
developer's iPhone and provides no interactive physical-device debugging.

The repository is connected to `xxnoodl/covoo`; unsigned iOS CI has passed.
No signing or device setup is needed for M0. The steps below are for later
installation on your phone, not immediate tasks.

## Signing choices

For local personal testing, an Apple Account with Xcode Personal Team can install
on personal devices, with short-lived provisioning and capability limits. This
requires access to an actual Mac with Xcode and a supported connection to the
phone; a hosted runner cannot pair with the phone attached to Windows.

For the manual CI signing path, use an Apple Developer Program team with access
to Certificates, Identifiers & Profiles. Register the iPhone's UDID, choose a
unique explicit bundle identifier, create an Apple Development certificate and
a matching development profile including that device. The certificate must be
exported as password-protected .p12 **including its private key** from the Mac
where the key was created. A downloaded .cer alone is insufficient.

In a GitHub environment named `ios-development`, configure:

| Kind | Name | Value |
|---|---|---|
| Secret | IOS_CERTIFICATE_BASE64 | Base64 of .p12 |
| Secret | IOS_CERTIFICATE_PASSWORD | .p12 password |
| Secret | IOS_PROFILE_BASE64 | Base64 of development .mobileprovision |
| Variable | IOS_TEAM_ID | Apple team ID |
| Variable | IOS_BUNDLE_ID | Exact profile app bundle ID |

Generate base64 locally (never commit the output):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('certificate.p12')) | Set-Clipboard
# Paste into the corresponding GitHub environment secret, then clear clipboard.
[Convert]::ToBase64String([IO.File]::ReadAllBytes('profile.mobileprovision')) | Set-Clipboard
Set-Clipboard -Value ''
```

Restrict the environment to trusted branches and reviewers as appropriate.
Dispatch `iOS development build (manual)` on trusted code only. The script imports
credentials into an ephemeral keychain, archives and exports using the supplied
profile, then removes imported files/keychain on exit. No credentials are needed
for pull-request CI. Signed artifacts contain provisioning information; access
and retention should be limited. This workflow has not yet been exercised.
Expired profiles, wrong UDID, mismatched key/certificate, team or bundle ID must
be corrected rather than bypassing signing. No App Store/TestFlight path is added.

## Install and inspect on a physical iPhone 14

The supported initial procedure requires a Mac that can actually connect to the
phone (borrowed or otherwise accessible); a remote Mac alone does not supply a
USB connection. Generate the Xcode project, open PhoneMic.xcodeproj, select the
correct team/bundle ID under Signing & Capabilities and select the connected
iPhone. Trust the host on the phone. Enable Developer Mode under Privacy &
Security when prompted, restart and confirm. Build and Run from Xcode. For a
CI-exported development IPA, use Xcode Devices and Simulators to install it on
the registered device. An unsigned .app or IPA is not a substitute.

Record OS/device/build versions, launch result, visible M0 state and any errors.
M0 must show inactive capture/transport and no measured latency; no permission
prompt is expected. Do not mark installation complete until this is performed.
Windows-only IPA sideload/debug tooling is not validated or required by this
project. If Mac/device access is unavailable, physical acceptance remains blocked.

Use Xcode's attached-device console/Console.app for logs. Retrieve device crash
reports through Devices and Simulators; retain matching archive/dSYMs and build
ID for symbolication. On the phone, Analytics Data in Privacy & Security can
provide shareable crash reports. Redact identifiers before sharing. A remote
Mac can inspect exported logs/crashes; live capture and debugging still require
a supported device connection. CI .xcresult bundles diagnose build failures,
not microphone performance. M1 will add capture diagnostics and a test recording.

## Official sources (checked 2026-10-25)

- [Apple account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Device registration](https://developer.apple.com/help/account/devices/register-a-single-device/)
- [Registered-device distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Xcode command-line tools](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [Windows Rust prerequisites](https://learn.microsoft.com/en-us/windows/dev-environment/rust/setup)
- [GitHub certificate/keychain guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
