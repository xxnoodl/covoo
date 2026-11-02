# Windows controls and saved pairing

Use Windows PowerShell 5.1 Windows Forms, shipped with Windows, around the
existing Rust receiver process. No new listener, browser control service,
driver or security setting. The UI owns configuration and polls a read-only
status snapshot; audio remains in the existing independent workers.

The private redirected stdin/stdout channel bootstraps a versioned receiver
identity and requests graceful stop. Credentials never enter command arguments
or logs. Ordinary CLI launches remain ephemeral. The desktop stores certificate,
PKCS#8 key and capability token together using current-user Windows DPAPI under
LocalAppData. Failure to decrypt or validate fails closed, without replacement.
Preferences contain no secrets. A single desktop instance owns this store.

Saving pairing preserves the certificate pin and token, not session audio keys.
Each take still gets fresh UDP keys. The phone stores its validated link only
through an explicit Remember action in a nonsynchronizing, device-only Keychain
item accessible while unlocked. Restoring a link never connects automatically.
Forget on the phone deletes its local secret, not receiver authorization.
Revoke on Windows requires a stopped receiver and deletes its identity; the next
Start generates both a new certificate and token, invalidating all previous links.
Stop alone does not revoke saved pairing. Old private pairing HTML must be removed
on revoke. Address changes require rescanning; discovery never replaces a pin.

DPAPI protects data at rest against other accounts, not code running as this user.
The QR/link is still a bearer credential: protect the recordings folder and never
upload it in artifacts. Local revocation does not delete previously copied QR
pages, but their credentials no longer authenticate to the replacement receiver.
No per-phone revocation, credential sync, password recovery or seamless address
migration is claimed. Corruption requires explicit revoke and pairing again.

References: [Windows DPAPI](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata?view=netframework-4.8),
[Apple Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).
