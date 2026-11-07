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
- **Settings:** new-install `prune=2048` with `pruneduringinit=550` MiB; users can choose any >=550 MiB and legacy settings must not be overwritten.
- **Block Retention:** New installations retain ~2 GiB raw block/undo files post-sync, and the 550 MiB minimum during initial sync; this is not total disk usage.
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

## Rolling block-history observability (v11)

Existing Storage Footprint card opens Advanced and provides live `pruneheight`-to-tip block time coverage. The selected pruning size previews a bounded projection using `getblockchaininfo.size_on_disk` and `prune_target_size`, not assumptions about the entire historical blockchain's density. Recalculate on every UI selection from cached sample, poll local headers at most every 120 seconds, and use logical year/month/week/day/hour units. Suppress misleading projection while IBD or when the buffer has not reached steady state. See [v11 rolling coverage](ROLLING_HISTORY_COVERAGE_V11.md).

## 4. BIP-110 / BLAKE2b Consensus Verification

See [Minimal Consensus Security v10](MINIMAL_CONSENSUS_SECURITY_V10.md). A pruned node fully validates consensus and advertises limited block serving (BIP 159); archival retention is not required for independent verification. Node defaults permit normal outbound block/transaction relay and user-approved inbound P2P, but disable implicit NAT-PMP/UPnP router changes. New installs default to Balanced (2 threads, 512 MiB cache, 24 connection cap), while Quiet/Fast change resource limits only and retain the user's pruning choice.


- **Hard Fork Height:** 961,640
- **Activation Checkpoint Hash:** `0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb`
- **GBT Rules:** `["segwit", "blake2b"]`
- **Strict Network:** MainNet only. Legacy SHA-256d blocks past the fork height fail validation closed.
