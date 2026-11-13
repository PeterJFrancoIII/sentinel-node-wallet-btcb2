# Sentinel Node Wallet — BTCB2

[![Release](https://img.shields.io/badge/Release-v1.0.0--Build2-blue.svg)](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0)
[![Tests](https://img.shields.io/badge/Tests-138%2F138%20Passing-brightgreen.svg)]()
[![Network](https://img.shields.io/badge/Network-BTCB2%20MainNet-orange.svg)]()
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B%20(Apple%20Silicon)-lightgrey.svg)]()

**Sentinel Node Wallet** is a standalone, self-custodial native macOS SwiftUI client for **Bitcoin Knots (BTCB2 BLAKE2b / BIP-110 MainNet)**. It bundles an embedded Bitcoin Knots daemon with an encrypted Native SegWit (Bech32) descriptor wallet, multi-operator security isolation, Touch ID biometric gating, and adaptive storage profiles.

- **Target App ID:** Apple App Store Connect App ID `6833290684`
- **Bundle Identifier:** `pool.sentineldefensetechnologies.co.za`
- **App Store Version:** `1.0` (Build `2`)
- **Canonical Repository:** [`PeterJFrancoIII/sentinel-node-wallet-btcb2`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)
- **Release Tag:** [`v1.0.0`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0)

---

## Table of Contents

1. [Key Features](#key-features)
2. [How to Fully Unload & Cleanly Uninstall Sentinel Node Wallet](#how-to-fully-unload--cleanly-uninstall-sentinel-node-wallet)
   - [Why macOS Leaves Data Behind Upon Trashing](#why-macos-leaves-data-behind-upon-trashing)
   - [Method 1: In-App 1-Click Clean Wipe & Uninstall (Recommended)](#method-1-in-app-1-click-clean-wipe--uninstall-recommended)
   - [Method 2: Standalone Shell Script (`scripts/clean_uninstall.sh`)](#method-2-standalone-shell-script-scriptsclean_uninstallsh)
   - [Method 3: Complete Manual Terminal Unload](#method-3-complete-manual-terminal-unload)
3. [Architecture & Security](#architecture--security)
   - [Multi-Operator Wallet Isolation](#multi-operator-wallet-isolation)
   - [Touch ID / Password Gated Keychain Autofill](#touch-id--password-gated-keychain-autofill)
   - [Interactive Knots Node Startup Prompt & Live Sync](#interactive-knots-node-startup-prompt--live-sync)
   - [Real-Time Fee Calculation & Net Recipient Model](#real-time-fee-calculation--net-recipient-model)
4. [Storage Modes & Hardware Optimization](#storage-modes--hardware-optimization)
5. [Development & Verification](#development--verification)
6. [License & Governance](#license--governance)

---

## Key Features

- **Embedded Bitcoin Knots Daemon:** Autonomous 1-click startup, loopback-only RPC (`127.0.0.1:8332`), and continuous daemon health/hashrate tracking.
- **Native SegWit (Bech32) Descriptor Wallets:** Fully encrypted local wallet databases using strict integer Satoshi arithmetic.
- **Multi-Operator Account Isolation:** Strict operator segregation; new operator accounts have zero access to existing operators' wallets.
- **Biometric Keychain Gating:** Operator credentials require Touch ID or Mac system password validation (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`).
- **Interactive Node Startup Prompt:** Detects node state on login, prompting operators to Enable or Bypass with a live blockchain synchronization progress card.
- **Dynamic Fee Recalculation:** Instant recalculation when selecting `MAX` balance or editing recipient amounts, preserving required fee headroom.
- **Ultra Power Policy:** Automatically throttles CPU threads, dbcache (128 MiB), and enforces max 4 outbound peers when running on MacBook battery power.

---

## How to Fully Unload & Cleanly Uninstall Sentinel Node Wallet

### Why macOS Leaves Data Behind Upon Trashing

On macOS, dragging an application (`.app`) to the Trash **never runs any uninstallation script** and **never deletes `Application Support` or container data automatically**. 

Apple designed macOS this way intentionally:
- The macOS Finder treats `.app` bundles as ordinary folders. Moving an app to the Trash is simply a filesystem move operation.
- Apple deliberately separates application binaries (`/Applications/*.app`) from user data (`~/Library/Application Support/*`) so that updating, troubleshooting, or reinstalling an app never deletes personal wallets, settings, or licenses.
- Applications cannot execute cleanup code while in the Trash because their process is already terminated.

Because the Bitcoin Knots node synchronizes **~18 GB** of blockchain blocks and chainstate databases, removing only the `.app` bundle from `/Applications` will leave this data on your hard drive. 

To completely unload and wipe Sentinel Node Wallet with **zero residual data left behind**, use one of the three methods below.

---

### Method 1: In-App 1-Click Clean Wipe & Uninstall (Recommended)

You can trigger a complete, verified data wipe directly from within the application before trashing the app:

1. Open **Sentinel Node Wallet**.
2. Navigate to **Node Settings** via either:
   - Top Menu Bar: **Help → Clean Uninstall & Storage Wipe…**
   - Node View: Click the **Gear icon** (or **Advanced Settings**) → scroll to **Clean Uninstall & Storage Wipe**.
3. Click the red **"Erase All Data & Uninstall…"** button (or click *"Reveal in Finder"* to inspect the directory).
4. Review the confirmation alert:
   > *"This will permanently delete all synchronized blockchain blocks, chainstate databases, UTXO indexes, and node configuration (~18 GB) from your Mac."*
5. Click **"Erase All Data & Quit"**:
   - The app gracefully halts the background `bitcoind` daemon.
   - It recursively deletes the entire `~/Library/Application Support/NodePocketBTCB2` data directory (~18 GB).
   - It clears all in-memory wallet states, sessions, and logs.
   - It displays: *"All data has been completely erased. You can now safely move Sentinel Node Wallet from /Applications to the Trash."*
6. Click **"Quit App Now"**, then drag `/Applications/Sentinel Node Wallet.app` to the Trash.

---

### Method 2: Standalone Shell Script (`scripts/clean_uninstall.sh`)

If you have already closed the app, or prefer an automated Terminal uninstaller, use the provided clean uninstall script:

```bash
cd /Users/computer/Developer/NodePocketBTCB2
./scripts/clean_uninstall.sh
```

**What this script does:**
1. Gracefully terminates any active `bitcoind` or `Sentinel Node Wallet` processes.
2. Recursively deletes `~/Library/Application Support/NodePocketBTCB2` (~18 GB).
3. Deletes the Mac App Store sandbox container `~/Library/Containers/pool.sentineldefensetechnologies.co.za` (if present).
4. Removes `/Applications/Sentinel Node Wallet.app` from your Applications folder.
5. Reclaims 100% of the disk space with interactive confirmation.

---

### Method 3: Complete Manual Terminal Unload

For power users or automated deployment scripts, run the following commands in Terminal:

```bash
# 1. Gracefully stop the Bitcoin Knots daemon and app process
killall bitcoind 2>/dev/null || true
pkill -f "Sentinel Node Wallet" 2>/dev/null || true
sleep 1

# 2. Delete the 18 GB node sync and wallet data directory
rm -rf "$HOME/Library/Application Support/NodePocketBTCB2"

# 3. Delete the Mac App Store sandbox container (if running sandboxed build)
rm -rf "$HOME/Library/Containers/pool.sentineldefensetechnologies.co.za"

# 4. Remove the application bundle from /Applications
rm -rf "/Applications/Sentinel Node Wallet.app"

echo "Sentinel Node Wallet and all supporting data have been completely removed."
```

---

## Architecture & Security

### Multi-Operator Wallet Isolation
Sentinel Node Wallet enforces strict per-operator isolation:
- The metadata registry maps every descriptor wallet to its creator's canonical operator account (`walletOwners: [String: String]`).
- New operator accounts initialize with zero wallet access until explicitly creating or onboarding a wallet.
- High-risk operations (`loadWallet`, `selectWallet`, `archiveWallet`, `deleteWalletFromMac`, `bumpFee`, `exportBackup`, `restoreWallet`, `prepareSendPreview`) fail closed if called across operator boundaries.

### Touch ID / Password Gated Keychain Autofill
- Login fields start completely blank; background Keychain sniffing on screen appearance is disabled.
- Autofilling credentials or 1-click login requires hardware Touch ID or Mac password authentication (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`).
- TOTP secrets are stored in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to prevent authorization errors.

### Interactive Knots Node Startup Prompt & Live Sync
- When an operator signs in while the Knots Node is offline, an interactive prompt window appears:
  - **Enable Knots Node:** Starts the node daemon, binds loopback RPC, loads the operator's wallet, and dismisses upon connection.
  - **Bypass:** Allows offline standby access to the Wallet Manager without blocking the operator.
- A dynamic offline banner remains visible with a 1-click "Turn On Node" button if bypassed.
- While synchronizing, a live status banner tracks current block height, validated headers, and percentage progress, actively streaming confirmed balances as blocks arrive.

### Real-Time Fee Calculation & Net Recipient Model
- **Net Recipient Model:** The amount entered in "Amount to Send" represents the exact net amount the counterparty will receive.
- **MAX Button:** Automatically computes `Available Balance - Estimated Transaction Fee` to avoid balance exhaustion.
- **Fixed-Point Formatting:** Enforces strict 8-decimal string formatting (`0.00000001`) to prevent floating-point scientific notation RPC errors (`RPC Server Error (-3): Invalid amount`).

---

## Storage Modes & Hardware Optimization

| Profile | Threads | dbcache | Max Connections | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **Quiet** | 1 | 256 MiB | 8 | Thermal-conscious, silent background sync |
| **Balanced** | 2 | 512 MiB | 24 | Default everyday balance of speed and efficiency |
| **Fast** | 4 | 1024 MiB | 40 | Rapid Initial Block Download (IBD) on AC power |
| **Ultra (Battery)** | 1 | 128 MiB | 4 (`listen=0`) | Automatic hardware preservation on battery power |

- **Compact Pruning:** Enforces minimum 550 MiB block/undo pruning to minimize disk usage on storage-constrained Macs.
- **Archival Mode:** Retains complete historical block data for archival operators and external storage volumes.

---

## Development & Verification

### Prerequisites
- macOS 13.0+ (Ventura, Sonoma, Sequoia)
- Apple Silicon (M1/M2/M3/M4)
- Xcode 15+ and Swift 5.9+

### Running the Test Suite
```bash
cd /Users/computer/Developer/NodePocketBTCB2
swift test
```
*Current test suite status:* **138 tests passed, 0 failures, 1 interactive keychain test skipped (100% pass rate)**.

### Packaging for Mac App Store
```bash
./scripts/package_appstore_archive.sh
```
Compiles, seals, and packages `Sentinel Node Wallet.pkg` using Apple Cloud Managed Signing and App Sandboxing.

---

## License & Governance

- Distributed under the terms specified in [NOTICE.md](NOTICE.md).
- Canonical operating and coordination directives adhere to [Shared Memory Agent Rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md).
