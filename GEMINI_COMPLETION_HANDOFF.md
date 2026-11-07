# Gemini 3.8 Flash High — Wallet Manager v7 completion handoff

**Project:** Sentinel Node Wallet - BTCB2  
**Scope:** minimal Wallet-tab enhancement + P0 security repairs; no new app/runtime or wallet migration.  
**Status:** DOCUMENTATION + IMPLEMENTATION WORK ORDER, not evidence that Wallet v7 is deployed.  
**Canonical contract:** [docs/WALLET_MANAGER_V7.md](docs/WALLET_MANAGER_V7.md).  
**GitHub PR:** branch `docs/wallet-manager-v7-20261106` should be reviewed/merged before code changes are declared complete.

## Source audit completed

Private Admin Node Console `src/status_server.py` and `src/wallet_registry.py` (read-only) show:
- Coinbase maturity periods: original 100 blocks, 6,480 blocks for coinbase minted at heights 973440–979918, 25,920 for later qualifying coinbases. Interpret 2027-09-01 MTP expiry from verified fork consensus, preserving older output's original maturity.
- Live fee presets: slow/cheapest=24 blocks, normal=6, fast=2, using own-node `estimatesmartfee` plus mempool/relay floor. Fee rates BTCB2/kB -> sat/vB factor `100000`; support custom value with floor and fee caps. Fees and inclusion times are estimates.
- Locally registered per-wallet named whitelist contacts; sending forbidden for unapproved destinations.
- Transaction history, details, RBF/reorg/mempool statuses, maturity countdown and optional queue/bump features.

The standalone public `WalletManager.swift` is much smaller: only basic balances, receive, recent TX, and `sendtoaddress`; lacks full fee preview and allowlist. P0 code observations: default wallet can be created with empty passphrase; `Double` amount and `tb1`/`bcrt1` accepted; UI checks sync/height only; per-send Keychain presence not established; current spend path doesn't prove `SIGHASH_UNIFIED`. **Do not auto-enable wallet spending** until fixed, audited and safely tested.

## Single-session execution sequence

1. **Inspect exact source/release**: record live git SHA and branch, app/node process owners, app data directories, current wallet encryption, current sync and fork checkpoint, existing Keychain service, and user's wallet backup. Keep the existing database and IBD state. No source repo merge with Admin Node Console.
2. **P0 stop-the-line**: quarantine unsafe send call (disable wallet transaction signing, not receive/history) while implementing cryptographic fail-closed MainNet verification, unified replay-safe signing, Keychain user presence, encrypted-only wallet creation and actual core allowlist enforcement. If the fork Knots RPC cannot prove/force unified signature in ordinary wallet RPC, disable send; don't guess. Prefer proven unsigned PSBT + supervised signer over unsafe shortcuts. Use a transaction state machine `INPUT -> QUOTE -> REVIEW -> AUTHORIZED -> SIGN -> BROADCAST -> MONITOR`, with one-time immutable approval and exact recipient/amount/fee binding; default to no unattended spending.
3. **Maturity and balance**: add compact `MaturityCalculator` model to `WalletManager`, enforce coinbase creation-height rule 100/6480/25920 and verified MTP expiry; show spendable/pending/immature and per-reward blocks remaining/time estimate; ignore maturity logic for ordinary transactions. Use accurate integer sats and actual node consensus state.
4. **Fee chooser**: Cheapest/Normal/Fast + Custom and target inclusion estimate. Query local BTCB2 node smartfee targets 24/6/2 and mempool floor, show sources/staleness. Fund preview PSBT without signing; compute actual virtual size/fee/change and total debit; enforce sat precision, floor and cap. Never use standard BTC mempool.space quote.
5. **Contacts + history**: Wallet-scoped named allowlist, default ON, user presence for mutations; address validation with local node, full string confirmation. Paginated `listtransactions` and `gettransaction` detail, status of replacements/confirmations/reorgs/coinbase maturity. Show TXID and explicit-click `https://mempool.guide/tx/{txid}` (validated 64-hex TXID); don't query explorer in background.
6. **One native Wallet UI**: small balance card, receive/send composer and trusted-recipient picker, concise transaction rows with detail sheet, maturity disclosure, auth confirmation. Additional functions in collapsible detail sheets, **no additional main navigation tab, web service, database daemon, miner or gateway**.
7. **Testing**: Python deterministic mock RPC/unit security fixtures; Swift XCTest UI/Core state machine; real Mac Keychain and Touch ID denial/cancel; read-only genuine BTCB2 MainNet fork/maturity/feerate sanity. Test all four maturity era boundaries and MTP expiry; whitelist bypass/tamper; fee quote expiry/PSBT mismatch; double-send; malformed txid/URL; balance reorg; existing wallet migration; backup/restore on pruned data. Never test-sign/broadcast with real user BTCB2. Avoid RegTest/TestNet shipped or running as part of user distribution.
8. **Governance + delivery**: merge reviewed docs into main, update README feature-status truth, CI matrix, architecture and security disclosures; run secret/license scan; rebuild development-only DMG if safe and verify on Mac. Publish NO real-funds or public-ready claim unless independent signer, backup and Apple signing/notary/updater gates pass.
9. **Final report to Shared Cognitive Memory**: exact source commit(s), PR merge, macOS/Knots version, current IBD, tests and redacted outputs, maturity cases, live local fee sample where permitted, per-send-auth proof, Core signing verification, sensitive storage scan, DMG hash, GitHub governance links and all PASS/FAIL/NOT RUN.

