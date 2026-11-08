# Test and release matrix — Sentinel Node Wallet - BTCB2


## Current v13.1 evidence snapshot — 2026-11-08 (America/New_York)

**Authoritative for current status; rows further below are historical target matrices from earlier v7/v12/v13 planning and may say NOT RUN for work since added.** Use the [current handoff](docs/V13_1_MAIN_AGENT_HANDOFF_20261107.md) for execution order. Until all P0 gates pass: **DEVELOPMENT ONLY; no real-funds send or public production release**.

**Code evidence:** `34dfbb09fbcfe4b9f15cf75ffac80640b8f9a4d4` on open PR #10, unmerged to main. [GitHub Actions macOS run 42447281610](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42447281610) ran **92 XCTest cases: 91 passed, 0 failed, 1 skipped interactive Keychain lifecycle**. Counts refer to that code SHA, not to later documentation-only commits. A CI PASS never means macOS hardware or a real Knots restore PASS.

| v13.1 acceptance item | Evidence / boundary | Current proof status |
| --- | --- | --- |
| Local operator auth, TOTP, high-risk single-use approvals | Branch source + security unit tests; old unsafe send path locked | **PASS (source/CI)**; real device consent incomplete |
| No-overwrite encrypted-wallet backup export architecture | Private staging; `openat`/directory FD; `fstat` + SHA-256 through open descriptor; `renameatx_np(RENAME_EXCL)`; inode-guarded cleanup | **PASS (source/CI)** on mocked successful and failure paths; further race/crash tests required |
| Failed RPC and empty staged backup behavior | Added two regression tests in `WalletAuthCoordinatorTests`, both passed in CI | **PASS (source/CI)**; disk-full/copy/fsync/rename-failure injection still NOT RUN |
| Operator-visible backup durability warning & descriptor cleanup | `WalletView` displays distinct `⚠️ Durability Unconfirmed` alert when `isDurabilityConfirmed == false`; security-scoped access handled; `dstFd`/`srcFd` closures guaranteed via `defer`; stale staging purge on startup tested (`testPurgeStaleStagingDirectoriesRemovesOldSessions`) | **PASS (source/CI)** |
| Actual Bitcoin Knots encrypted descriptor wallet backup + restore | Reproducible empirical regtest qualification on macOS host with bitcoind (SHA256: `836edd...`), 24,576-byte encrypted descriptor backup (mode 0600, SQLite format 3), restore to new wallet, descriptors true, locked status (`unlocked_until: 0`), and `ismine: true` address ownership verified | **PASS (native Mac reproducible qualification)**; signed-app UI roundtrip remains P0 gate |
| Mac Keychain / Touch ID accept, deny, cancel, -34018 & migration | CI interactive `testKeychainPassphraseLifecycle` deliberately skipped; headless CLI `swift test` fails with `-34018` (`errSecMissingEntitlement`) as expected without signed app bundle | **NOT RUN/UNVERIFIED (real device)** — P0 |
| Apple Passwords credential save/autofill/OTP | UI picker and input hints in source; HTTPS `webcredentials`, AASA, Team ID, entitlements and consent not complete | **BLOCKED (end to end)** — P0 |
| Real peer-cap/inbound/Ultra 4 + stable-AC restore | Config/source regression, live node verified running in Ultra profile (`-par=1 -dbcache=128 -maxconnections=4 -listen=0`), 4 outbound peers, 0 inbound | **PASS (live host Ultra runtime)**; battery-to-AC dynamic transition P0 |
| Real wallet send via `SIGHASH_UNIFIED` | Source intentionally throws `signingPathUnverified` | **SAFE DISABLED**; actual replay-safe signing NOT VERIFIED — P0 |
| App + fork Knots executable provenance, Apple Developer ID/notarization, signed updater, independent audit | No complete signed release artifacts / full-surface reviewer proof | **BLOCKED** — P0 |
| Data/IBD preservation on installed user Mac | Live bitcoind (PID 41696) syncing continuously past block 699,773 (45.01% verification progress); wallet `Kevin` locked and untouched | **PASS (live host node verified)** |

**Specific remaining defect to review:** unsupported directory `fsync` returns `BackupExportResult.isDurabilityConfirmed=false`; `AppState` logs it, but the Wallet UI may still display an unqualified "backup successfully saved". Ensure the warning is visible on the operator surface. Verify all file descriptors close on throwing read/hash branches, crash-safe temporary cleanup, and conservative external-volume semantics.

**Test environment rule:** consumer app remains MainNet-only. An isolated, no-funds temporary regtest node is permissible only for development verification, never as a shipped alternate chain profile or as a substitute for MainNet consensus/signing validation.

**Historical planning note (v7-era):** a published development repository exists. The previous v6 receipt of 35 passing tests does **not** cover the new Wallet Manager v7 requirements, genuine security-device consent, nor release notarization. This file specifies **required** results; unmeasured items are NOT RUN.

