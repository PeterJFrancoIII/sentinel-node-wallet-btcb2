# NODE Pocket Architecture & Consensus Model

## 1. System Architecture

NODE Pocket is structured into two cleanly separated layers:

```text
┌────────────────────────────────────────────────────────┐
│                   NODE Pocket App                      │
│            SwiftUI Interface & User Actions            │
│  (Dashboard, Sync Profiles, Wallet Manager, Console)  │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                   NodePocketCore                       │
│  ┌──────────────────┐  ┌─────────────────────────────┐ │
│  │   NodeManager    │  │        WalletManager        │ │
│  │ (Process/Config) │  │   (Encrypted Descriptors)   │ │
│  └────────┬─────────┘  └──────────────┬──────────────┘ │
│           │                           │                │
│  ┌────────▼─────────┐  ┌──────────────▼──────────────┐ │
│  │  HashrateTracker │  │      BitcoinRPCClient       │ │
│  │  (BIP-110 Work)  │  │   (Localhost JSON-RPC 1.0)  │ │
│  └──────────────────┘  └─────────────────────────────┘ │
└───────────────────────────┬────────────────────────────┘
                            │ Localhost RPC (127.0.0.1)
┌───────────────────────────▼────────────────────────────┐
│         Bitcoin Knots Daemon (bitcoind BTCB2)          │
│            BIP-110 BLAKE2b Consensus Engine            │
└────────────────────────────────────────────────────────┘
```

---

## 2. BIP-110 / BLAKE2b Consensus Verification

NODE Pocket enforces that all block validation and network metrics conform to the **BIP-110 hard-fork specification** activated on September 1, 2026:

1. **Target & Difficulty Arithmetic:**
   - Base difficulty $D = 1.0$ is defined by `DIFF1_TARGET`:
     $$\text{DIFF1} = \text{0x00000000FFFF0000000000000000000000000000000000000000000000000000}$$
   - Difficulty is derived from the 256-bit block target:
     $$\text{Difficulty} = \frac{\text{DIFF1\_TARGET}}{\text{Target}}$$
   - Expected hashes per block:
     $$E = \frac{2^{256}}{\text{Target} + 1} = \text{Difficulty} \times 2^{32}$$

2. **Network Hashrate Estimation:**
   - Rather than relying on third-party aggregators or synthetic single-block estimates, NODE Pocket aggregates empirical block samples over a rolling window of $k = 30$ blocks:
     $$\text{Network Hashrate (H/s)} = \frac{\sum_{i=1}^{k} E_i}{\sum_{i=1}^{k} \Delta t_i}$$
   - If a miner timestamp anomaly produces $\Delta t \le 0$, the interval is preserved in audit logs but excluded from the rate denominator, preventing artificial hashrate explosions.
   - If telemetry age exceeds 300 seconds, the metric is marked `STALE` in the UI.

3. **Block Template Rules:**
   - Requires `["segwit", "blake2b"]` in `getblocktemplate` calls. Ordinary SHA-256d Bitcoin mainnet blocks are rejected.

---

## 3. Dynamic Sync Profiles

| Parameter | Quiet Profile | Balanced Profile | Fast Profile |
| :--- | :--- | :--- | :--- |
| **Target Host** | MacBook Air (Battery) | Desktop / Daily | AC Power (IBD) |
| **Verification Threads (`par`)** | 1 thread | 2 threads | 4 threads |
| **DB Cache (`dbcache`)** | 100 MB | 450 MB | 2,048 MB |
| **Max Peers (`maxconnections`)** | 8 peers | 16 peers | 40 peers |
| **Max Upload (`maxuploadtarget`)**| 100 MB / day | 500 MB / day | 2,000 MB / day |
| **Prune Limit (`prune`)** | 550 MB | 2,000 MB | 10,000 MB |
| **Thermal / Battery Advisory** | Silent, zero fan noise | Minimal impact | High throughput |

---

## 4. Wallet Security & Keychain Integration

- **Modern Descriptors:** Uses native output descriptors for SegWit (Bech32) addresses (`createwallet` with `descriptors=true`).
- **Encrypted at Rest:** Passphrase encryption is required prior to generating addresses or signing.
- **Keychain Storage:** Passphrases can be saved in the macOS Keychain (`com.nodepocket.btcb2.wallet`) only upon explicit user opt-in (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Silent extraction from system passwords or Apple Passwords databases is strictly prevented.
- **Deterministic Backups:** One-click encrypted backup export to user-designated destinations.
