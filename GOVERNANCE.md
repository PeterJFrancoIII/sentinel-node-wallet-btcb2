# Governance — Sentinel Node Wallet - BTCB2

**Scope:** A minimal, independent, native macOS **BTCB2 BLAKE2b/BIP-110 MainNet-only** validating node and self-custodial wallet. No mining pool, Admin Node Console runtime, TestNet/RegTest/Signet, DATUM gateway or cloud account in this release.


## Current v13.1 governance checkpoint — 2026-11-07 (America/New_York)

**Status: DEVELOPMENT ONLY, NOT PUBLIC/REAL-FUNDS-READY.** The current incoming-main-agent source of truth is [v13.1 agent-transfer handoff](docs/V13_1_MAIN_AGENT_HANDOFF_20261107.md). Read it before executing old v12/v13 notes below, which remain contracts/history but may describe superseded implementation status.

- Development [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10): `fix/v13-1-security-remediation-20261107`, **open and not merged into `main`** at evidence commit `03216baa2b2ea6a2aec45d3920410d8c8c0ed569`.
- Evidence [macOS CI 42439761927](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42439761927): **91 executed, 90 passed, zero failed, one interactive hardware-Keychain test skipped**. This is source/automated-test evidence only.
- Implemented in the review branch: core local-auth enforcement; multi-wallet operator fixes; configured/effective peer ceiling with Ultra 4/`listen=0` in source; user profile placement; encrypted-wallet backup using isolated staging, descriptor-anchored verification, no-overwrite atomic publication, recovery guards and mocked failure-path tests. `WalletManager` real-funds send is still **fail-closed / disabled**.
- Gemini [receipt #061](docs/V13_1_MAIN_AGENT_HANDOFF_20261107.md) **reports** a real isolated Knots regtest encrypted descriptor-wallet backup/restore and undisturbed MainNet sync. The native test is **agent-reported**, not independently reproduced by this governance review; request reproducible redacted artifacts before upgrading its status.
- Remaining blockers: operator-visible backup durability warning and fault/recovery review; signed-app Keychain/Touch ID and Apple Passwords save/autofill; native Ultra/peer transition; fork-binary provenance and `SIGHASH_UNIFIED` audit; independent security and signed/notarized distribution. [Current release evidence matrix](TEST_AND_RELEASE_MATRIX.md).
- This is **no-feature-addition / release freeze**: only bug fixes, evidence, safety and compliance work. Preserve existing wallets, Keychain, chainstate, datadir, IBD and user configuration. Isolated temporary regtest is allowed for development-only verification; do not ship or expose alternative networks in the public application.

## Canonical documents

1. [V12 Ultra Power Policy & All-Wallet Inventory](docs/POWER_WALLET_INVENTORY_V12.md) is the authoritative power management, multi-wallet inventory, and UI contract.
2. [Wallet Manager v7](docs/WALLET_MANAGER_V7.md) is the authoritative wallet functional and security contract.
3. [Security policy](SECURITY.md) defines hard release blockers and vulnerability reporting.
4. [Test and release matrix](TEST_AND_RELEASE_MATRIX.md) demands reproducible evidence.
5. [Current v13.1 main-agent handoff](docs/V13_1_MAIN_AGENT_HANDOFF_20261107.md) is the authoritative current-state and next-work instruction. [Gemini completion handoff](GEMINI_COMPLETION_HANDOFF.md) is historical.
6. README communicates current honest status; it must never overstate code coverage or notarization.

## Minimal engineering rules

- Exactly three user views: Node, Wallet and Network, with one optional Advanced sheet. Wallet functionality expands *inside Wallet*.
- One managed, provenance-verified BLAKE2b-capable Bitcoin Knots process, dedicated app-owned datadir, cookie-authenticated loopback RPC, macOS Keychain; Python only for development tests/mocks, never a shipped Python service.
- Strict isolation from the original Admin Node Console, external mining pools, and hardware projects. Reference the Admin Wallet Manager source **read only**; no import of private code, address book, wallets, real transaction records, credentials or services.
- Wallet and chain data must survive renaming, app upgrade, pruned/full-history transitions, crashed sync and backup restoration; no silent datadir or bundle ID migration.
- BTCB2 MainNet identity requires consensus checkpoint at block 961,640, subsequent trusted anchors and fresh tip; `chain=main` or `bc1` alone is insufficient.
- Compact validating node by default: NEW installs `prune=2048` MiB, `pruneduringinit=550` MiB; custom >=550 MiB. Preserve every EXISTING user's 550/custom retention and archive state, and keep storage independent of Quiet/Balanced/Fast. Monitor full datadir, warn near 35 GiB and gracefully stop by 40 GiB or <=10–12 GiB host free. Block retention is **not** a complete datadir limit.
- Optional full-history archive: explicit opt-in, validated high-capacity external SSD where needed, wallet backup and fresh full-history download/reindex; preserve rollback.
- The entire user-facing app is BTCB2 MainNet only. No alternative-network profiles or binaries exposed through UI. Deterministic mocked RPC tests and isolated temporary developer-run regtest wallets are allowed for development verification only; neither is exposed or distributed as a consumer network.
- Adaptive synchronization and coinbase-maturity ETAs must be labeled estimates, calibrated from observed network/sync data, with unknown/stalled states.
- **No DATUM Gateway in the current scope.** Reserve future capability only as roadmap text, with its own threat model, UI and acceptance gates if authorized later.

- Minimal consensus-security peer policy: default Balanced par=2/cache512MiB/maxconnections24, Quiet 1/256/16 and Fast 4/1024/32. Relay full blocks and transactions and permit inbound P2P when reachable, but explicitly disable NAT-PMP/UPnP auto-mapping and NEVER expose RPC; peer limit is a ceiling, not a guaranteed number of peers. Preserve wallet data and user-selectable Quiet/Fast/profile settings. [Canonical v10 node policy](docs/MINIMAL_CONSENSUS_SECURITY_V10.md).

## Rolling historical ledger coverage

The **Storage Footprint** selector must show two separate quantities: (1) the *observed* time depth of locally retained blockchain files based on Knots `getblockchaininfo.pruneheight` and verified local header timestamps, and (2) a *projected* approximate time depth for the selected pruning MiB based on current block/undo-file storage density. Forecasts recalculate without additional RPC on each keystroke; read-only polling is capped to once per 120 seconds. Display the most meaningful years/months/weeks/days/hours with `~` and calibration status when the node is in IBD or no reliable byte data exists. Clearly distinguish retained block history from full consensus validation, money insurance, archival access, wallet recovery and deep-reorg guarantees. [v11 storage coverage specification](docs/ROLLING_HISTORY_COVERAGE_V11.md).

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
- Main branch must be reviewed, with CI required when available. The current PR #10 is an app-code development branch, not a documentation-only release; it must not merge as a production build until P0 gates and independent audit are cleared. Separately reviewed documentation may be cherry-picked without deploying unsafe wallet code.
- Security regressions block new packaged distributions even when the prior development DMG launches successfully.
- Avoid collecting private destination addresses, TXIDs, wallet passphrases or metadata in public issue descriptions, screenshots, CI logs or Shared Memory.

## v13.1 — Apple Passwords operator onboarding clarification

The last owner-authorized onboarding change offers user-controlled strong login-password generation, system-mediated Apple Passwords credential save only when correct associated-domain entitlements and signed macOS application are available, and user-approved 2FA verification-code setup via Apple's apple-otpauth handler. The operator's TOTP verifier key must stay independently secured in the application Keychain. Neither opening the system dialog nor saving a generic app Keychain password proves the user has a saved Apple Passwords login. Mark success only after owner/device verification. [Framework and Mac tests](docs/APPLE_PASSWORDS_OPERATOR_SETUP_V13_1.md).

## Final feature change and release freeze — v13

The owner requires ONE final Wallet-tab authentication modification: username, strong password and RFC6238 TOTP on a completely local account, with truthful Apple Passwords save/autofill and fresh independent macOS owner-presence for sensitive actions. See [v13 implementation contract](docs/FINAL_WALLET_AUTH_V13.md). Keep Node and Network online without login. Generic Keychain access is not Apple Passwords and a password/TOTP gate does not cryptographically stop same-user/root malware or RPC access without core-level wallet protection.

Following v13, no additional non-security features may be introduced before [all-surfaces production and code-reduction audit](docs/FINAL_PRODUCTION_SECURITY_AUDIT_V13.md). Require explicit signed app/embedded Knots provenance, wallet recovery, replay-safe signing, owner-approved license, source-to-binary audit and independent review. Prior v12 Ultra Battery correction is **4** max peers + `listen=0`, not Gemini's reported 12.

Production signoff is evidence-driven, not unit-test-count-driven. An Apple Passwords account association requires an owner-authorized webcredentials domain, static AASA and valid signed Team ID/bundle ID; no unrelated business/pool website is used by default. A P0 entitlement or Keychain error cannot trigger a silent downgrade of wallet credential protection.

## Distribution gates

Public wallet distribution requires valid upstream Knots binary provenance, actual fork/signing evidence, wallet creation/backup/restore security, independently reviewed transaction code, Apple Developer ID signatures on app and embedded binary, notarized/stapled DMG accepted by Gatekeeper, signed Sparkle/EdDSA updates and approved license/third-party notices. Otherwise label artifacts **development only — not suitable for real funds**.

Do not promise a hot wallet is secure against a fully compromised host. Document the limits and provide stronger external-signing/watch-only options as future features if demanded.