| Gate / scenario | Evidence required | Current v7 status |
| --- | --- | --- |
| Wallet constructor never creates unencrypted by default | Mock missing passphrase + failure, real empty-wallet creation check | NOT RUN — P0 |
| BTCB2 MainNet and replay-safe signing | Verified fork block 961,640, fresh anchor/tip and decoded actual unified signatures; wrong chain/`tb1`/`bcrt1` rejected | NOT RUN — P0 |
| Per-send Mac user presence | Touch ID / device owner auth, deny/cancel/replay tests with Security.framework on real host | NOT RUN — P0 |
| Address allowlist | New/edited/removed/disabled entries require auth; unknown address and clipboard swap rejected by core logic | NOT RUN — P0 |
| Immutable fee-aware send preview | Sat integer accounting; funded PSBT actual vsize/fee/change; quote change, expired quote and double-submit rejected | NOT RUN — P0 |
| Fees and timing | Cheapest=24, Normal=6, Fast=2 blocks; live own-node estimate/floor; custom sat/vB; no invented ETA; fee target ordering | NOT RUN |
| Coinbase maturity | Original height 973439/973440/979918/979919, MTP expiry, pre-expiry long-lock, exact boundary/reorg | NOT RUN |
| Mature/pending/immature buckets | Coinbases only subject to maturity; verify trusted balance and 0-conf handling with node | NOT RUN |
| TX history | Pagination, UTXO detail, confirmations, fee, vsize, replace/conflict/abandon/reorg, multi-output TXID grouping | NOT RUN |
| Explorer link | Strict 64 lowercase/uppercase hex, `mempool.guide/tx/`, explicit click; no silent network request | NOT RUN |
| Wallet backup/restore | Empty wallet + contacts backup, Keychain auth, prune birth-height warning, no overwrite/data loss | NOT RUN — P0 |
| App isolation + minimalism | One node, three views, no DATUM/miner/cloud integration, no production alternate chains | TO REVERIFY |
| Resource/storage | New-install prune=2048 after IBD and pruneduringinit=550 while IBD; preserve older custom/550/archive config. 35/40 GiB disk guards, measured peak disk and CPU/RSS/energy | TO REVERIFY |
| Development docs + secrets | Swift+Python deterministic tests, clean CI scan, source/vendor/license review | NOT RUN v7 |
| Public release | Apple Developer ID for app+bitcoind; notarization/staple/Gatekeeper; signed updates; independent wallet audit | BLOCKED |

## v13.1 Apple Passwords onboarding validation

| Scenario | Status |
| --- | --- |
| App-generated 192-bit login password; strength, uniqueness, macOS input hints | Swift test authored; native compile/test NOT RUN |
| apple-otpauth system UI launched and 2FA code verified with Apple Passwords | NOT RUN on actual signed Mac |
| Save username/password into selected Apple Passwords vault | BLOCKED — owner-approved associated domain, AASA/Apple signing and working credential-save API required |
| Unsupported OS, ad-hoc build, denied user consent, canceled credentials | Must visibly fail safe; NOT RUN |
| Existing operator, wallet secrets, Keychain and MainNet IBD unchanged | Mac validation NOT RUN |

## Final v13 authentication + complete production freeze gates (NOT RUN)

| Surface / gate | Actual proof | Status |
| --- | --- | --- |
| Local username/password/TOTP enrollment and login | No default, hashed verifier, accepted/rejected/replayed/expired OTP and rate limit; core denies direct unauthenticated RPC | NOT RUN — P0 |
| Apple Passwords on real signed macOS | Owner-approved AASA/domain & Team ID; system-mediated save, relaunch autofill, verification-code entry; entitlement fail-safe | NOT RUN — P0 |
| Step-up and recovery | Touch ID/device-owner approval and deny/cancel for backup/send/deletion/recipient edits; short session, lock on sleep; recovery codes don't replace wallet backup | NOT RUN — P0 |
| Wallet encryption and Keychain | -34018/-50 without weakening item; legacy migration preserves secrets; no plaintext fallback | NOT RUN — P0 |
| Binary/updater provenance | Actual signed Knots checksums+fingerprints (not shell label), pinned BTCB2 fork; Developer ID/notary and signed release updating | NOT RUN — P0 |
| Prior v12 Ultra correction | Battery/charging effective 4 peers, listen=0, par=1 and low process CPU/disk I/O priority, user prior mode restored | NOT RUN — P0 |
| Wallets/backup/data safety | All-wallet read/lock/archive/delete/restore on empty test-only data, never funded user wallet | NOT RUN — P0 |
| Malicious/nonessential code audit | Entire source/dependency/network/launch agent/compiled bundle inventory, SBOM, static/dynamic trace, minimal audited removals, no unreviewed payload | NOT RUN — P0 |
| All Node/Wallet/Network/settings surfaces | Cross-surface SwiftUI UI and native macOS tests, mainnet fork, pruned disk and energy, peer relay, historic coverage, fiat freshness and explorer privacy | NOT RUN |
| Independent security signoff | Signed artifacts, license/notice, clean-room restore, Gatekeeper fresh Mac, no remaining P0, reviewer signoff | BLOCKED |

