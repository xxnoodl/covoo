# covoo engineering rules

Implement milestones in order; M0 and M1 passed. User approved the M2 handoff with
documented reliability limitations; M3 Stage A is in progress. Stop at physical acceptance gates
until the user confirms results. Never claim unperformed CI or hardware checks.

Keep transport, protocol, capture, clocks, buffering and endpoint integration
separate. No blocking operations, locks, file I/O, UI or unnecessary allocation
in future real-time callbacks. Unsafe Rust requires isolated review and rationale.
No automatic drivers, system security changes, Android or ASIO. M3 Stage A uses an
explicitly selected existing audio endpoint. Driver installation needs explicit approval.
Run cargo fmt --all -- --check, cargo clippy --workspace --all-targets -- -D warnings,
cargo test --workspace --locked, and cargo build --workspace --locked.
Keep diagnostics truthful and document blockers in docs/milestones.

Keep the README, commit messages and updates short. Use plain wording and normal
punctuation. Put detailed setup and milestone reports in docs.

The product name is covoo. Apply the user-facing rename in M2; PhoneMic is the
historical working name. See docs/milestones/M2.md.

M8 is deferred research into optional audio enhancement and microphone modeling.
See docs/milestones/M8.md. Don't implement it during the existing milestones or
promise near-perfect microphone matching without controlled reference tests.
