# Wallet Manager v7 — BTCB2 MainNet (Canonical)

**Project:** Sentinel Node Wallet - BTCB2  
**Status:** implementation specification; NOT a declaration of wallet safety or public-release readiness  
**Scope:** one existing **Wallet** tab within the native SwiftUI app; no extra daemon, web server, external wallet API, mining/pool integration or shipped Python service.

## Purpose and reference

Match the **observable behavior** of the private Admin Node Console Wallet Manager for: mature/immature coinbase rewards, estimated time to spendability, three live fee choices plus custom fee, named whitelisted recipients, detailed transaction history, correct-chain TXID hyperlinks and controlled spending. The private Admin Console is **read-only reference**; do not copy its code, database, real addresses, RPC cookies, account data or private documents into this standalone/public repository.

**No DATUM Gateway in v7.** One-click DATUM setup is a future, separately governed milestone; no bundled gateway, Stratum controls, mining activation, pool credentials or inbound gateway port changes in this release.

## Minimal UI — one Wallet tab

1. **Balances:** Spendable (node-trusted), Pending/unconfirmed, Immature coinbase, Total tracked; clearly label unverified/stale wallet data and locked state. A coinbase reward is not spendable until consensus says so.
2. **Receive / Send:** QR/address; send form with named trusted recipient, amount in BTCB2, fee choices, actual preview and explicit second authorization. Sending is unavailable until BLAKE2b MainNet and wallet authorization gates pass.
3. **Trusted Recipients:** Add, rename, remove, validate and select destination addresses with full address confirmation.
4. **History:** Paginated records, filter/search, details drawer and external link when appropriate. No remote explorer/API calls without a click.

Wallet operations must not require running an entire historical block archive. Keep existing descriptor wallet intact while pruning and syncing; restoring an older wallet whose birth-height history has been pruned requires guided resync.

## 1 — Coinbase maturity and time to maturity

**BTCB2 Knots consensus schedule, verified by on-chain creation height and the node's `getdeploymentinfo`:**

| Coinbase creation conditions | Required block maturity | Nominal duration |
| --- | ---: | --- |
| Height below 973,440 | 100 blocks | ~16.7 hours |
| Height 973,440 through 979,918 | 6,480 blocks | ~45 days |
| Height at or above 979,919, before the RDTS expiry condition | 25,920 blocks | ~180 days |
| Coinbase created after previous-block median time past reaches 2027-09-01 00:00 UTC | 100 blocks (unless consensus is changed) | ~16.7 hours |

Rewards *created before* the expiry under the 25,920-block rule retain that maturity even after expiry. The 45-day era does **not** retroactively become 180 days. This schedule applies **only to coinbase outputs**; ordinary inbound transfers are not subject to coinbase maturity.

Implementation:

- Obtain `getbalances.mine.trusted` / `untrusted_pending` / `immature` for headline buckets; use `listtransactions` / `gettransaction` and supported UTXO detail to associate coinbase origin height, amount, confirmations, block hash and status. Never misclassify ordinary pending payments as immature mining rewards.
- Maturity height derives from **original coinbase height plus required consensus depth**, using Knots's authoritative spendability/immaturity checks to resolve confirmation boundary off-by-one questions. Derive blocks-to-maturity from live tip, not from elapsed wall time; re-evaluate after reorgs, node upgrades and changed chain deployments.
- Per reward show `Matures at block #...`, `... blocks remaining`, an approximate calendar/time countdown in adaptive w/d/h/m/s and confidence. Use observed recent network block intervals with robust smoothing and nominal 600s fallback labeled *low confidence*; ETA is not a guaranteed clock.
- If the node is still in IBD or the wallet is rescanning, mark the amounts provisional and do not declare a block mature solely because an ETA reached zero. If node-derived consensus rule or origin height is unknown, show **Unknown—waiting for verified chain data**, never guess 45/180 days from the current height alone.
- Test boundaries 973,439/973,440, 979,918/979,919, MTP expiry, reward minted just before expiry but matured after, exactly-at-maturity confirmation, reorg/rollback, IBD/stale node and wallet restore/pruned history.

## 2 — Live fee quotes and accurate preview

