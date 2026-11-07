# Rolling Historical Ledger Coverage — v11

**Product:** Sentinel Node Wallet - BTCB2 (MainNet only)  
**Surface:** Node → **Storage Footprint** → existing Advanced Storage picker. No additional tab, service, daemon, index or archive required.  
**Status:** Draft Swift implementation and tests. Live Mac/Knots verification is still required.

## The user experience

The existing Storage Footprint card becomes clickable. It shows the chosen blockfile budget and a compact live-derived retained-history age, e.g. `2 GiB · ~1 week, 3 days retained`. Selecting it opens the same Advanced settings sheet, where the user sees:

- **Actually retained now:** computed from verified local `getblockchaininfo.pruneheight` to the current validated tip and their header timestamps, plus the corresponding block count and IBD qualifier.
- **At selected budget:** a forecast that recomputes instantly when the user selects 550 MiB, 1 GiB, 2 GiB, 4 GiB or enters a valid custom MiB value, using observed retained block/undo bytes per historical time span. This preview never changes node settings until **Apply**.
- **Automatic units:** two most meaningful units: years/months, months/weeks, weeks/days, days/hours, or hours. Examples: `~2 years, 1 month`, `~3 months, 2 weeks`, `~2 weeks, 3 days`, `~3 days, 7 hours`, `~8 hours`. Duration less than one hour displays `<1 hour`. Average Gregorian month/year lengths are used for forecast duration units, not calendar promises.
- **Calibration states:** While initial block download runs, the node has not pruned any files, the RPC lacks trustworthy byte data, the selected target is below 550 MiB, the chain is reorganizing or Knots is disconnected, say `Calibrating`/`Awaiting initial pruning`/`Waiting for verified retention data`. Show actual retained coverage **at current sync height** during IBD if the first retained boundary is valid, but suppress a false future live-tip forecast until sync has settled.
- **Interpretation:** Label as *Rolling historical blocks on disk*, NOT financial insurance, uninterrupted archival access, consensus voting power, wallet-backup replacement, or guaranteed deep-reorganization support. A pruned node still validates every consensus rule; old blocks outside the retained window cannot be served or rescanned without redownload.

## Live local data, no new external connectors

Read only local Bitcoin Knots RPC:

1. `getblockchaininfo` yields `blocks`, `bestblockhash`, `initialblockdownload`, `pruned`, `pruneheight`, `size_on_disk` and `prune_target_size`. The byte and target fields represent raw block/undo files (NOT total chainstate, log, wallet, or APFS usage). The first retained height represents the earliest continuously retained block (the block after the last pruned height, per RPC version).
2. `getblockhash(pruneheight)` then `getblockheader` for first retained and current validated tip. Timestamp difference yields **observed historical time span**; block heights yield observed block count. Block timestamps are consensus-limited but not exact wall-clock timestamps, so the output is marked approximate.
3. When fully synchronized, pruning has happened and the recorded block/undo bytes are reasonably near the effective prune target (ratio 0.45–2.0), derive an estimated byte density `recordedBytes / observedSeconds`. Forecast a new target's rolling window from `requested MiB * 1,048,576 / observedBytes * observedSeconds`, with a conservative 288-block minimum window based on observed average seconds/block. This is only an estimate; block weight/undo size, pruning granularity, reorgs and rate changes materially change the actual window.
4. Re-sample at most once every **120 seconds**. All slider/text edits recalculate forecasts **from the latest sample in memory**, with zero additional RPC calls per keystroke. Use Knots' own node data, never pool/explorer APIs, and do not scan old block files or demand txindex/blockfilterindex.

## Safety, migration and test gates

- New installs remain pruned Balanced, new default 2 GiB post-IBD and 550 MiB during IBD; user still can select 550 MiB minimum or custom. **Existing** 550/custom/archive storage choices remain unchanged.
- Preserve active syncing, Keychain wallets, previous bitcoin.conf, and optional external archive. The UI forecast does not call `pruneblockchain` or change disk data; only the existing authenticated Apply path can request a safe graceful restart.
- Mock RPC tests cover missing/zero pruneheight, old unpruned chains, IBD, stalled nodes, malformed timestamps, negative span, unavailable byte fields, sampling behavior and reasonable sample bounds; unit formatter tests cover all year/month/week/day/hour boundaries and forecasts for 550/1024/2048/4096 MiB. Each predicted estimate must be explicitly prefixed with `~`.
- Real Mac tests compare actual oldest stored block and tip header timestamps to UI, observe actual Knots prune cycles over time, compare selected custom budget and later measured coverage, prove no new HTTP calls, no extra services, low CPU/RAM usage, unchanged wallet and chain height. Benchmarks cannot establish precise future coverage when the network changes.
- Unresolved Keychain -34018, encrypted wallet creation/import, BLAKE2b replay-safe spending, Apple notarization and signed update gates remain release blockers. This v11 change does **not** resolve them.

**Primary documentation:** [Bitcoin Core 29 `getblockchaininfo` RPC](https://bitcoincore.org/en/doc/29.0.0/rpc/blockchain/getblockchaininfo/), [Knots 29.4 example bitcoin.conf](https://sources.debian.org/src/bitcoin-knots/29.4.knots20260508.2-1~bpo13%2B1/share/examples/bitcoin.conf), [BIP 159](https://github.com/bitcoin/bips/blob/master/bip-0159.mediawiki).
