# Sentinel Node Wallet - BTCB2

> **Minimal, self-custodial BTCB2 BLAKE2b MainNet wallet and validating Bitcoin Knots node for macOS.** Active pruning by default, optional archival history, network hashrate, dynamic synchronization ETA, and a secure native Wallet Manager.

**Development status — not approved for real funds or public binary distribution.** Swift/Python test receipts document development progress, not independent wallet-security certification. Apple Developer ID signing, notarization, secured auto-updates, full wallet recovery and an independent security review are release gates. [Security policy](SECURITY.md) · [Release matrix](TEST_AND_RELEASE_MATRIX.md).

## Three screens. No unnecessary services.

| Screen | Purpose |
| --- | --- |
| **Node** | Verified BTCB2 BLAKE2b MainNet sync, node health, adaptive time remaining, disk safety, Quiet/Balanced/Fast profiles and storage options. |
| **Wallet** | Local encrypted descriptor wallet, receive QR, balances, coinbase maturity countdown, fee-aware sending, named trusted recipients and full transaction history. See [Wallet Manager v7](docs/WALLET_MANAGER_V7.md) for planned security requirements and implementation status. |
| **Network** | Locally derived BLAKE2b network hashrate, 30/120-block trends, freshness and difficulty. |

One native **SwiftUI** application supervises one official, verified fork-compatible **Bitcoin Knots** node. Its dedicated app data and Keychain items are isolated from external mining pools, admin consoles, enterprise networks, ASIC firmware and all other projects. No Electron, Docker, hosted wallet, miner, gateway or analytics service.

### BTCB2 MainNet, not ordinary BTC

The BIP-110-aligned network switched from SHA-256d to BLAKE2b at height **961,640**. Ordinary Bitcoin Core, standard SHA-256d Bitcoin MainNet and the same-looking `bc1` addresses are **not proof of this chain**. Every sensitive wallet operation must verify the BLAKE2b block at that height, subsequent trusted chain evidence and a current synchronized tip. Only BTCB2 MainNet is shipped: no TestNet, RegTest, Signet or network selector.

### Disk space: pruned by default

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

## License and notices

The source is visible on GitHub; **public visibility is not an open-source license**. The project license must be approved by the owner and committed as a `LICENSE` file before declaring a licensing grant or general distribution. See [NOTICE](NOTICE.md) for upstream Bitcoin Knots attribution and third-party obligations. No private Admin Console or pool implementation is distributed.