The send form offers **Cheapest / Normal / Fast / Custom** without a second window. Use only **BTCB2 MainNet's OWN node** for fee markets; never obtain fee numbers or confirmation estimates from ordinary BTC `mempool.space`.

| Preset | Initial smart-fee target | ETA basis |
| --- | ---: | --- |
| Cheapest | 24 blocks | estimated BTCB2 inclusion time from target × observed interval |
| Normal | 6 blocks | same |
| Fast | 2 blocks | same |
| Custom | User-entered positive finite sat/vB | no timing guarantee absent a credible fee estimate |

- Query supported `estimatesmartfee` targets, `getmempoolinfo`, `getnetworkinfo`; convert **BTCB2/kB × 100,000 = sat/vB**; require `Fast >= Normal >= Cheapest` (equal legitimate when quiet). Respect observed `mempoolminfee` and `minrelaytxfee`, but a floor quote is **not** evidence of confirmation within the chosen number of blocks.
- Display rate (sat/vB), **projected exact fee (BTCB2 and sats)**, recipient amount, change estimate, total debit, target blocks, approximate time and fee quote age/source. No fabricated 1 sat/vB, fixed 141-vB transaction or guaranteed confirmation time. Refresh conservatively while the send sheet is visible; expire quotes quickly on changing tip/mempool.
- Use a **nonbroadcast, non-signing RPC-funded preview** (e.g. supported `walletcreatefundedpsbt` or `fundrawtransaction` + decode) to obtain real selected inputs, virtual size and fees; never accidentally lock UTXOs or persist partial signing secrets during preview. Use signed integer satoshis, not floating-point arithmetic, for balances, fees and amount limits.
- Custom fee validates finite/positive, local relay floor, dust policy, balance/fee sufficiency, configurable maximum fee cap, selected inputs and policy. Insufficient or stale fee data -> clearly show **unavailable / time unknown** or explicit relay-floor-only source, rather than invent a confident quote. Neither preset nor manual entry may bypass signing and trusted-recipient checks.

## 3 — Whitelisted named recipients

- Small versioned **app-local, wallet-scoped** encrypted-at-rest or OS-protected contact metadata: stable wallet ID, exact destination address, name/label, created/updated time and verification state. No centralized API, additional database daemon or blockchain address crawler.
- **Allowlist ON for outgoing transfers by default**. Users explicitly add a trusted recipient, confirm the full address visually and complete macOS user-presence authentication; a nickname alone cannot change the destination. Enforce the allowlist in the **WalletManager signing/broadcast layer**, not merely UI filtering.
- Adding, deleting, changing an address or disabling the protection requires reauthorization and a warning. Label edits do not modify address bytes. Validate through `validateaddress` on the verified BTCB2 node (not only regex). Re-read destination after clipboard paste and when the actual PSBT inputs/outputs are reviewed to resist clipboard substitution.
- Never whitelist a pasted destination automatically during a send or silently approve a new recipient. If metadata is missing/corrupt, fail closed for spending while keeping receive and read-only history usable.
- Optional contacts import/export only after verified backup/privacy review; no cloud sync or data harvesting.

## 4 — History, detail view, tracking, explorer

Wallet-owned history uses `listtransactions` with pagination + `gettransaction` detail and `getmempoolentry` as available. Show directional category, BTCB2 amount, coinbase maturity state, recipient label/address, fee, effective sat/vB, vsize, first seen/time received, block height/hash/time, confirmation count, mempool status, status of conflict/abandon/reorg/replacement and RBF lineage. Do not present a finite recent-page cache as complete historical coverage. Unavailable pruned historic block data must be labeled; never invent it.

**TXID hyperlink:** A standard Bitcoin `mempool.space/tx/{txid}` URL targets the incompatible SHA256d chain. Default verified BTCB2 chain-compatible link is `https://mempool.guide/tx/{txid}` (64 hex characters, fixed HTTPS host). Open **only on explicit user click** to avoid silently exposing wallet activity, TXIDs and user IP to a third party. Do not call remote explorer or fee APIs in the background. If the user asks for a specific mempool.space instance, only permit it when that exact endpoint demonstrably follows BTCB2 BLAKE2b; otherwise do not generate misleading links.