## Latest addition: rolling historical coverage (v11)

Before claiming the low-storage node finished, integrate and test [Rolling Historical Ledger Coverage](docs/ROLLING_HISTORY_COVERAGE_V11.md), already drafted in PR #4. Clicking Node → Storage Footprint opens the existing Advanced picker; display observed retained-history age and selected-prune projection (years/months/weeks/days/hours), using only local `getblockchaininfo` and first-retained/tip headers, with no false coverage guarantee, no archival default and no per-keystroke RPC. Run Swift and actual Mac tests; preserve users' existing 550/custom retention settings.

## FINAL OWNER MODIFICATION — Wallet Auth v13, then production security sweep

**Read current merged `main`, open PR #5 and the latest Shared Cognitive Memory V12 correction first.** PR #4 has merged into main; PR #5 remains open. Owner explicitly REPLACED Ultra Battery 12 peers with **4** and disabled inbound listening, with low-priority CPU/disk behavior while battery or actively charging. Reconcile the target Mac before claiming V12 complete.

Implement [v13 Local Username + Password + TOTP and Apple Passwords specification](docs/FINAL_WALLET_AUTH_V13.md) in a *separate* minimal Swift PR after validated v12. macOS Apple Passwords save/autofill requires owner-approved associated domain, static AASA, Apple-signed bundle entitlements and user consent; preserve fallback local login without pretending generic Keychain equals Passwords. Protect Wallet tab and **core wallet RPC methods** with fresh auth and independent owner-presence for sensitive operations; Node/Network continue working locked. Recovery codes and separate wallet encryption/backup must survive login reset. Never upload login or TOTP secrets to a website.

When v13 passes native Mac tests, FREEZE features and execute [full production security audit and removal plan](docs/FINAL_PRODUCTION_SECURITY_AUDIT_V13.md) over ALL source/CI/scripts/Knots/app binaries/dependencies/services/surfaces. Inspect and resolve concrete known issues: Keychain -34018 weaker fallback, swallowed walletpassphrase/walletlock errors, misleading Knots verification helper, ad-hoc build signing, dormant MainNet-unneeded RegTest RPC helpers, duplicate UI settings controls and any actual unneeded or hostile code supported by evidence. Do not delete wallet files, Keychain secrets or chainstate, or claim malware found without independent proof. Include complete PASS/FAIL/NOT RUN, signed/provenance receipts and independent review; do not publish or enable real-funds send while P0s remain.

## Rules that do not change## Rules that do not change

MainNet only; minimal native app; use new-install default 2048 MiB pruned recent-block retention (550 MiB during IBD), preserve older user selections, 50 GiB design objective, optional external SSD archival full-redownload; adaptive synchronization ETA; logo from owner-supplied JPG; strict pool and enterprise infrastructure isolation; wallet data stays at existing app-owned path until approved migration; noncustodial keys never leave device.

**Roadmap only:** one-click DATUM gateway provisioning **not today**. It requires its own permission, resource/battery, network/Stratum and security design before any future implementation.
