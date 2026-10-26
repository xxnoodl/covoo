# covoo

iPhone mic for Windows and DAWs. M1 capture passed. M2 adds encrypted LAN
streaming to a Windows WAV receiver; phone-to-PC validation is pending.

Run the Windows checks:

```powershell
powershell -File scripts/verify.ps1
```

Needs Rust and MSVC C++ Build Tools. GitHub Actions builds iOS on a Mac runner.

[Build setup](docs/testing/builds.md) | [Phone-to-PC test](docs/testing/m2-device.md) | [Status](docs/milestones/M2.md)
