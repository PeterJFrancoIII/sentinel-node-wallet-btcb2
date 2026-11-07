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
| Resource/storage | 550MiB prune from IBD, 35/40GiB disk warnings/stops, actual peak disk and CPU/RSS/energy | TO REVERIFY |
| Development docs + secrets | Swift+Python deterministic tests, clean CI scan, source/vendor/license review | NOT RUN v7 |
| Public release | Apple Developer ID for app+bitcoind; notarization/staple/Gatekeeper; signed updates; independent wallet audit | BLOCKED |

**No real-funds test sends.** Python mock RPC and Swift XCTest should cover failures and formatting; actual Mac user-presence and fork signature need separate authenticated tests. No RegTest/TestNet/Signet distributed or used for execution. Maintain an evidence receipt with full commit SHA, macOS build, test commands, redacted outputs, storage, historical compatibility, DMG hash, independent review and explicit PASS/FAIL/NOT RUN.
