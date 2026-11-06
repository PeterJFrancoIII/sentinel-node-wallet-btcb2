# NODE Pocket (BTCB2)

> **Minimalist Sovereign Node & Wallet Manager for macOS (Apple Silicon)**  
> **Consensus Specification:** BIP-110 BLAKE2b Proof-of-Work Bitcoin Knots  
> **App Identifier:** `com.nodepocket.btcb2`

---

## Overview

**NODE Pocket** is a standalone, lightweight macOS application built with Swift and SwiftUI. It provides a simple, one-click experience for running a pruned Bitcoin Knots node with BIP-110 / BLAKE2b consensus, managing an encrypted descriptor wallet with user-consented macOS Keychain integration, and tracking network hashrate and difficulty directly from local block consensus.

Designed specifically for Apple Silicon (MacBook Air / Pro), NODE Pocket offers dynamic sync profiles to preserve battery and memory during everyday portable use, while allowing high-throughput sync when connected to power.

---

## Key Features

1. **Pruned Bitcoin Knots Subprocess Manager:**
   - Automated lifecycle control (start, graceful stop via RPC/SIGTERM, crash recovery).
   - Profiles:
     - **Quiet (Default):** 1 verification thread, 100 MB DB cache, 8 max peers, 550 MB pruned storage. Maximum battery conservation and silent background execution.
     - **Balanced:** 2 verification threads, 450 MB DB cache, 16 max peers, 2,000 MB pruned storage.
     - **Fast:** 4 verification threads, 2,048 MB DB cache, 40 max peers, 10,000 MB pruned storage.
2. **Consensus Hashrate & Difficulty Tracker:**
   - 100% locally calculated from consensus block headers and target work (BIP-110).
   - Rolling sample window (30 blocks) evaluating $\frac{\sum \text{expected\_hashes}}{\sum \Delta t}$.
   - Non-positive interval anomaly flagging to prevent artificial rate spikes.
   - Zero reliance on third-party or paid APIs.
3. **Encrypted Descriptor Wallet:**
   - Native SegWit (Bech32) receive address generation.
   - Modern output descriptor format.
   - User-consented macOS Keychain storage for passphrases (`com.nodepocket.btcb2.wallet`).
   - One-click wallet backup export.
4. **Strict Isolation by Design:**
   - Strict `127.0.0.1` RPC binding; zero external ingress.
   - Standalone application support directory: `~/Library/Application Support/NodePocketBTCB2` (`0700` directory, `0600` config permissions).
   - Zero shared code, credentials, dependencies, or runtime linking with any external or cross-project mining pools, firmwares, or daemons.

---

## Installation

### DMG Download
1. Download the latest release: `NodePocket-BTCB2-v0.1.0-macOS-arm64.dmg`.
2. Verify the SHA-256 checksum:
   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```
3. Open the disk image and drag **NODE Pocket** to your **Applications** folder.

---

## Building from Source

### Prerequisites
- macOS 13.0 (Ventura) or newer
- Apple Silicon Mac (`arm64`)
- Xcode 15+ or Command Line Tools (Swift 5.9+)

### Build Steps
```bash
# Clone repository
git clone https://github.com/nodepocket/node-pocket-btcb2.git
cd node-pocket-btcb2

# Run comprehensive test suite
swift test

# Build native release app and DMG installer
./scripts/build_dmg.sh
```

---

## Architecture & Verification

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for architectural details and [`docs/ISOLATION_REPORT.md`](docs/ISOLATION_REPORT.md) for empirical isolation test verification.

---

## License

MIT License.
