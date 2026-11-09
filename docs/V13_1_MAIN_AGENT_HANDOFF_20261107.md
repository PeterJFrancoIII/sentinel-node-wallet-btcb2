# v13.1 Main-Agent Transition Handoff — Sentinel Node Wallet BTCB2

**Snapshot:** 2026-11-08 19:45 America/New_York (latest code and CI timestamps 2026-11-08 UTC).  
**Decision:** DEVELOPMENT ACCEPTED; PRODUCTION / REAL-FUNDS USE BLOCKED.  
**Active Work Order:** `WO-NODEPOCKET-V13.1-FULL-REMEDIATION-20261108` (P0-01 to P0-07, P1-01 to P1-05 remediated, plus 6 independent audit findings resolved).  
**New main agent:** role-neutral; this file replaces the outdated V12 execution order in [GEMINI_COMPLETION_HANDOFF.md](../GEMINI_COMPLETION_HANDOFF.md).  
**Owner's request:** preserve everything already built, make progress against the remaining gates, and hand over one inspectable truth set.

## 1. Where the working tree is

- Repository: https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2
- Code review branch: `fix/v13-1-security-remediation-20261107`; active [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), **OPEN and NOT merged into main** as of this snapshot.
- Prior code evidence SHA `663b9e0031dc1870a07bc3de01157ad9acd62fcf` verified by CI [run 42459030543](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42459030543) (97 tests, 96 passed, 1 skipped).
- Independent Audit Remediation: Addressed 6 independent review findings from ChatGPT audit of Receipt #065:
  1. **P0 Wallet deletion backup mismatch & restore proof**: `WalletManager.exportBackup` explicitly accepts and binds `targetWalletName`. `WalletInventory.deleteWalletFromMac` accepts `verifiedReceipt: VerifiedBackupReceipt?`, verifies target wallet identity (`receipt.walletName == name`) and backup path, executes an isolated test restore via `rpcClient.restoreWallet(name: "del_verify_<uuid>", backupFile:)`, verifies restoration, and immediately unloads the test wallet before permitting deletion.
  2. **P0 Confirmed `.stopped` Ultra restart**: `NodeManager.applyUltraMode` tracks `previousPid`, calls `await stop()`, polls up to 20 cycles for `state == .stopped`, strictly guards on state and verifies `kill(oldPid, 0) != 0` before launching the new daemon process.
  3. **P0 Process identity, provenance, and pre-fork consensus adoption verification**: `NodeManager.verifyAdoptedDaemon` validates datadir and `.cookie` POSIX ownership (`stat.st_uid == getuid()`), verifies live PID (`kill(pid, 0) == 0`), verifies executable provenance via `proc_pidpath` ending in `bitcoind`, and inspects positive pre-fork consensus anchors (Genesis block 0 `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f`, block 500,000, and block 800,000) and Knots subversion.
  4. **P0 Backup staging cross-process locking**: `WalletManager.exportBackup` acquires an advisory exclusive POSIX lock `flock(LOCK_EX)` on `.session.lock` and writes PID to `.session.pid`. `purgeStaleStagingDirectories` checks non-blocking `flock(LOCK_EX | LOCK_NB)` and verifies PID liveness (`kill(pid, 0) == 0`), preventing any cross-process corruption or race condition during active exports.
  5. **P1 Coinbase rewards refresh auth capability**: `AppState.refreshCoinbaseRewards()` passes authenticated `WalletAuthCapability` to `walletManager.fetchCoinbaseRewards()`, and `AppState.selectWallet()` passes capability to `refreshWalletInfo()`.
  6. **P1 Same-height chain reorg deduplication**: `HashrateTracker` deduplicates blocks by both hash and height (`last.hash == hash && last.height == height`). When a block arrives with `height <= last.height` and a differing hash, it prunes the stale branch (`samples.removeAll(where: { $0.height >= height })`) and appends the reorg block.
- Local test execution: **102 executed; 101 passed; zero failed; one intentionally skipped interactive Keychain test**.
- Agent receipts: `MSG:SENTINEL-V13-1-FULL-REMEDIATION-RECEIPT-20261108-066` supersedes `MSG:SENTINEL-V13-1-FULL-REMEDIATION-RECEIPT-20261108-065` in `InterAgent_Dialogue_Channel`.

## 2. Immutable project boundaries and STOP conditions

This is a public-facing, minimal, standalone native SwiftUI **BTCB2 BLAKE2b/BIP-110 MainNet-only** Knots node and self-custodial wallet. Three views: **Node, Wallet, Network**, with one Advanced sheet. No shared runtime, credentials, process control, dependency or source modification of any external mining system, hardware firmware, pool, private Admin Console or unrelated project. Old admin code may be read for behavior reference only. No new miner, cloud wallet, gateway, remote RPC or alternative-network consumer UI.

**Preserve user wallets, passphrases/Keychain items, app bundle identity, dedicated datadir, IBD/chainstate, pruning preferences, address book and previous backup files.** No destructive resets, file deletion, funded-wallet tests, production restore-overwrite, unverified adopted-daemon stop, or live-funds transfers. Use isolated temporary, empty, zero-funds test wallets/datadirs for all destructive/failure tests. An isolated developer-run regtest daemon may be used for testing only; it is never packaged or exposed as a consumer mode.

