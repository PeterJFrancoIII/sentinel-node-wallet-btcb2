# Agent instructions — Sentinel Node Wallet - BTCB2

**Canonical current wallet contract:** [docs/WALLET_MANAGER_V7.md](docs/WALLET_MANAGER_V7.md)  
**Primary project:** Native SwiftUI macOS Bitcoin Knots **BTCB2 BLAKE2b/BIP-110 MainNet-only** validating node and non-custodial wallet.

## What is in scope

Maintain exactly three main surfaces: **Node, Wallet, Network**, plus one small Advanced sheet. The Wallet surface must be mature/immature-aware, fee-aware, history-rich and secure. Python is permitted as a test/mocking and automation tool; **no Python runtime or web backend** is shipped to consumers.

**No DATUM gateway in this release.** Future one-click DATUM support is roadmap-only. No Stratum, pool, rental, miner or remote-wallet integration now.

## Read-only references and isolation

Original private Admin Node Console Wallet Manager (`src/status_server.py` and `src/wallet_registry.py`) may be read for behavioral parity; NEVER copy its live code, database, real wallet data/addresses, credentials or integration services. No writes to Sentinel Pool, Ethereum Mining Corp, Admin Console, BM-S3 firmware, or other project repos/runtimes. Retain historical app bundle ID, Keychain service and datadir until a reversible migration is proved. Existing running node and wallet are not disposable test fixtures.

## Immediate P0 items

1. Remove empty-passphrase wallet creation, unencrypted default wallet, `tb1`/`bcrt1` acceptance and insecure auto-Keychain unlocking.
2. Validate actual BLAKE2b fork, new chain anchor/fresh tip, encrypted wallet, BTCB2 replay-safe `SIGHASH_UNIFIED` signing and allowlist **inside core send pipeline**; UI badges or local height are insufficient.
3. Use satoshi integers, local-node fee quotes/relay floor and PSBT funded preview; bind user presence + exact destination, amount, fee/inputs/change to one-time broadcast authorization; immediately lock wallet afterward.
4. Add coinbase creation-height maturity schedule (100/6480/25920 blocks plus 2027-09-01 MTP rule), maturation countdown, transaction details, verified BTCB2 `mempool.guide` external links and named trusted recipients with secure edit controls.
5. Add Swift/Python mock tests and real Security.framework consent/chain read-only tests; never spend real funds to test. Mark all v7 gates NOT RUN until evidenced.

## Release and reporting

No public or real-funds-safe release before P0s, clean wallet restore, Apple Developer ID signing and notarization, Gatekeeper, secure updates and independent audit. Read [GOVERNANCE.md](GOVERNANCE.md), [SECURITY.md](SECURITY.md), [TEST_AND_RELEASE_MATRIX.md](TEST_AND_RELEASE_MATRIX.md) and [GEMINI_COMPLETION_HANDOFF.md](GEMINI_COMPLETION_HANDOFF.md).

Follow existing Shared Cognitive Memory rules. Post one redacted evidence receipt with exact commit, test results and PASS/FAIL/NOT RUN, not unverified 'complete' claims. Do not leak addresses, keys or user-specific transaction data into Shared Memory or GitHub.
