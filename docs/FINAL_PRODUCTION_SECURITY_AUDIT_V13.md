# Production Security Audit and Release Gate — Sentinel Node Wallet BTCB2

**Status:** NOT CLEARED — no real funds, production deployment or public distribution. The latest factual register is [PROJECT_STATUS.md](PROJECT_STATUS.md); the [test matrix](../TEST_AND_RELEASE_MATRIX.md) is authoritative for PASS/OPEN. Prior v13 completion language is historical.

## Audit scope (must be independently evidenced)

| Track | Mandatory proof | Status |
|---|---|---|
| Keys and auth | Fail-closed requested Keychain storage, duplicate/migration safety, native user-presence, local multi-user/TOTP/recovery and Apple Passwords signed webcredentials/consent | **OPEN / Keychain P0 FAIL** |
| Wallet correctness | Actual installed-app encrypted descriptor create, inventory update, cancellation/retry, isolated backup→restore, stable wallet identity, crash/durability/permission tests | **OPEN** |
| Daemon/consensus | Bind RPC endpoint to verified PID/executable/datadir, test cookie and bitcoin.conf, secure files, real fork anchors and pinned Knots binary provenance | **OPEN** |
| Signing | Independently verified BTCB2 SIGHASH_UNIFIED, replay protection, integer sats, fee/PSBT exact-output binding, recipient allowlist, one-time step-up and immediate lock | **OPEN; SEND DISABLED** |
| Native behavior | Dock/closed-window/zoom, battery/charging Ultra=4/listen=0, profile persistence, wallet lock and alerts on actual macOS | **OPEN** |
| Distribution | Source/dependency/license/SBOM review, clean binary/signing chain, signed app and embedded daemon, notarized/stapled DMG, Gatekeeper, secure updates, independent auditor | **OPEN** |

## Safety and receipts

Use isolated zero-funds test fixtures; never delete, restart, unlock, rename or restore over operator assets; do not modify live blockchain state. Recheck PR SHA and CI before every claim. A mock, green unit test, peer-reported desktop result, code signing or notarization alone is not proof of fund safety.

Report PASS/FAIL/NOT RUN/SKIPPED with redacted commands, environment, exact code/build hash, test count and tester identity. Keep immutable historical receipts. Close each P0 only with independent positive and adversarial evidence; absent that, retain **NO-GO**. See [Security](../SECURITY.md) and [Agent handoff](V13_1_MAIN_AGENT_HANDOFF_20261107.md).