**Spending stays disabled at the wallet core:** `WalletManager` send entrypoints throw `WalletSecurityError.signingPathUnverified` until BTCB2 replay-safe `SIGHASH_UNIFIED` and all P0 gates pass. Never bypass this to demonstrate a transaction.

## 3. Achieved: code and test evidence

**Node and UI:** Three-view SwiftUI app; one Settings control; profile presets Quiet 16, Balanced 24, Fast 32 peer ceilings; Ultra battery/charging override **maxconnections=4, listen=0**, par=1, dbcache=128 MiB, saved preference restored on stable AC in source. Existing config/prune retained. `Profile Active` card placed at top. Inbound toggle and configured-versus-effective peer cap handling are present in PR #10. A ceiling is not a promise of that many actual connections. Live transition and cap-at-boundary QA remains distinct.

**Wallet authorization:** Local username + password + RFC6238 TOTP, short-lived session, explicit device-owner step-up for high-risk actions, single-use action/target-bound approvals; Keychain security and legacy migration hardening; encrypted-wallet creation requirements; fail-closed unauthorized core RPC paths. Apple Passwords picker and autofill hints exist, **but credential save/retrieval in Apple's Passwords app is not proven** without proper webcredentials/AASA, owner Team ID, signed bundle and real-user consent.

**Wallet management:** Multi-wallet listing, per-wallet RPC isolation and integer satoshi accounting; archive unload; reversible macOS Trash deletion with strict checks; balance, receiving, history and maturity models in development. Do not imply all wallet v7 edge cases or funded send workflow are release-qualified.

**Backup export & safe deletion (P0-02, P0-03):** Preemptive deletion of an existing destination removed. Captures and checks selected wallet and auth session before/after asynchronous approval; rejects replay and mismatched targets. Knots `backupwallet` writes into private per-session staging, then app creates an exclusive hidden destination-directory temp file; verifies bytes/mode/regular-file via `fstat` on the same open descriptor, computes SHA-256 through that descriptor, uses `openat` + `renameatx_np(RENAME_EXCL)` against the same held directory FD, and guards failure cleanup with `fstatat`/inode-device comparison + `unlinkat`. File `F_FULLFSYNC` with `fsync` fallback; directory `fsync` tracked in `BackupExportResult`. Active staging session registry prevents `purgeStaleStagingDirectories` from deleting concurrent exports. Wallet deletion in `WalletInventory` strictly checks verified backup existence, regular file mode, SQLite/BDB magic header, verified zero balance, and unload before trash. Delete sheet in `WalletView` routes backups through `exportBackup`.

**Reproducible native Mac / real Knots qualification:** Verified via standalone reproducible script `tests/integration/test_knots_regtest_roundtrip.sh` running against pinned Bitcoin Knots `v29.4.3.knots20260508` (Mach-O arm64 bitcoind SHA-256 `9047086...`, embedded `836edd...`). The test executes an isolated regtest daemon on custom port 28443 in `/tmp`, creates an encrypted descriptor wallet (`createwallet` with `descriptors=true`), verifies address generation and ownership (`ismine=true`), exports a 24,576-byte backup, and restores to a distinct wallet with full descriptor retention, locked status (`unlocked_until=0`), and key ownership confirmed. 100% reproducible qualification receipt logged.

**Verified live host node:** Native macOS background daemon (PID 45252) running in Ultra profile (`-par=1 -dbcache=128 -maxconnections=4 -listen=0`), continuing IBD past block 853,916+ (981,158 headers) with 70.51% validation progress. Operator wallet `Kevin` locked and untouched in `/Users/computer/Library/Application Support/NodePocketBTCB2`.

## 4. Current safety / UX concerns requiring targeted review

1. **Operator-visible backup truth (P0):** `BackupExportResult.isDurabilityConfirmed=false` can be returned when destination filesystem cannot sync directory metadata; `AppState` currently logs this, but `WalletView` may still display an unqualified "backup successfully saved" alert. Surface "published, durability unconfirmed" directly to the operator and require readback or another verified backup before considering it safe. For a post-publication I/O failure, clarify that a file may exist even though durability could not be confirmed.
2. **File-identity / error cleanup review (P1):** confirm every exceptional branch closes its open source/destination FD; e.g. thrown SHA read before `close(dstFd)`. The `fstatat`-then-`unlinkat` inode guard narrows risk but is not an indivisible compare-and-unlink against an active malicious directory writer. Use a restricted owned directory / exact OS ownership model and test parent swaps, failure injection, and stale staging after unexpected termination.
3. **Real recovery proof (P0):** reproduce the isolated encrypted-wallet backup→restore with the exact build and capture *redacted* logs/commands, encrypted status, descriptor ownership, new destination identity, pruned recovery warnings, Keychain failure and permission-denied cases. Test the actual signed app/UI + fresh device-owner prompt, not only CLI or mocked URLProtocol. No production wallet may be used as a test fixture.
4. **Persistence and release audit (P0):** verify backup directory ancestor permissions, scoped file access, and mounted external-volume semantics (APFS versus exFAT/network) with truthful durability states. Failures must never overwrite a good prior backup.

