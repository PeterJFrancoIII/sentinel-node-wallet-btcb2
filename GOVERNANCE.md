# Governance — Sentinel Node Wallet - BTCB2

**Scope:** A minimal, independent, native macOS **BTCB2 BLAKE2b/BIP-110 MainNet-only** validating node and self-custodial wallet. No mining pool, Admin Node Console runtime, TestNet/RegTest/Signet, DATUM gateway or cloud account in this release.

## Canonical documents

1. [Wallet Manager v7](docs/WALLET_MANAGER_V7.md) is the authoritative wallet functional and security contract.
2. [Security policy](SECURITY.md) defines hard release blockers and vulnerability reporting.
3. [Test and release matrix](TEST_AND_RELEASE_MATRIX.md) demands reproducible evidence.
4. [Gemini completion handoff](GEMINI_COMPLETION_HANDOFF.md) defines the next implementation order.
5. README communicates current honest status; it must never overstate code coverage or notarization.

## Minimal engineering rules

- Exactly three user views: Node, Wallet and Network, with one optional Advanced sheet. Wallet functionality expands *inside Wallet*.
- One managed, provenance-verified BLAKE2b-capable Bitcoin Knots process, dedicated app-owned datadir, cookie-authenticated loopback RPC, macOS Keychain; Python only for development tests/mocks, never a shipped Python service.
- Strict isolation from the original Admin Node Console, Sentinel mining pool, EMC and hardware projects. Reference the Admin Wallet Manager source **read only**; no import of private code, address book, wallets, real transaction records, credentials or services.
- Wallet and chain data must survive renaming, app upgrade, pruned/full-history transitions, crashed sync and backup restoration; no silent datadir or bundle ID migration.
- BTCB2 MainNet identity requires consensus checkpoint at block 961,640, subsequent trusted anchors and fresh tip; `chain=main` or `bc1` alone is insufficient.
- Compact by default: `prune=550` and `pruneduringinit=550` MiB, user selects >=550 MiB; monitor total datadir, warn near 35 GiB, graceful stop by 40 GiB or <=10–12 GiB host free. 550 MiB is **not** a full datadir limit.
- Optional full-history archive: explicit opt-in, validated high-capacity external SSD where needed, wallet backup and fresh full-history download/reindex; preserve rollback.
- The entire user-facing app is BTCB2 MainNet only. No alternative-network profiles or binaries exposed through UI. Deterministic mocked RPC tests are allowed without running alternative chains.
- Adaptive synchronization and coinbase-maturity ETAs must be labeled estimates, calibrated from observed network/sync data, with unknown/stalled states.
- **No DATUM Gateway in the current scope.** Reserve future capability only as roadmap text, with its own threat model, UI and acceptance gates if authorized later.

## Wallet v7 P0 gates — failing any blocks live spending

1. **Encrypted-by-default wallet:** Existing code's empty-passphrase default MUST be repaired; no silent creation of unencrypted wallet. No passphrases or seeds in plaintext fallback files.
2. **Per-send user presence:** Appropriate macOS Security.framework/LocalAuthentication consent, expiration and Keychain access controls; test actual device behavior. Login session alone is insufficient.
3. **Consensus and signing:** Correct BTCB2 MainNet, BLAKE2b fork and fresh fully synced tip; ensure the actual signing/broadcast path produces replay-safe `SIGHASH_UNIFIED` signatures. A display badge is not proof.
4. **Recipient allowlist:** Default ON for outgoing payments, enforced within wallet signing code; edits, disables and destination changes need user reauthorization; full address visible for final review.
5. **Preview integrity:** Use fixed-point integer satoshis, non-signing funded preview, exact fee/vsize/inputs/outputs/change and fee caps; approve *specific* immutable wallet/address/amount/fee transaction, then revalidate before signing. Reject changed or stale quote, double-submission and unauthorized caller.
6. **Coinbase maturity:** Determine original reward height and node-confirmed consensus maturity, including 100/6480/25920-height windows and rule expiry; never apply maturity limits to ordinary payment UTXOs.
7. **Secure backup and migration:** Verified restore of encrypted wallet and contact metadata, no duplication or wallet loss when pruned history is absent.
8. **No unsafe fund tests:** No live-funds sends in test runs; mock RPC tests and authorized read-only MainNet observations.

## Development and change control

- Source commits: minimal diffs, code review, full test evidence, and one exact SHA per reported build. Do not count static unit tests as real fork, fee-policy, user-presence or wallet-restore verification.
- Main branch must be reviewed, with CI required when available. This documentation-only branch should merge after audit, independently of app code.
- Security regressions block new packaged distributions even when the prior development DMG launches successfully.
- Avoid collecting private destination addresses, TXIDs, wallet passphrases or metadata in public issue descriptions, screenshots, CI logs or Shared Memory.

## Distribution gates

Public wallet distribution requires valid upstream Knots binary provenance, actual fork/signing evidence, wallet creation/backup/restore security, independently reviewed transaction code, Apple Developer ID signatures on app and embedded binary, notarized/stapled DMG accepted by Gatekeeper, signed Sparkle/EdDSA updates and approved license/third-party notices. Otherwise label artifacts **development only — not suitable for real funds**.

Do not promise a hot wallet is secure against a fully compromised host. Document the limits and provide stronger external-signing/watch-only options as future features if demanded.
