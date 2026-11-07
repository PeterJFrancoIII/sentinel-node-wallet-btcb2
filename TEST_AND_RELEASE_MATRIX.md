# Test and release matrix — Sentinel Node Wallet - BTCB2

**Current status:** a published development repository exists. The previous v6 receipt of 35 passing tests does **not** cover the new Wallet Manager v7 requirements, genuine security-device consent, nor release notarization. This file specifies **required** results; unmeasured items are NOT RUN.

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

**No real-funds test sends.** Python mock RPC and Swift XCTest should cover failures and formatting; actual Mac user-presence and fork signature need separate authenticated tests. No RegTest/TestNet/Signet distributed or used for execution. Maintain an evidence receipt with full commit SHA, macOS build, test commands, redacted outputs, storage, historical compatibility, DMG hash, independent review and explicit PASS/FAIL/NOT RUN.

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
