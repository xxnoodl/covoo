# Install from Windows

Experimental developer test route with a regular Apple account. Not yet tested
on the reference iPhone. No paid membership or local Mac is needed for this
route; GitHub's Mac runner compiles the app and AltServer signs it locally.

1. Install [AltServer for Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).
   Follow its Apple iTunes/iCloud requirements. Don't uninstall or replace
   existing Apple software unless its guide requires it for your setup.
2. In the latest successful GitHub Actions run, download `ios-sideload-package`.
   Extract the downloaded ZIP to get `PhoneMic-unsigned.ipa`.
3. Connect and unlock your iPhone, then trust the PC. Open AltServer.
4. Hold Shift while clicking its tray icon, choose `Sideload .ipa`, select your
   phone and the IPA. Sign in directly in AltServer when prompted.
5. Trust your developer app under Settings > General > VPN & Device Management.
   Enable Developer Mode under Privacy & Security if prompted, then restart and confirm.
6. Open PhoneMic and run the [recording check](m1-device.md).

The IPA is unsigned input for the signing tool, not an installable signed build.
AltServer's direct install needs reinstalling/refreshing after 7 days with a free
account. Account limits and signing-service failures can block installation.
This is only a development installation tool, not an audio transport dependency.
Keep Apple credentials in the local signing app, not GitHub secrets or chat.

If it fails, report the exact error and your iOS version. No jailbreak, paid
signing service, MFi hardware or system security bypass is part of this route.

Sources checked 2026-10-25:

- [AltServer Windows setup](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [Direct IPA install and Shift menu](https://faq.altstore.io/release-notes/altserver)
- [Apple free-account limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
