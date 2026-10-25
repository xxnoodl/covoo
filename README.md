# PhoneMic

iPhone mic for Windows and DAWs. M1 adds local iPhone test recordings.
Device validation is pending. Streaming isn't implemented yet.

Run the Windows checks:

```powershell
powershell -File scripts/verify.ps1
```

Needs Rust and MSVC C++ Build Tools. GitHub Actions builds iOS on a Mac runner.

[Build setup](docs/testing/builds.md) | [Install on iPhone](docs/testing/windows-install.md) | [Status](docs/milestones/M1.md)