## 5. Remaining P0 production gates and priority order

**Priority A — finish backup/auth proof.** Real Mac `Keychain` test (CI interactive test currently SKIPPED), Touch ID/device password accept/deny/cancel/replay/login-lock mid-prompt, non-destructive TOTP migration, safe recovery; close the backup UI warning and conduct tested clean-room encrypted-wallet restore with evidence.

**Priority B — Apple Passwords end to end.** Obtain owner approval for a dedicated HTTPS `webcredentials` host, static AASA association with the actual Apple Team ID and bundle ID, correct Associated Domains entitlement and Developer ID signed app. Verify user-initiated credential enrollment, automatic/picker fill after relaunch, TOTP independently, cancel and failure paths. Never claim the generic Keychain equals Apple Passwords and never use unrelated business/pool domains without approval.

**Priority C — live node/power validation.** Real Mac battery/charging to Ultra=4 / `listen=0` and stable-AC restoration, configured peer ceiling versus observed peers, safe existing `listen`/maxconnections policy, no sync reset or mutation, single app-owned daemon verified by PID/datadir. Validate MainNet fork checkpoints and binary provenance with official signatures/hashes rather than a filename.

**Priority D — wallet signing security.** Keep spend disabled while independently auditing BTCB2 BLAKE2b `SIGHASH_UNIFIED` correctness, chain identity/fresh tip, fixed-point funded PSBT preview, fees/maturity, allowlist, immutable outputs/change, one-time step-up, broadcast and wallet-lock failure handling. No real user funds used for qualification; if uncertain, retain disabled state.

**Priority E — distribution and independent review.** Source/dependency/SBOM/secret/network review across Node/Wallet/Network/settings and update pipeline; valid fork binary provenance; Apple Developer ID app + embedded executable signatures, notarized/stapled DMG and Gatekeeper validation on fresh Mac; signed updater chain, licensing and third-party notices; reviewer not the implementing agent. No P0 may be waved through by a passing test suite.

No new feature scope until these release gates close. DATUM capability remains roadmap only.

## 6. Handoff execution protocol for the incoming main agent

1. **Inventory read-only first:** fetch PR #10, branch head, `GOVERNANCE.md`, `AGENTS.md`, `SECURITY.md`, `TEST_AND_RELEASE_MATRIX.md`, this handoff and full v13 audit. Identify exact app and Knots executables, process ownership, attached datadir, prune config, loaded-wallet IDs and backup locations without printing secrets. Do not assume prior agent's live runtime view is still valid.
2. **Branch discipline:** work on PR #10 or a reviewed child branch; treat current code SHA above as baseline, then record a fresh new SHA after modifications. No unreviewed merge to `main`, no production DMG claim. No cross-project writes.
3. **Close identified residuals with minimal code:** operator-visible durability status; FD cleanup and identity; injected faults (partial copy, digest mismatch, permission/disk full, rename collision, power loss, stale staging), plus correct filesystem statuses. Preserve good backup files and signed app data.
4. **Execute isolated actual Knots wallet round trip:** separate temporary regtest datadir/test-only wallet; fresh encrypted descriptor wallet, address ownership, locked/unlocked state, backup, restore to a new unique wallet, repeatability, redacted evidence. Then test signed-app native flow when prerequisites are available. Never touch existing user wallets or node state.
5. **Perform missing Mac acceptance and security gates** in priorities A–E, update matrix row by row: `PASS (source/CI)`, `PASS (native on-device)`, `AGENT-REPORTED/UNVERIFIED`, `NOT RUN`, `BLOCKED` with direct evidence.
6. **Post one new concise inter-agent receipt:** agent identity, exact SHA + PR + CI URL/counts, native Knots/macOS version, explicit pass/fail/not-run and source paths, unchanged production data attestation, unresolved P0 and next owner action. No credentials, wallet addresses, Keychain secrets, TOTP enrollment codes, TXIDs or personal metadata.

## 7. Release decision and handoff acceptance

**Accept:** a continuing development candidate with implemented security controls and repeatable native macOS CI.  
**Do not accept:** an audited public wallet, safe hot-wallet funds custody, verified real-funds signing, genuine Apple Passwords credentials, or a notarized distribution.  
**Handoff is complete only when** the incoming main agent acknowledges this document, confirms fresh repository/runtime identity, updates the evidence matrix honestly and starts priority A without altering production data.

Canonical contracts: [GOVERNANCE](../GOVERNANCE.md) · [AGENTS](../AGENTS.md) · [SECURITY](../SECURITY.md) · [Release matrix](../TEST_AND_RELEASE_MATRIX.md) · [Final security audit](FINAL_PRODUCTION_SECURITY_AUDIT_V13.md) · [Apple Passwords setup](APPLE_PASSWORDS_OPERATOR_SETUP_V13_1.md).
