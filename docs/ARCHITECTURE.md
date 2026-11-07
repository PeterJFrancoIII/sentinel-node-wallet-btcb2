# Sentinel Node Wallet Architecture & Consensus Model

## 1. System Architecture

Sentinel Node Wallet is structured into two cleanly separated layers:

```mermaid
flowchart TD
    subgraph UI [Sentinel Node Wallet App (SwiftUI)]
        Views[NodeView / WalletView / NetworkView]
        Advanced[AdvancedSheet Storage & Profile Config]
    end

    subgraph Core [NodePocketCore Framework]
        AppState[AppState Coordinator]
        NodeMgr[NodeManager Process Supervisor]
        StorageMgr[StorageMode Engine]
        ETAMgr[AdaptiveETAEngine]
        WalletMgr[WalletManager Descriptor Service]
        HashTracker[HashrateTracker BIP-110 Engine]
        RPCClient[BitcoinRPCClient 127.0.0.1]
    end

    subgraph Daemon [Embedded Process]
        Knots[Bitcoin Knots bitcoind v29.4.3.knots20260508 arm64]
    end

    Views --> AppState
    Advanced --> AppState
    AppState --> NodeMgr
    AppState --> ETAMgr
    AppState --> StorageMgr
    AppState --> WalletMgr
    AppState --> HashTracker

    NodeMgr -->|Spawns / Supervises| Knots
    WalletMgr -->|Descriptor RPC| RPCClient
    NodeMgr -->|JSON-RPC Loopback| RPCClient
    RPCClient -->|127.0.0.1:8332| Knots
```

---

## 2. Storage Modes: Compact Pruned vs. Full-History Archival

Sentinel Node Wallet implements a two-tier storage model tailored for constrained Apple Silicon laptops:

### A. Compact Pruned Mode (Default)
- **Settings:** `prune=550` and `pruneduringinit=550` written directly to `bitcoin.conf`.
- **Block Retention:** Keeps only the latest 550 MiB of raw block and undo files.
- **Node Validation:** Full validation from genesis block; every transaction and script is validated locally before pruning older blocks.
- **Safety Thresholds:**
  - Alert triggered when total datadir reaches 35 GB.
  - Automatic graceful shutdown triggered if datadir reaches 40 GB or host volume free space falls below 10 GB.

### B. Full-History / Archival Mode (Opt-in)
- **Settings:** `prune=0` (all block data retained).
- **Disk Requirement:** Requires ~800+ GB of storage.
- **Host Protection:** Strictly prohibited on the internal macOS startup disk (<50 GB free).
- **External Volume Preflight:** Only enabled after operator selects an external drive verified to have $\ge 1$ TB of free capacity.
- **Conversion Policy:** Transitioning from Compact to Archival requires full historical re-download and re-indexing (`-reindex`).

---

## 3. Adaptive Verification Progress ETA Engine

The verification time-remaining estimator continuously monitors initial block download (IBD) progress:

1. **Sampling:** Collects rolling progress timestamps `(t, verificationprogress, height)`.
2. **Warmup & Smoothing:** Requires at least 3 samples and 30 seconds warmup before emitting estimates to filter out startup bursts.
3. **Throughput Calculation:**
   $$\text{Rate} = \frac{\Delta \text{progress}}{\Delta t}$$
   $$\text{Time Remaining} = \frac{1.0 - \text{current\_progress}}{\text{Rate}}$$
4. **Auto-Scaled Formatting:**
   - $\ge 2$ weeks: `~2w 3d`
   - $1$ to $13$ days: `~3d 7h`
   - $1$ to $23$ hours: `~5h 24m`
   - $1$ to $59$ minutes: `~18m 42s`
   - $< 60$ seconds: `~47s`
5. **State Awareness:** Reports `Calibrating...`, `Estimating`, `Waiting for peers`, `Stalled` (if 180s without progress), or `Synchronized`.

---

## 4. BIP-110 / BLAKE2b Consensus Verification

- **Hard Fork Height:** 961,640
- **Activation Checkpoint Hash:** `0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb`
- **GBT Rules:** `["segwit", "blake2b"]`
- **Strict Network:** MainNet only. Legacy SHA-256d blocks past the fork height fail validation closed.
