# Free iOS build fallback

Codemagic's individual plan offers 500 free macOS M2 minutes per month, checked
November 8, 2026. Team accounts do not receive these free minutes. Keep billing
disabled and use the individual account's remaining free allowance. A workflow
timeout limits each run, not total monthly usage.

## Start a build

1. Sign in at https://codemagic.io/signup with an individual account. Do not
   enable paid billing or create a paid team for this build.
2. Add `https://github.com/xxnoodl/covoo` as an app. Choose the native iOS/YAML
   configuration. The root `codemagic.yaml` must be committed and available on
   the selected branch before Codemagic can load it.
3. Select `desktop-setup` and workflow `ios-unsigned`. Check that the instance
   is `mac_mini_m2` and free minutes remain, then start one manual build.
4. Inspect all steps: project generation, native queue checks, unsigned simulator
   and device builds, and simulator tests must pass before IPA packaging.
5. Download `covoo-unsigned.ipa` and `ios-build-info.txt` from build artifacts.
   Match the recorded revision to the intended source and the IPA's SHA-256
   using `Get-FileHash .\covoo-unsigned.ipa -Algorithm SHA256` on Windows.
   The scanner/background source at `60edd86` uses app version 0.1.0, build 2.
6. Sign/install locally with the existing iLoader procedure in
   [Windows installation](windows-install.md). Apple credentials stay local.
   Confirm About shows build 2, then use the deferred device checks in todo.md.

The workflow has no automatic triggers and uses a 40-minute timeout. It requires
no Apple Developer subscription, signing secrets or App Store integration. The
simulator test script uses local ad-hoc signing only. The device IPA is unsigned.
It does not run the separate Rust/Swift network interoperability, Windows, Linux
or VST3 CI jobs; those checks retain their own status. A successful cloud build
does not accept camera permissions, background audio or physical recording.

## Current verification and blocker

This fallback is prepared locally; no Codemagic build or updated IPA is claimed.
Starting a build requires the user's Codemagic account connection/sign-in and
the configuration on a remotely available branch. No Codemagic tool connection
is available in this session.

On November 8, GitHub's status endpoint reported all systems operational. The
latest repository run remained attempt 2 of 42443412659, failed at 03:54 UTC;
all four jobs had zero steps. The requested retry through the GitHub connector
was refused because that tool requires approval and session policy is `never`.
No new attempt was started, so the account's present billing-lock state is not
verified. No billing settings were changed.

## Sources

- [Individual free minutes and billing](https://docs.codemagic.io/billing/pricing/)
- [Workflow syntax and M2 runner](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)
- [Adding an app](https://docs.codemagic.io/getting-started/adding-apps/)
- [GitHub run](https://github.com/xxnoodl/covoo/actions/runs/42443412659)
- [GitHub service status](https://www.githubstatus.com/)
