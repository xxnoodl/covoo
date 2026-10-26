# Builds

Windows needs Rust and Visual Studio C++ Build Tools with the Windows SDK.
Rust version is set in rust-toolchain.toml.

```powershell
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --workspace --release --locked
cargo run -p windows-receiver --locked
```

Or run `powershell -File scripts/verify.ps1`. This also detects the local
toolchain under .tools. Product name: set `PHONEMIC_PRODUCT_NAME`.

On a Mac with Xcode and Homebrew:

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

The generated project is ignored. Product name and bundle ID are in project.yml.
CI records Xcode and XcodeGen versions and uploads build artifacts and logs.
Unsigned iOS artifacts can't establish physical installation.

After generating the project, run the native queue and simulator recording tests
from the repository root:

```sh
bash scripts/test-native.sh
bash scripts/test-ios.sh
bash scripts/test-swift-network.sh
```

The simulator test uses synthetic PCM and does not validate the microphone.
The network test compiles the same Swift sender with Network.framework and
CryptoKit on macOS and checks it against the Rust receiver on loopback.

M2 additions:

```powershell
python -m unittest discover -s tests/interoperability -p test_compare_recordings.py
cargo run --release --locked -p audio-transport --example crypto_bench
```

The Windows artifact contains `covoo-receiver.exe` and `start-receiver.cmd`.
Source builds keep the Cargo binary name `windows-receiver`. The iOS target and
bundle identifier stay unchanged so updates can retain the existing app data;
display/artifact names are covoo. Use PRODUCT_DISPLAY_NAME or COVOO_PRODUCT_NAME
for naming configuration. The historical PHONEMIC_PRODUCT_NAME remains a CLI fallback.
