# Sentinel Node Wallet BTCB2 — Project Status

**Snapshot:** 2026-11-10 (America/New_York). **Status:** development candidate; **production, public distribution and real funds: NO-GO**.
**Code baseline:** [2aa0e15](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/commit/2aa0e155329c141cbee72a9ea8adb1b20ccb392a) on [open PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), branch fix/v13-1-security-remediation-20261107; not merged to main.
**CI:** [42938948275](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42938948275): 133 executed, **132 passed, 0 failed, 1 skipped** (interactive Keychain). A green build is not native-app or wallet-security certification.

**Evidence labels:** **BUILT** = present in source; **PEER-REPORTED** = another agent's runtime claim, not independently reproduced; **OPEN** = failing, unproven or missing acceptance; **GATE** = mandatory before release. Do not turn source presence or peer receipts into a native PASS.

## Built in source (not all release-qualified)

| Area | Built / implemented |
|---|---|
| Native app | SwiftUI Node / Wallet / Network views; one Advanced sheet; autonomous startup flow; status, health and sync telemetry. |
| Node | BTCB2 BLAKE2b/BIP-110 MainNet-only Knots RPC and fork-anchor checks; quiet/balanced/fast profiles; persisted pruning/inbound preferences; rolling history, hashrate and ETA; battery/charging Ultra target **4 peers, listen=0**. |
| Wallet | Explicit encrypted-descriptor create path with RPC preflight and indeterminate-commit reconciliation; per-wallet RPC; loaded/on-disk inventory and nondestructive archive; **Trash deletion temporarily blocked until independently verified isolated recovery**, address/history/maturity and backup/restore infrastructure. |
| Access | Local multi-user username/password, RFC6238 TOTP, recovery codes, short-lived wallet capability and step-up framework; Keychain integration; Apple Passwords-oriented UI hooks. |
| Pricing | Neoxa/NonKYC BTCB2 quote service, attribution, freshness handling and manual override path. |
| Security | Backup staging, non-clobber publication and receipt logic; core signing/broadcast/RBF re-disabled at c19332b (wallet actor + generic RPC + UI); 2 new regression tests pass. BTCB2 SIGHASH_UNIFIED remains unaudited. |
| Recent repairs | #069 RPC-stage diagnostics; #070 Dock/window restoration; #071 daemon-adoption recognition of owned .cookie **or** bitcoin.conf plus typed rejection errors; #075 receive address store and strict userPresence capability reconciliation; #076 single-window lifecycle close-to-hide and targeted mainWindow restore; #077 live daemon 1-click launch and end-to-end encrypted descriptor wallet creation/lock/unlock/address qualification; #078 wallet renaming, RBF bump fee, pending vs confirmed spendable balance isolation, and live mempool percentile fee intelligence; #079 sync-gated hashrate tracker with 30-block consensus derivation, a previously armed send pipeline with Bech32 validation, allowlist, estimated funded preview and deferred relock (P0 security regression); **c19332b restores unconditional send/RBF hold**. Live USD fiat preview remains informational. |

## In progress — independently identified defects / proof gaps

**NEW SOURCE/CI MILESTONE: FAIL-CLOSED DELETION AND RELEASE EXECUTABLE COMPILE.** Code 2aa0e15 removes the prior `try?` live-daemon restore that ignored failure before moving wallet files to Trash. Core deletion is now prohibited without an independent isolated Knots encrypted-wallet recovery proof; current implementation deliberately rejects all deletion attempts, even with a durable receipt. SwiftUI disables Trash and directs the operator to Archive. The previous opt-in destructive test targeting the real Application Support datadir was removed. [macOS CI 42938948275](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42938948275) passes 132/133 tests (one interactive Keychain skip), the optimized `NodePocketApp` Release-mode compile, and packaging shell syntax. New guarded Developer ID/AASA/notary DMG script is **SOURCE ONLY, NOT RUN with owner credentials and NOT released**. See [Production release checklist](PRODUCTION_RELEASE_CHECKLIST.md).


**P0 SEND SAFETY SOURCE/CI REPAIRED:** The earlier #079 sendtoaddress and bumpfee paths contradicted the production freeze. c19332b now throws before unlock/broadcast at WalletManager, denies known sign/send/bump RPC methods in the generic client and keeps the UI disabled, regardless of IBD. [CI 42931815052](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42931815052) confirms 2 new regressions (130/131 pass, one Keychain skip). **No signed-Mac acceptance, no authorized spending and no independent fork-signing proof**. The local Knots daemon and any external RPC clients remain outside this application's guarantee.


