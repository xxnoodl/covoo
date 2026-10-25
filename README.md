# PhoneMic

Windows-first iPhone microphone project. **M0 foundation only; Windows checks
pass, macOS CI acceptance pending.** No capture, streaming, virtual microphone, drivers or ASIO.
Working product name is configurable, independent of package identifiers.

## Build on Windows

Install Visual Studio C++ Build Tools (Desktop development with C++, MSVC x64,
Windows SDK), then Rust via https://rust-lang.org/install.html . Open a new
PowerShell in this repository:

```powershell
rustup show
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --workspace --release --locked
cargo run -p windows-receiver --locked
$env:PHONEMIC_PRODUCT_NAME = 'MyMic'
cargo run -p windows-receiver --locked
```

Rust is pinned in rust-toolchain.toml. There are no external Rust dependencies.
Alternatively run `powershell -File scripts/verify.ps1` for the same checks. It
also detects the ignored workspace-local toolchain, if installed during setup.
The receiver is a console executable with truthful unavailable-state diagnostics.
It does not enumerate audio endpoints or open network sockets. Linux CI checks
shared-code portability; Windows 11 is the desktop product target.

## Build on a Mac or macOS CI

Install Xcode and select it as the active developer directory. Install Homebrew
and XcodeGen, then:

```sh
cd apps/ios
brew install xcodegen
xcodegen generate
xcodebuild -version
xcodebuild -project PhoneMic.xcodeproj -scheme PhoneMic -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PhoneMic.xcodeproj -scheme PhoneMic -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The generated project is intentionally ignored. Change PRODUCT_DISPLAY_NAME and
PRODUCT_BUNDLE_IDENTIFIER in apps/ios/project.yml for your product/team. iOS 17
is the deployment minimum, not the selected SDK version. Build workflow logs
record the actual Xcode, Swift and XcodeGen versions; XcodeGen via Homebrew is
currently unpinned and must be pinned after the first successful macOS run.

Push to a GitHub repository to run `.github/workflows/build.yml`, or dispatch it
through Actions. CI uploads the Windows binary and unsigned iOS app/build logs.
Unsigned apps are compilation artifacts, not installable device releases.

See [architecture decision](docs/decisions/0001-m0-foundation.md),
[codec contract](docs/protocols/audio-v1.md),
[iPhone deployment](docs/testing/ios-deployment.md), and
[M0 verification report](docs/milestones/M0.md).
