# Contributing — Sentinel Node Wallet BTCB2

Read [Project Status](docs/PROJECT_STATUS.md), [Governance](GOVERNANCE.md), [Security](SECURITY.md) and [Agent Rules](AGENTS.md) before editing. Current integration is [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10); do not merge, deploy or claim production readiness without explicit approval.

- **Scope:** clean-room MIT-compatible Swift/SwiftUI macOS Apple Silicon; BTCB2 BLAKE2b/BIP-110 MainNet-only consumer UI, no cross-project code/data, remote RPC or cloud wallet service.
- **Safety:** never touch real funds, operator wallets, keys, backups, Keychain, blockchain state or an adopted live daemon. Test destructive/failure scenarios only in isolated zero-funds fixtures. Keep core send disabled until the independent signing gate is passed.
- **Evidence:** run `swift test` and applicable scripts, verify the actual CI commit, report exact pass/fail/skip and on-device results separately. A mock or optional test is not proof of a production flow.
- **Patches:** minimal reviewed diffs; preserve backwards compatibility and operator data. Follow [test/release matrix](TEST_AND_RELEASE_MATRIX.md); no P0 bypass.
- **Handoffs:** use the [canonical SCM rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md), exact session and message provenance. Never publish secrets or personal wallet metadata.

Release status remains **NO-GO** until all independent security and native acceptance gates pass.
