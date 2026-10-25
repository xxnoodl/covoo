# PhoneMic engineering rules

Implement milestones in order; this repository is at M0. Do not begin M1 until
M0 build checks are resolved and reported. Stop at physical acceptance gates
until the user confirms results. Never claim unperformed CI or hardware checks.

Keep transport, protocol, capture, clocks, buffering and endpoint integration
separate. No blocking operations, locks, file I/O, UI or unnecessary allocation
in future real-time callbacks. Unsafe Rust requires isolated review and rationale.
No automatic drivers, system security changes, Android, ASIO or streaming in M0.
Run cargo fmt --all -- --check, cargo clippy --workspace --all-targets -- -D warnings,
cargo test --workspace --locked, and cargo build --workspace --locked.
Keep diagnostics truthful and document blockers in docs/milestones.

Keep the README, commit messages and updates short. Use plain wording and normal
punctuation. Put detailed setup and milestone reports in docs.