See [v13 login contract](docs/FINAL_WALLET_AUTH_V13.md) and [full production security audit](docs/FINAL_PRODUCTION_SECURITY_AUDIT_V13.md). A mocked test pass or prior Gemini handoff is not proof of installed/macOS Apple Passwords behavior.

**No real-funds test sends.** Python mock RPC and Swift XCTest should cover failures and formatting; actual Mac user-presence and fork signature need separate authenticated tests. No RegTest/TestNet/Signet network is shipped or presented in the consumer application; isolated temporary regtest is permitted for zero-funds developer-only backup/restore verification. Maintain an evidence receipt with full commit SHA, macOS build, test commands, redacted outputs, storage, historical compatibility, DMG hash, independent review and explicit PASS/FAIL/NOT RUN.

## v12 Ultra Power Policy, All-Wallet Inventory & Single Settings UI

| Scenario | Required proof | Current status |
| --- | --- | --- |
| IOKit power state classification | Battery, Charging, AC Not Charging, Unknown, Low Power Mode | **PASS** (Swift + Python tests) |
| Ephemeral Ultra resource bounds | `par=1`, `dbcache=128MiB`, `maxconnections=4` (authoritative override replacing draft 12), `listen=0`, `maxuploadtarget=128MiB`, `prune=2048`, low CPU/IO priority | **PASS** (Swift + Python tests) |
| Preferred profile preservation | User-selected Quiet/Balanced/Fast saved; resumes on stable AC | **PASS** (Swift + Python tests) |
| Multi-wallet discovery & per-wallet isolation | Knots `listwalletdir` + `listwallets`, `/wallet/<name>` RPC calls | **PASS** (Swift + Python tests) |
| Unloaded wallet stale/unavailable labeling | Shows timestamped last known or `Unavailable — Load to refresh` (never 0) | **PASS** (Swift + Python tests) |
| Reversible archive semantics | `unloadwallet` closes wallet; registry preserves DB/Keychain credentials | **PASS** (Swift + Python tests) |
| Fail-closed wallet deletion gating | Refuses if spendable > 0, pending > 0, immature > 0, or unverified | **PASS** (Swift + Python tests) |
| Mandatory pre-delete backup verification | Requires verified non-empty `.dat` backup before file operation | **PASS** (Swift + Python tests) |
| Reversible macOS Trash deletion | Uses `FileManager.trashItem`; `rm -rf` strictly forbidden | **PASS** (Swift + Python tests) |
| Single Settings UI button | Exactly 1 `showAdvancedSheet = true` call site in `NodeView.swift`; read-only Storage Footprint | **PASS** (Swift + Python tests) |

## v11 live rolling-history coverage

| Scenario | Required proof | Current status |
| --- | --- | --- |
| Actual retained-history age | Compare `pruneheight`, first-retained block header, best tip header timestamps and block count with UI | NOT RUN on real Knots |
| Selected-size projection | 550 MiB / 1 GiB / 2 GiB / 4 GiB / custom recomputes immediately from sampled block/undo byte density; no additional per-keystroke RPC | Swift tests authored, NOT RUN |
| Automatic time units | Years/months/weeks/days/hours and combined two-unit bounds; invalid values fail safely | Swift tests authored, NOT RUN |
| During IBD or missing data | Actual as-of current validated tip where possible, projected coverage displays Calibrating instead of false live-tip forecast | Swift tests authored, NOT RUN |
| Non-invasive safety | No node restart until Apply, no wallet or chain writes, no extra service or unintended archival mode | NOT RUN on Mac |

## Candidate bug-fix acceptance (not yet Mac-validated)

| Change | Test evidence required | Current status |
| --- | --- | --- |
| Quiet / Balanced / Fast selector | One serialized write/restart per Apply, `bitcoin.conf` numerical settings and actual Knots process startup, no hidden errors | NOT RUN on Mac |
| Settings survive relaunch | Reopen app and verify last-selected profile, threads/cache/peers and unchanged pruning | NOT RUN on Mac |
| Battery behavior | Fast remains selected on battery, no automatic switch to Balanced | NOT RUN on Mac |
| Adopted-daemon case | Unverified process cannot be stopped; clear error; implement PID/datadir-verified safe adoption before claiming seamless adoption | PARTIAL — deliberate fail-closed |
| Strong passphrase generation | `SecRandomCopyBytes` (32 bytes), 43-character base64url, distinct samples, no seed/recovery mislabeling | Swift XCTest added; NOT RUN |
| Protected Keychain storage | New wallet name/account item requiring device-owner presence; no silent overwrite, save errors block wallet creation | Mac manual test NOT RUN |
| Saved-passphrase fill | User explicitly requests fill and authenticates; decline/cancel must not release secret, both create and later send prompts | Mac manual test NOT RUN |
| Wallet backup | Export/restore encrypted descriptor wallet, proof that passphrase alone does not recover descriptors, Keychain unavailable scenario | NOT RUN |
| Apple Passwords compatibility | Do not claim generic Keychain item is automatically visible in Apple's Passwords app; verify UI wording | Documentation only |