Advanced transaction detail may expose **manual** BIP125 fee bump when the exact Knots BLAKE2b `SIGHASH_UNIFIED` signing path is proven. Never auto-bump or auto-broadcast at first maturity; require fresh fee preview and per-transaction authorization. RBF replacement/new TXIDs must be linked in the history without losing the original record.

## 5 — Security against unauthorized access (P0 release gates)

No hot wallet can guarantee private-key protection if the host OS or authenticated user's process is fully compromised. Offer meaningful defense-in-depth instead:

- Encrypted descriptor-wallet creation must **fail closed if no passphrase** is available; never create a silently unencrypted default (`ensureDefaultWalletLoaded` currently has an empty-passphrase fallback). Receive/history may remain usable while the encrypted wallet stays locked.
- Keychain wallet passphrases must use an audited macOS `SecAccessControl` user-presence policy (Touch ID/device owner authentication as supported), **per send and per recipient/security-policy change**. No auto-retrieval by a process that merely shares the login session; no plaintext seed/passphrase caches, disk mirrors, CLI argv, logs, analytics, support exports or Git commits. Keychain item access and service migration must preserve existing wallet data.
- Require **fresh explicit approval bound to exact wallet, chain, full destination address, amount, fee cap, coin selection/change and a short expiry**. Recompute/revalidate server-side immediately before signing, invalidate if preview differs; prevent UI-only authorization bypass, paste substitution and double-send on retry. Show full address without truncation during final confirmation.
- Sending/signing must check real verified BLAKE2b block at 961,640 and a trusted later anchor, a fresh, fully synchronized MainNet tip, wallet encryption/unlock, allowlist and replay-safe **opt-in `SIGHASH_UNIFIED`** signatures (not just a green UI badge). Existing `WalletManager.send` accepts `tb1`/`bcrt1` and invokes `sendtoaddress` without a demonstrated unified signature flag; block such paths until proven and tested.
- Require native user interaction and minimal wallet unlock (seconds), `walletlock` on success/failure/cancel, no persistent unattended signing, no shared RPC credentials or remote wallet RPC. Do not promise that FileVault/Keychain alone defeats malware with root privileges. Recommend FileVault, updates, no remote-control software for high-value wallets and independent hardware signing/watch-only for stronger protection as a *future optional* mode.
- No real-money send tests or opening broad inbound RPC. Fail closed on fork mismatch, unsupported RPC or signing policy, missing recipient/quote integrity and interrupted wallet rescan.

**Observed public-source P0 audit targets (at v6):** `Sources/NodePocketCore/Wallet/WalletManager.swift` (empty-passphrase default; `Double` amounts; `sendtoaddress`; alternate address prefixes; async relock), `Sources/NodePocketApp/Views/WalletView.swift` (IBD/height-only send gate, no approved preview), `Sources/NodePocketCore/Wallet/KeychainHelper.swift` (Keychain without per-send user-presence access control). These observations are inspection findings, NOT proof that new code is already fixed.

## Acceptance, tests and release

Python deterministic mock RPC, maturity epoch/MTP fixtures, fee tier bounds and quote-expiry, satoshi rounding, recipient tampering/authorization, 64-char TXID explorer URL, transaction pagination/reorg/RBF, P0 gates. Swift native unit/UI tests and safe read-only BTCB2 MainNet verification; empty-wallet backup/restore only with explicit user authorization. Add per-send Security.framework user-presence tests on a real Mac; mock-only tests cannot prove hardware authentication. **No TestNet/RegTest/Signet UI or shipped runtime; no spending real funds for tests.**

No public **real-funds** endorsement until all P0s pass plus wallet backup/recovery, release notarization, signed updater, license/notice and independent security review. Preserve the existing application support directory, bundle ID, Keychain service and blockchain history during the v7 change; don't create a second wallet as a side effect.

**Source references (read-only):** Admin Node Console's `src/status_server.py` and `src/wallet_registry.py`; public BTCB2 chain guidance: https://bitcoin-blake2b.org/developers ; BTCB2 explorer: https://mempool.guide ; primary reference client release: https://github.com/bitcoinknots/bitcoin/releases/tag/v29.4.3.knots20260508 .
