# Sentinel Node Wallet - BTCB2

> **Minimal, self-custodial BTCB2 BLAKE2b MainNet wallet and validating Bitcoin Knots node for macOS.** Active pruning by default, automatic Ultra power management on battery/charging, All-Wallet inventory with reversible archive and safe trash deletion, dynamic rolling historical coverage, network hashrate, and a secure native Wallet Manager.

**Development status — not approved for real funds or public binary distribution.** Swift/Python test receipts document development progress, not independent wallet-security certification. Apple Developer ID signing, notarization, secured auto-updates, full wallet recovery and an independent security review are release gates. [Security policy](SECURITY.md) · [Release matrix](TEST_AND_RELEASE_MATRIX.md) · [V12 Specification](docs/POWER_WALLET_INVENTORY_V12.md).

## Three screens. No unnecessary services.

| Screen | Purpose |
| --- | --- |
| **Node** | Verified BTCB2 BLAKE2b MainNet sync, node health, adaptive time remaining, disk safety, single Settings gear, read-only Storage Footprint rolling history, Quiet/Balanced/Fast profiles with automatic **Ultra Power Saving** when on battery or charging. |
| **Wallet** | All-Wallet Inventory listing all local wallets with per-wallet balances, reversible **Archive**, safe **Delete from this Mac** via macOS Trash, local encrypted descriptor wallet, receive QR, coinbase maturity countdown, fee-aware sending, and full transaction history. See [V12 Specification](docs/POWER_WALLET_INVENTORY_V12.md) and [Wallet Manager v7](docs/WALLET_MANAGER_V7.md). |
| **Network** | Locally derived BLAKE2b network hashrate, 30/120-block trends, freshness, P2P peer topology, and difficulty. |

One native **SwiftUI** application supervises one official, verified fork-compatible **Bitcoin Knots** node. Its dedicated app data and Keychain items are isolated from external mining pools, admin consoles, enterprise networks, ASIC firmware and all other projects. No Electron, Docker, hosted wallet, miner, gateway or analytics service.

### Automatic Ultra Power Policy (V12)
- **Continuous IOKit Monitoring:** Queries `IOPSCopyPowerSourcesInfo` for battery power, active charging, and macOS Low Power Mode.
- **Ephemeral Resource Clamps:** When on battery or actively charging, Knots automatically applies lightweight parameters (`par=1`, `dbcache=128MiB`, `maxconnections=12`, `maxuploadtarget=128MiB`) ephemerally without modifying `bitcoin.conf`.
- **Preferred Profile Preservation:** User's preferred Quiet/Balanced/Fast profile remains safely stored and automatically resumes when the Mac returns to stable AC power without charging.

### All-Wallet Inventory & Multi-Wallet Safety (V12)
- **Per-Wallet Isolation:** Individual RPC calls (`/wallet/<name>`) for each loaded wallet prevent cross-wiring. Integer satoshi math guarantees zero precision loss.
- **Multi-Wallet Discovery:** Enumerate all created wallets on disk via `listwalletdir` and `listwallets`. Unloaded wallets display cached timestamps or `Unavailable — Load to refresh`.
- **Reversible Archive:** Unloads wallet from memory (`unloadwallet`) and collapses into Archived section without modifying files or deleting Keychain credentials.
- **Safe Reversible Deletion:** Refuses deletion if balance > 0, pending > 0, immature > 0, or balance state is unknown. Requires mandatory fresh backup export, user presence, typed wallet name confirmation, and moves files to **macOS Trash** (`FileManager.trashItem`).

### Disk space: pruned by default

**Live rolling history:** Storage Footprint displays approximately how far back its **currently retained historical blocks** reach, plus a live-data forecast for the selected 550 MiB/1/2/4 GiB/custom budget. Units automatically switch between years, months, weeks, days and hours. [Rolling historical coverage specification](docs/ROLLING_HISTORY_COVERAGE_V11.md).



| Mode | Policy |
| --- | --- |
| **Compact** (default) | New installs use `prune=2048` MiB after initial sync and `pruneduringinit=550` MiB while syncing. Selectable 550 MiB minimum, 1/2/4 GiB or validated custom. Existing settings remain unchanged. |
| **Storage protection** | Warn at 35 GiB app data; graceful pause by 40 GiB or around 10–12 GiB host free, preserving wallet data. Target **under 50 GiB total**, not a hard guarantee. |
| **Full History** (explicit opt-in) | `prune=0`, complete historical redownload/reindex, sufficient capacity (typically a dedicated external SSD), verified backup and safe rollback. |

**550 MiB during IBD and the 2048 MiB post-sync target limit retained block/undo files, not the entire node directory.** Chainstate, indexes, wallet files and temporary operations consume more space. Even a pruned node downloads and validates historical blocks before discarding them; it remains a **fully validating node**. Full History additionally stores and can serve historical blocks when reachable.

### Wallet Manager — target v7 parity with the Admin Console

