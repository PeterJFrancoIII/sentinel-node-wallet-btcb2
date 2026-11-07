# Sentinel Node Wallet - BTCB2

> Native macOS BTCB2 BLAKE2b mainnet wallet and Bitcoin Knots validating node. 550 MiB pruning, adjustable storage, optional archival history, Keychain security, network hashrate and sync ETA.

[![macOS](https://img.shields.io/badge/platform-macOS%2013%2B%20(Apple%20Silicon)-black.svg)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.4.2%20%2F%20SwiftUI-orange.svg)](https://swift.org)
[![Consensus](https://img.shields.io/badge/consensus-BIP--110%20BLAKE2b-blue.svg)](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## Important Notices & Disclaimer

> [!WARNING]
> **DEVELOPMENT & EVALUATION RELEASE ONLY**  
> This build is strictly for local testing, consensus validation, and peer evaluation. Public binary releases and distribution are gated until formal Apple Developer ID code signing, Apple Notarization, Gatekeeper validation, signed Sparkle update delivery, and an independent security audit are completed.

> [!IMPORTANT]
> **Consensus & Network Scope: BTCB2 BLAKE2b MainNet Only**  
> Sentinel Node Wallet operates exclusively on the **BTCB2 BLAKE2b / BIP-110 MainNet** (hard fork checkpoint at height `961,640`, block hash `0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb`). It is **NOT** compatible with ordinary SHA-256d Bitcoin mainnet, nor are testnets or regtest enabled in production builds.

> [!NOTE]
> **Pruning vs. Disk Footprint Clarification**  
> The default `prune=550` (550 MiB) setting restricts **raw blockfile storage**. It does **not** cap the total node data directory size. The UTXO coins database (`chainstate`), block index, and wallet database grow independently (~5–15 GB). Sentinel Node Wallet actively monitors host disk space, warns the operator at 35 GB total datadir usage, and gracefully suspends sync if host free space drops below 10 GB.

---

## Discoverability & GitHub Topics

Repository: `PeterJFrancoIII/sentinel-node-wallet-btcb2`

Topics:
`btcb2`, `bitcoin-blake2b`, `blake2b`, `bip110`, `bitcoin-knots`, `macos`, `macos-app`, `swift`, `swiftui`, `apple-silicon`, `bitcoin-wallet`, `non-custodial`, `self-custody`, `wallet-manager`, `pruned-node`, `full-node`, `blockchain-node`, `low-storage`, `network-hashrate`, `sentinel-node-wallet`

---

## Core Capabilities

### 1. Embedded Bitcoin Knots Validating Node
- Bundles official Bitcoin Knots `v29.4.3.knots20260508` compiled natively for Apple Silicon (`arm64`).
- Full sovereign consensus verification from genesis through the BIP-110 BLAKE2b transition.
- Fail-closed fork checkpoint enforcement: automatically rejects any block sequence that attempts to continue legacy SHA-256d consensus past height 961,640.

### 2. Dual Storage Architecture
- **Compact Pruned (Default):**
  - Active from initial block download: `prune=550` and `pruneduringinit=550`.
  - Operator-customizable retention selector ($\ge 550$ MiB, e.g. 1 GB, 2 GB, 4 GB, or custom integer).
  - Designed for internal laptop SSDs (MacBook Air / MacBook Pro).
  - Disk safety guards: Alert at $\ge 35$ GB datadir; automatic graceful stop at $\ge 40$ GB datadir or $\le 10$ GB free host storage.
- **Full-History / Archival Mode (Opt-in):**
  - Fully unpruned (`prune=0`) retaining 100% of historical block data (~800+ GB).
  - Hard-gated against internal drive installation (<50 GB free) to protect macOS system stability.
  - Requires preflight-verified external high-capacity drive or SSD with $\ge 1$ TB free space.
  - Clear confirmation warnings regarding complete historical reindex / redownload requirements.

### 3. Adaptive Verification Progress ETA
- Computes empirical block verification speed using monotonic, rolling-window throughput smoothing.
- Displays auto-scaled time remaining: `~2w 3d`, `~3d 7h`, `~5h 24m`, `~18m 42s`, `~47s`, or `~0s`.
- Transparent state indicators: `Calibrating...`, `Estimating`, `Waiting for peers`, `Stalled`, or `Synchronized`.

### 4. Non-Custodial Encrypted Descriptor Wallet
- Modern output descriptors with Native SegWit (Bech32, `bc1...`) addresses.
- Passphrase protection using Apple Keychain Services (`app.nodepocket.btcb2.wallet`).
- Zero plaintext passphrases or unencrypted private keys written to disk.
- Send transaction gating: Transacting is locked until Initial Block Download (IBD) is complete and the chain tip is verified past the BIP-110 fork.

### 5. Local Consensus Hashrate Tracker
- 100% locally calculated from consensus block headers and target work difficulty.
- Zero reliance on external, proprietary, or paid third-party APIs.
- Rolling 30-block work window with anomaly filtering for non-positive block timestamps.

### 6. Strict Isolation by Architecture
- RPC binds exclusively to `127.0.0.1` on local loopback. External ingress is disabled.
- Zero code sharing, networking, or credential links with mining pools, remote servers, or external services.

---

## Architecture Overview

```mermaid
flowchart TD
    App[Sentinel Node Wallet macOS App\nSwiftUI / Swift 6.4.2] --> AppState[AppState Coordinator]
    AppState --> NodeMgr[NodeManager Process Supervisor]
    AppState --> WalletMgr[WalletManager Descriptor Service]
    AppState --> ETAMgr[AdaptiveETAEngine]
    AppState --> HealthMgr[SystemHealthMonitor]

    NodeMgr -->|Spawns / Manages| Knots[Embedded Bitcoin Knots bitcoind\nv29.4.3.knots20260508 arm64]
    Knots -->|Loopback JSON-RPC\n127.0.0.1:8332| RPC[BitcoinRPCClient]
    RPC --> NodeMgr

    WalletMgr -->|Passphrase Secure Storage| Keychain[Apple Keychain Services\napp.nodepocket.btcb2.wallet]
    WalletMgr -->|Descriptor RPC| RPC

    Knots -->|Compact Pruned default 550 MiB| InternalDisk[~/Library/Application Support/NodePocketBTCB2]
    Knots -.->|Archival Mode opt-in >= 1 TB| ExternalSSD[/Volumes/ExternalSSD/BTCB2Archival]
```

---

## Building from Source

### Prerequisites
- macOS 13.0 (Ventura) or newer
- Apple Silicon Mac (`M1/M2/M3/M4`, `arm64`)
- Xcode 15+ with Swift 5.9+ / 6.x

### Build & Package
```bash
# Clone the repository
git clone https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2.git
cd sentinel-node-wallet-btcb2

# Run test suite (25/25 unit & integration tests)
swift test

# Build native release app bundle
./scripts/build_app.sh

# Package macOS DMG
./scripts/build_dmg.sh
```

---

## License

This project is licensed under the [MIT License](LICENSE). Embedded Bitcoin Knots components are copyright © 2009–2026 The Bitcoin Core Developers and Bitcoin Knots Contributors, under the MIT License.
