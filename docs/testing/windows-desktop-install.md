# covoo for Windows

Extract the complete ZIP into a folder first. Open `covoo.exe` to run it there,
or open `install-covoo.cmd` to install for your Windows account and add covoo to
the Start menu. No administrator access or development tools are needed to run
the package. This package is unsigned. Windows may ask about downloaded apps.
Covoo does not change execution policy, firewall rules or other security settings.
If your policy blocks scripts, use the console launchers or your normal trusted
software process; no policy bypass is included.

Choose both a connection/interface and an output in the desktop window, then
Start receiver and scan its QR on your iPhone. Choose `File recording only` to
avoid playing audio. An existing virtual cable is needed for the current DAW
route; this package does not install a covoo microphone or any other driver.
See `Desktop-setup.md` and `DAW-setup.md` for details. A compatible signed iPhone
app is still required; an unsigned IPA is not an installable signed app.

To update, close the desktop, extract the new package and run its installer.
The installer verifies the package's file hashes, copies to a separate build
folder and switches the Start menu entries after copying succeeds. Previous
builds are retained until uninstall. Hashes detect damaged files; they are not a
publisher signature. The package contains no pairing credentials or recordings.

Use Uninstall covoo in the Start menu to remove installed program files and
shortcuts. Saved pairing, preferences and recordings under
`%LOCALAPPDATA%\covoo` are preserved. Uninstall does not revoke pairing. To revoke,
stop the receiver and use Revoke saved pairing before uninstalling. Program files
are under `%LOCALAPPDATA%\Programs\covoo`. Uninstall preserves unexpected files
and refuses corrupted managed files or redirected paths rather than deleting them.

Implementation and automated checks do not establish physical microphone,
headphone, routing, latency or reliability acceptance.