- **Mature / immature / pending / spendable** BTCB2 balances. Coinbase rules use the **reward's originating height**: 100 blocks before 973,440; 6,480 blocks for 973,440–979,918; 25,920 blocks from 979,919 until the September 2027 rule expiry; then the applicable node-reported consensus rules. Previously minted 45-day rewards do not become 180-day rewards. Per-reward maturity block, remaining blocks and approximate w/d/h/m/s ETA are displayed; non-coinbase transfers are not subject to coinbase maturity.
- **Cheapest / Normal / Fast / Custom** transfer fees: local-node dynamic rates, tentative 24/6/2-block inclusion targets, actual PSBT-based fee/virtual-size preview, and honest estimated time ranges. No guessed fees, fake precision or silent broadcast.
- **Named trusted recipients** and enforced address allowlist; identity confirmation and reauthorization for additions, edits, bypasses and each spend.
- **History and TXID detail:** all available wallet records with fees, confirmation/reorg/immature/RBF states, search and pagination. Explicit-click BTCB2 explorer links use [mempool.guide](https://mempool.guide), **not ordinary mempool.space** (which indexes a different Bitcoin chain).
- **Security first:** Keychain user presence, encrypted wallets only, replay-safe SIGHASH_UNIFIED signing verified on the actual fork, preview bound to the eventual broadcast, no plaintext secret fallback, no remote wallet RPC. **Sending is not approved until all v7 P0 gates are proven and tested.**

A hot wallet on a fully compromised Mac cannot promise perfect protection. Enable FileVault, keep macOS updated, protect login credentials and consider an offline/hardware signer for high-value funds.

## Minimal consensus-security node defaults

The default is **Balanced**: 2 verification threads, 512 MiB database cache, a **24-peer ceiling**, and modest recent-block retention. Quiet allows 16 maximum peers and Fast 32; these are capacities, not guarantees of actual peer count. Around 10–11 automatically selected outbound peers can be normal across every profile. The node independently validates BTCB2 MainNet, relays blocks and transactions, and permits inbound P2P when reachable, but never automatically maps the router (`natpmp=0`, `upnp=0`). RPC stays on 127.0.0.1. Changes must not force a new wallet, reset sync, open router ports or modify an existing prune target. [Consensus security specification](docs/MINIMAL_CONSENSUS_SECURITY_V10.md).

## Sync modes and generated wallet encryption passphrases (candidate fix)

Quiet / Balanced / Fast change verification threads, database-cache size and peer limits; they do **not** change the selected pruning amount. Settings are saved and, when this app owns the daemon, applied after one graceful restart. Failed application must be visible; an unverified adopted node is never force-stopped. **These changes still require native macOS acceptance tests.**

The Create Encrypted Wallet dialog offers **Generate Strong Passphrase** (256-bit system entropy) and optional **Save in macOS Keychain**, with wallet name and user-presence-protected retrieval. **Use Saved Passphrase** allows owner-authorized entry later. This is an **encryption passphrase, not a recovery seed**, and a separate wallet-file backup is essential. The macOS **Keychain** is not the same as Apple's **Passwords** app: generic native Keychain items are not guaranteed to appear as website logins or receive Passwords autofill. See [sync and Keychain fix tests](docs/SYNC_AND_KEYCHAIN_FIX.md).

## Installation and development

**Target:** Apple Silicon macOS 13+; existing internal app identifier/data paths may remain under the former development name to protect existing wallet and sync state. Branding changes must never initialize a new wallet or delete old blockchain files.

```bash
git clone https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2.git
cd sentinel-node-wallet-btcb2
swift test
```

The repository currently contains development source and documentation. Do **not** treat an ad-hoc-signed DMG as a notarized public release. See [Governance](GOVERNANCE.md), [Security](SECURITY.md), [Architecture](docs/ARCHITECTURE.md) and [Test & release matrix](TEST_AND_RELEASE_MATRIX.md). Wallet behavior remains subject to [v7 acceptance criteria](docs/WALLET_MANAGER_V7.md).

## Roadmap: deliberately not in this release

One-click **DATUM Gateway** provisioning may be added in a future independently reviewed phase. No DATUM, Stratum, mining, pool access, unattended auto-send, cloud account or other additional service is being shipped today.

## Final Wallet Manager authentication — v13 (implementation pending)

The release target is one **local, offline-first Wallet Manager login** with a user-selected username, strong password and time-based one-time verification code (TOTP). The Wallet tab remains locked until authorized; Node and Network continue syncing without wallet login. Every wallet-sensitive operation requires an internally enforced session, and spending, backups, recipient edits and wallet deletion additionally require fresh macOS owner presence. No account/password/TOTP secret is shared with a server.

**Apple Passwords support is a release gate, not a completed feature.** System-authorized username/password saving and autofill requires an app-controlled `webcredentials` associated domain, matching AASA/Apple Team ID and properly signed macOS app. Apple Passwords can also hold verification codes, but storing password and TOTP together weakens factor independence; Touch ID/device-owner step-up remains mandatory. Generic macOS Keychain items do not automatically appear in Apple Passwords. No unapproved domain will be attached or cloud login added.

Read [Final authentication v13](docs/FINAL_WALLET_AUTH_V13.md) and [production security audit](docs/FINAL_PRODUCTION_SECURITY_AUDIT_V13.md). Both are implementation/test specifications; **no real-funds or public release approval has been granted**.

## License and notices

The source is visible on GitHub; **public visibility is not an open-source license**. The project license must be approved by the owner and committed as a `LICENSE` file before declaring a licensing grant or general distribution. See [NOTICE](NOTICE.md) for upstream Bitcoin Knots attribution and third-party obligations. No private Admin Console or pool implementation is distributed.
