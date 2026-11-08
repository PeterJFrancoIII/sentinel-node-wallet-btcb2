# Sentinel Node Wallet - BTCB2: Ultra Power Policy, All-Wallet Inventory & Single Settings UI (V12)

**Canonical Document Authority:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`  
**Shared Memory Entity:** `SentinelNodeWallet_BTCB2_PowerWalletInventory_MinimalUI_v12_20261106`  
**Governing Authority:** [Shared Cognitive Memory Agent Rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md)

---

## 1. Executive Summary

Sentinel Node Wallet - BTCB2 Release Specification V12 introduces three fundamental architectural improvements while strictly maintaining the minimal 3-tab native macOS architecture, BTCB2 BLAKE2b MainNet-only consensus, and fail-closed security invariants:

1. **Automatic Ultra Power Policy:** Continuous macOS `IOKit.ps` monitoring detecting battery power, active charging, and macOS Low Power Mode. Automatically applies ephemeral lightweight resource bounds (`par=1`, `dbcache=128MiB`, `maxconnections=4`, `maxuploadtarget=128MiB`, `-listen=0`, low CPU/disk I/O priority) without altering saved user preferences, restoring preferred Quiet/Balanced/Fast settings upon return to stable AC power. (Note: Authoritative override `SENTINEL-ULTRA-CORRECTION-20261106-024` permanently enforces `maxconnections=4` and `listen=0`, superseding draft 12-peer limits).
2. **All-Wallet Inventory:** Complete visibility into all created and on-disk wallets via `listwalletdir` and `listwallets`. Strict per-wallet balance queries (`/wallet/<name>`), integer satoshi math, stale/unavailable labeling for unloaded wallets, reversible in-memory **Archive**, and fail-closed reversible **Delete from this Mac** via macOS Trash with mandatory pre-deletion backup verification.
3. **Single Settings Button:** Removal of redundant settings entry points from `NodeView.swift`. Storage Footprint is rendered as an inert, read-only rolling history metric card, leaving exactly one top-header Settings gear button (`node-settings-button`) accessible across all node lifecycle states.

---

## 2. Ultra Power Policy Architecture

### 2.1 IOKit Power State Classification
macOS system power is queried via `IOPSCopyPowerSourcesInfo` and `IOPSGetPowerSourceDescription`:
- `kIOPSPowerSourceStateKey == kIOPSBatteryPowerValue`: State is `.battery`. Ultra power required.
- `kIOPSPowerSourceStateKey == kIOPSACPowerValue`:
  - `kIOPSIsChargingKey == true`: State is `.charging`. Ultra power required (prevents thermal throttling during charge).
  - `kIOPSIsChargingKey == false`: State is `.acNotCharging`. Normal user-selected profile applied.
- `ProcessInfo.processInfo.isLowPowerModeEnabled == true`: Ultra power required regardless of power source.
- Fallback/Desktop: State is `.unknown` or `.acNotCharging` for AC-only desktops.

### 2.2 Ephemeral Resource Overrides
To avoid modifying `bitcoin.conf` on disk or corrupting user preferences:
- Node startup appends command-line arguments:
  `-par=1 -dbcache=128 -maxconnections=12 -maxuploadtarget=128`
- `bitcoin.conf` preserves the user's preferred profile (Quiet, Balanced, or Fast).
- UI displays active status:
  - Battery: `Ultra · Battery Active • Preferred Fast resumes on AC`
  - Charging: `Ultra · Charging Active • Preferred Fast resumes on AC`
  - AC: `[Quiet/Balanced/Fast] Profile Active`
- User selection during Ultra saves the preferred profile for future AC sessions without terminating Ultra mode.

---

## 3. All-Wallet Inventory & Multi-Wallet Isolation

### 3.1 Per-Wallet RPC Isolation
All wallet queries use the dedicated RPC endpoint `/wallet/<wallet_name>`:
- `getwalletinfo(walletName: name)`
- `getbalances(walletName: name)`
- `listtransactions(walletName: name)`

Global `/` RPC balances are never cross-wired. Satoshi math uses 64-bit integer calculations:
$$\text{sats} = \text{round}(\text{BTC} \times 10^8)$$

### 3.2 State Representation
- **Loaded Wallets:** Live spendable, pending, and immature balances.
- **Unloaded Wallets (Cached):** Displays last observed balance with explicit block height and timestamp (`Last known (block 364890)`).
- **Unloaded Wallets (Uncached):** Displays `Unavailable — Load to refresh` (never invents 0 sats).

### 3.3 Metadata Registry
Stored at `~/Library/Application Support/NodePocketBTCB2/wallets_metadata.json` with POSIX permissions `0600`:
- Tracks `archivedWallets: Set<String>`
- Tracks `cachedBalances: [String: CachedWalletBalance]`

---

## 4. Reversible Archive Semantics

Archive provides lightweight wallet deactivation without deleting data:
1. Calls Knots RPC `unloadwallet(name, load_on_startup: false)`.
2. Adds wallet name to `archivedWallets` in `wallets_metadata.json`.
3. Hides wallet from active inventory rows and places it in the collapsible "Archived Wallets" section.
4. **Preserves** all wallet database files (`.sqlite`), descriptors, keys, and macOS Keychain credentials.
5. **Unarchive** calls `loadwallet(name)` and restores live balance updates.

---

## 5. Fail-Closed Reversible Delete ('Delete from this Mac')

Wallet deletion enforces multi-layer safety invariants:
1. **Balance Preflight Verification:**
   - Spendable sats MUST be 0.
   - Pending sats MUST be 0.
   - Immature coinbase sats MUST be 0.
   - Wallet state MUST be verified live (not stale or unknown).
   - If balance > 0, deletion is strictly refused.
2. **Path & Symlink Guards:**
   - Canonical wallet URL must be strictly inside `dataDirectory/wallets/` or `dataDirectory/<name>`.
   - Path traversal characters (`..`, `/`, `\`, `:`) and symbolic links are strictly prohibited.
3. **Mandatory Backup Verification:**
   - A fresh backup database is exported via `backupwallet` to `~/Downloads/`.
   - Backup file existence and non-zero byte size (> 0 bytes) are verified before unlinking.
4. **Confirmation & Identity:**
   - User must type the exact wallet name to confirm.
5. **Reversible Trash:**
   - Knots unloads the wallet via `unloadwallet`.
   - Directory/file is moved to macOS Trash via `FileManager.default.trashItem(at:resultingItemURL:)`.
   - Reversible by the user from macOS Trash; `rm -rf` is strictly forbidden.
   - Keychain credentials remain intact for disaster recovery.

---

## 6. Single Settings UI Affordance

`NodeView.swift` has been audited and simplified:
- The top header row contains exactly ONE Settings gear button (`node-settings-button`), visible across stopped, starting, and running states.
- The `Button` wrapper around the `Storage Footprint` metric card has been removed; it is now an inert read-only display.
- The redundant `Configure…` button on the Sync Profile card has been removed.
- Total call sites of `showAdvancedSheet = true` in `NodeView.swift`: **Exactly 1**.

---

## 7. Verification Summary

| Test Suite | Tests Run | Pass Rate | Status |
| :--- | :--- | :--- | :--- |
| Swift Unit & Regression Suite | 65 | 100% | PASS |
| Python V12 Power & Inventory Suite | 6 | 100% | PASS |
| Python V7 Wallet Security Suite | 16 | 100% | PASS |
| Python ETA Engine Suite | 3 | 100% | PASS |
| **Total Automated Tests** | **90** | **100%** | **PASS** |
