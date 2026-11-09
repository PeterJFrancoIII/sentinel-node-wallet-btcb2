# Sentinel Node Wallet — BTCB2

Standalone, self-custodial **BTCB2 BLAKE2b/BIP-110 MainNet-only** native macOS SwiftUI client for Bitcoin Knots. Three views: **Node, Wallet, Network**, with one Advanced sheet. No remote wallet service or consumer alternative-network mode.

**DEVELOPMENT ONLY — NO PUBLIC / REAL-FUNDS RELEASE.** [Canonical project status: built, in progress, left](docs/PROJECT_STATUS.md) · [Security](SECURITY.md) · [Release matrix](TEST_AND_RELEASE_MATRIX.md).

## Built in source

- Knots RPC, fork/chain anchors, local node status, pruning, persistent Quiet/Balanced/Fast preferences, battery/charging Ultra (**4 max peers, listen=0**), rolling network hashrate and sync ETA.
- Encrypted descriptor wallet creation code, per-wallet RPC, all-wallet inventory, receive/history, coinbase maturity, reversible archive, guarded Trash deletion, staging/backup/restore.
- Local multi-account login, password/TOTP/recovery/step-up framework, Keychain hooks and Apple Passwords candidate integration.
- Neoxa / NonKYC BTCB2 price quotes, source/freshness handling and manual override.
- **Signing and broadcasting remain disabled in core** until independent BTCB2 replay-safe SIGHASH_UNIFIED approval.

**Code implemented ≠ native accepted.** Outstanding Keychain failure handling, wallet creation, daemon adoption, window restore and release evidence are itemized in [Project Status](docs/PROJECT_STATUS.md).

## Development

Requires macOS 13+, Apple Silicon, Swift 5.9+; use a **disposable zero-funds test datadir**. Run tests with `swift test`; inspect `scripts/build_app.sh` and `scripts/build_dmg.sh` before packaging a development artifact. The test suite's Keychain user-presence case requires explicit authorized on-device execution. Do not use an operator wallet or interrupt an active node.

Active review is [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), not merged or production-authorized. See [Contributing](CONTRIBUTING.md), [Architecture](docs/ARCHITECTURE.md), [Agent instructions](AGENTS.md), and [v7 wallet specification](docs/WALLET_MANAGER_V7.md). Historical feature specifications are contracts, not proof of native release acceptance.

License and attribution: see [NOTICE](NOTICE.md).
