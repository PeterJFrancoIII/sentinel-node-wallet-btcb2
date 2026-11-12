# Minimal Consensus Security — Default Node Policy (v10)

> **Current status:** [Built / In progress / Left](PROJECT_STATUS.md) (2026-11-09). This document is a detailed historical specification or agent receipt, **not** independent production acceptance. Public distribution and real funds: **NO-GO**.

**Project:** Sentinel Node Wallet - BTCB2  
**Product:** One native macOS app, one managed verified Knots BTCB2 BLAKE2b MainNet daemon, three tabs, no DATUM, no archival default.  
**Status:** Proposed source changes for Mac testing; not a production-approved release.

## What contributes to consensus security?

1. **Independent validation:** The node applies fork-correct consensus rules, rejects invalid blocks, keeps the UTXO set, and verifies the BTCB2 branch at height 961,640 (`0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb`). Verify a later trusted anchor and a fresh tip. It does not cast consensus votes and does not add mining hashrate.
2. **P2P diversity and relay:** Maintain automatically selected outbound full-relay and block-relay-only peers. Relay valid blocks, transactions and addresses, advertise `NODE_NETWORK_LIMITED` when pruned; do not use `blocksonly=1` or forced single-peer `connect`. More peers alone do not add proof-of-work security.
3. **Useful inbound service:** `listen=1` permits inbound P2P on port 8333 **when reachable**, but router and firewall exposure must be authorized. Explicitly disable `natpmp=0` and `upnp=0` to prevent automatic port mappings. RPC on 8332 remains loopback-only.
4. **Reliable operation:** Reasonable RAM/threads, modest bandwidth, no IBD resets, peer diversity, safe restarts, truthful live status and reviewed MainNet-specific Knots updates. A sleeping laptop cannot promise 24/7 service; do not defeat sleep or drain battery without consent.

A *pruned validating node is fully validating*, but is not a *full-history archival node*. The latter retains all historical blockfiles. BIP 159 defines pruned `NODE_NETWORK_LIMITED` peers guaranteeing at least 288 recent blocks. Wallets restored from previously pruned history may need guided re-download.

## Proposed new-install defaults

| Option | Quiet | Balanced — **new default** | Fast |
| --- | ---: | ---: | ---: |
| Script verification threads (`par`) | 1 | 2 | 4 |
| UTXO database cache (`dbcache` MiB) | 256 | 512 | 1024 |
| Max peer capacity (`maxconnections`) | 16 | 24 | 32 |
| Historical upload threshold (`maxuploadtarget` MiB/24h) | 256 | 512 | 1024 |
| Block retention AFTER IBD (`prune` MiB) | User choice | **2048** | User choice |
| Block retention DURING IBD (`pruneduringinit` MiB) | 550 | 550 | 550 |

**Storage is independent of sync profile.** Switching Quiet/Balanced/Fast MUST NOT change persisted 550/1024/2048/4096/custom pruning. Legacy users' `bitcoin.conf` prune targets must survive upgrades. An existing archive (`prune=0` or no explicit prune) must not silently convert to pruned. 2048 MiB gives modest recent-block headroom, **not** stronger consensus checks; `prune=550` remains user selectable. The raw blockfile limit is not the entire datadir: retain 35 GiB warning and 40 GiB/10–12 GiB free safety-stop thresholds; indexes off.

`maxconnections` is a ceiling, not a target. The outbound baseline is approximately eight full-relay, two block-relay-only and sometimes one feeler. 10–11 actual connections is normal across all modes when inbound connections are unavailable. Increasing maxconnections reserves inbound capacity; it does not create peers. Show connected total, inbound, outbound, cap and actual-applied profile in the Node view.

`maxuploadtarget` is a historical-block upload threshold, not a hard total bandwidth ceiling. Recent blocks and transaction relay can still exceed it.

## Minimal new-install Balanced configuration intent

~~~ini
# BTCB2 BLAKE2b MainNet (verified Knots binary)
server=1
listen=1
natpmp=0
upnp=0
blocksonly=0
v2transport=1
rest=0
par=2
dbcache=512
maxconnections=24
maxuploadtarget=512
prune=2048
pruneduringinit=550

[main]
port=8333
rpcport=8332
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
~~~

Maintain existing RPC-credential compatibility; migration to cookie auth is a separate tested change. Do not open public RPC, pin a lone outbound peer, provision a gateway, enable mining, or bypass transaction safety gates.

## Verification / release gates

- On actual Mac check app-owned PID, args, datadir, config, peer types, RPC readiness, block tip continuity, BLAKE2b fork hash, Keychain and current prune.
- New-install Balanced must use 2048 after sync and 550 during IBD. Existing 550, custom 4096, archive prune=0 and legacy no-prune configs must not be silently changed.
- All three profiles, app relaunch and adopted-daemon edge cases: verify runtime cache/threads and gracefully restarted process, not just GUI highlights. Peer count may remain 10–11 in every profile.
- Check `getblockchaininfo` pruned/IBD, `getnetworkinfo` inbound/outbound, `getpeerinfo` connection types and limited-service flags. Confirm 8333 inbound is only available with explicit network permission and no automatic port mapping.
- Benchmark peak datadir, RSS/CPU, network traffic and battery. Update README and tests. Report full git SHA, developer-only DMG SHA if built, and PASS/FAIL/NOT RUN.
- Preserve P0 Keychain -34018, encrypted wallet creation/recovery, signed/notarized releases and replay-safe send as independent blocking gates. Node tuning does not fix wallet security.

**References:** [BIP 159](https://github.com/bitcoin/bips/blob/master/bip-0159.mediawiki), [Bitcoin developer P2P](https://developer.bitcoin.org/devguide/p2p_network.html), [Knots bitcoin.conf](https://sources.debian.org/src/bitcoin-knots/29.4.knots20260508.2-1~bpo13%2B1/share/examples/bitcoin.conf), [BTCB2 fork anchors](https://bitcoinbip110.org/technicals/).