1. **P0 Keychain custody — source remediation CI PASS, native verification OPEN:** Source at `5e7a597` blocks `createwallet` when requested Keychain storage fails or an existing credential cannot be verified. All five new deterministic Keychain custody tests passed in CI `42705121938`. Matching duplicate entries require interactive verification; existing entries are never implicitly replaced by the creation path. Explicit offline-custody choice remains a separate UI action. **Do not mark native PASS until real signed-Mac Keychain and wallet-create evidence is collected.**
2. **P0 Wallet creation — EMPIRICALLY VERIFIED ON LIVE DAEMON (#077):** Successfully executed full end-to-end lifecycle on live Bitcoin Knots daemon (PID 4458) with `ephemeral_gate2_test_wallet`: SQLite descriptor encryption (`createwallet`), immediate locked custody (`unlocked_until: 0`), incorrect passphrase fail-closed rejection (`RPC_WALLET_PASSPHRASE_INCORRECT: -14`), valid passphrase unlock (`walletpassphrase`), bech32 BIP-84 address derivation (`getnewaddress` -> `bc1qd95srg8slp5xy2c2f2ykjmy7jpcy3npmk7yhlr`), re-locking (`unlocked_until: 0`), and clean unload. Operator wallet `Kevin` remained locked (`unlocked_until: 0`) and completely untouched.
3. **P0 Daemon adoption:** Prove successful positive bitcoin.conf and cookie-only paths on isolated Knots; bind the authenticated RPC listener to the verified live PID/executable/datadir; reject symlinks/unsafe file types, permissions and non-credential conf files. #071 new tests prove negative cases only; conditional live test may return without testing.
4. **P1 Window restoration — RESOLVED (#076):** Implemented `NSWindowDelegate.windowShouldClose` close-to-hide, targeted `mainWindow` lifecycle tracking via `WindowAccessor`, zero-window elimination on Dock reopen, and removal of unsafe forced unwrap.
5. **P0 Backup/restore:** Independently verify staging/FD failure cleanup, crash/race and volume durability semantics, user-visible warnings and fresh-wallet encrypted backup-to-restore using the installed signed app.

## Left before public/real-funds release (GATES)

- Owner-approved Apple Passwords webcredentials/AASA/Team ID/bundle signing and real consent/AutoFill/2FA/Keychain user-presence tests (the skipped CI test must run on an authorized Mac).
- Independent fork-specific BTCB2 SIGHASH_UNIFIED/signing and fee/PSBT/allowlist/replay-safety audit; **do not enable send** without approval and proof.
- Real macOS battery/charging Ultra and profile transitions, native window/user-account/isolation QA, trusted Knots binary/checkpoint and RPC/daemon provenance.
- Developer ID signing of app **and** embedded daemon, notarization/stapling, Gatekeeper, secure update chain, SBOM/license and independent security review. No existing real wallet, Keychain item, chainstate or IBD may be modified to perform tests.

## Operating rules and evidence

**SCOPE_LOCK=NODEPOCKET_BTCB2_ONLY.** Zero live funds, production wallet mutations, process restarts, remote RPC, external-project changes, or merge/deployment without explicit separate operator approval. Use isolated zero-funds datadirs and redact all credentials, addresses and personal records.

Canonical SCM session: **Session_Gemini_NodePocketBTCB2_20261106-1741**; bus **InterAgent_Dialogue_Channel**. Last peer receipt: **MSG:SENTINEL-DAEMON-ADOPT-REPAIR-RECEIPT-20261109-071** (earlier #069 wallet RPC; #070 windows). Follow [Shared Memory rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md); search_nodes → open_nodes; retain author/message provenance. Receipt #071's live adoption, signed bundle and undisturbed operator wallet are **peer-reported**, not independently demonstrated in this audit.

**Next sequence:** verify fail-closed Keychain creation and signed-Mac behavior → isolated native create/restore → positive and adversarial daemon adoption → native windows/auth/Ultra → signing/binary/release audit. Report exact commit, CI, negative/positive tests, native evidence, skips and open gates; never silently upgrade a claim to PASS.

Detailed contracts: [GOVERNANCE](../GOVERNANCE.md) · [SECURITY](../SECURITY.md) · [Agent rules](../AGENTS.md) · [Release matrix](../TEST_AND_RELEASE_MATRIX.md) · [Architecture](ARCHITECTURE.md).
