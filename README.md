# PhoneMic

iPhone mic for Windows and DAWs. Local iPhone recording passed M1 validation.
Wi-Fi streaming is next. The covoo display-name change is planned for M2.

Run the Windows checks:

```powershell
powershell -File scripts/verify.ps1
```

Needs Rust and MSVC C++ Build Tools. GitHub Actions builds iOS on a Mac runner.

[Build setup](docs/testing/builds.md) | [Install on iPhone](docs/testing/windows-install.md) | [Status](docs/milestones/M1.md)
