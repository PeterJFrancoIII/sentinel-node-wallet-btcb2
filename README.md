# Sentinel Node Wallet — BTCB2

**Latest GitHub release:** [v1.0.0 (Build 8)](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build8) · **macOS:** 13+ on Apple Silicon · **BTCB2:** BLAKE2b / BIP-110 MainNet.

Sentinel Node Wallet is an independent SwiftUI macOS application that bundles a local Bitcoin Knots daemon and provides node operations, encrypted-descriptor wallet management and locally calculated blockchain network analytics. The project is **not** an exchange, mining program, cloud wallet or part of any other operational system.

| Identity / release | Current record |
|---|---|
| GitHub release tag | `v1.0.0-build8` (published `2026-11-26T00:21:45Z`) |
| Approved candidate source commit | [`bfc314c7`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/commit/bfc314c7ea7f352784cc0421ab0a7a815099cfc6) |
| Installer asset | [`Sentinel-Node-Wallet-BTCB2-v1.0.0-build8-macOS-arm64-notarized.dmg`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build8/Sentinel-Node-Wallet-BTCB2-v1.0.0-build8-macOS-arm64-notarized.dmg) (`14,197,833` bytes) |
| DMG SHA-256 | `449323dce965e1ae35a539d3e655a397f6a2b12f6df25421dd765c7510646119` |
| App Store Connect record | [App ID `6833290684`](https://appstoreconnect.apple.com/apps/6833290684/distribution/macos/version/inflight) |
| Current macOS bundle identifier in release scripts | `pool.sentineldefensetechnologies.co.za` |
| Version / build in published DMG | `1.0.0 (8)` |
| Pin in build scripts | Bitcoin Knots `29.4.3.knots20260508` |
| CI & Phase C feed verification | [PR #41 CI #45564463622](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45564463622) — **339 executed, 338 passed, 0 failed, 1 skipped** · [Phase C #45736669756](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45736669756) **SUCCESS** (`dist/appcast.xml` SHA-256 `90eaebe859c413648f60f50ca8d6ad0479f0410e3e504a3d8db525231a597f83`) |

> **Release qualification:** `v1.0.0-build8` is Developer ID signed (`S8QMQZA656`), hardened runtime, embedded provisioning profile (`043f266e...`), Apple notarized and ticket-stapled, with Sparkle EdDSA signature verification and Phase C live feed verification complete. However, the interactive Keychain `.userPresence` XCTest remains skipped in hosted CI, full clean-Mac post-enrollment wallet/Keychain GUI acceptance is not complete, and independent BTCB2 real-funds signing audit remains **OPEN**. Consult [Project Status](docs/PROJECT_STATUS.md), [Security](SECURITY.md) and [Test Matrix](TEST_AND_RELEASE_MATRIX.md) before trusting the app with funds. Previous releases `v1.0.0-build6` (missing embedded profile) and `v1.0.0-build7` (clean-Mac enrollment failure `missingRegistryInEstablishedNode`) are suppressed in `dist/appcast.xml`; upgrade directly to `v1.0.0-build8` without resetting existing data.

## Install or upgrade to Build 8

1. Open the [Build 8 release](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build8) and download `Sentinel-Node-Wallet-BTCB2-v1.0.0-build8-macOS-arm64-notarized.dmg` (or use `Sentinel Node Wallet > Check for Updates…` from Build 7+; close Settings/modal sheets before clicking `Install and Relaunch`, because Build 7/Build 8 shipping builds encounter AppKit `App termination blocked by modal sheet` if Settings remains open—if Sparkle finished staging/installing after the node stopped, quitting and reopening the app completes the swap safely).
2. Verify its SHA-256 against `449323dce965e1ae35a539d3e655a397f6a2b12f6df25421dd765c7510646119` and `SHA256SUMS.txt`: `shasum -a 256 Sentinel-Node-Wallet-BTCB2-v1.0.0-build8-macOS-arm64-notarized.dmg`.
3. Mount the DMG and drag **Sentinel Node Wallet.app** to **Applications** (replacing only the `.app` bundle; existing data in `~/Library/Application Support/NodePocketBTCB2` is preserved).
4. Review the installed app's macOS signature and Gatekeeper decision before running (`spctl --assess --type exec -vv "/Applications/Sentinel Node Wallet.app"`). Do **not** bypass OS security warnings.
5. For untested workflows, use a **disposable, zero-funds wallet** until the pending native Keychain/GUI acceptance and BTCB2 signing audits are completed.

The downloadable `BUILD_MANIFEST.json` and `SHA256SUMS.txt` on the release page are separate artifacts. Verify their contents against the installer you actually download; GitHub's published digest establishes file-integrity metadata, not source-to-binary reproducibility or financial safety.

## Functionality in current source

- **Node:** Embedded `bitcoind` and `bitcoin-cli`; start/stop and live sync progress; RPC bound to `127.0.0.1:8332`; peer and block-height indicators; optional, operator-controlled incoming P2P (normally port 8333).
- **Storage:** Pruning defaults to **2,048 MiB of retained block files** on new installations, with a **550 MiB minimum** and `pruneduringinit=550`; optional archival history on qualifying external storage. The prune target does **not** cap total node disk usage or indicate the full amount needed for validation.
- **Profiles:** Quiet, Balanced and Fast selectable; Ultra battery policy applies separate power-saving overrides. Customized profile settings are persisted. Defaults are documented below, not universal fixed running metrics.
- **Wallet:** Local encrypted descriptor wallets, multiple operator accounts with ownership isolation, receiving addresses and QR codes, history, balances, maturity reporting, backups, restore workflows and nondestructive Archive.
- **Authentication:** Local usernames/passwords, TOTP and recovery mechanisms, Keychain hooks, Touch ID or system password prompts for supported protected interactions. These features still require acceptance on each actual signed distribution build.
- **Network:** Local-consensus hashrate/difficulty estimates, rolling 30-block dot plot and dual-EMA/MACD chart; optional public **read-only ticker** queries to Neoxa and NonKYC for estimated fiat values. The app does **not** place exchange trades.
- **Uninstall:** An explicitly destructive **Full Uninstallation** UI and separate `scripts/clean_uninstall.sh` exist. They can remove blockchain data **and local wallet databases**. This is **not** the same operation as nondestructive wallet Archive or currently blocked individual-wallet Delete; see below.

### Default resource profiles

| Profile | Verification threads | Cache | Connection cap | Notes |
|---|---:|---:|---:|---|
| Quiet | 1 | 128 MiB | 3 | Lower-priority work |
| Balanced | 2 | 256 MiB | 8 | Default for a new installation |
| Fast | 4 | 1,024 MiB | 24 | Faster validation on AC |
| Ultra (battery) | 1 | 128 MiB | 4 | Automatic override; inbound listening off |

A connection cap is not a guaranteed count of connected peers. Existing configuration, custom settings and runtime override logic can alter effective behavior.

## Wallet and uninstall safety

**On-chain spending is not independently certified.** The current RPC implementation defaults `isBroadcastRestricted=true` and denies send/sign/broadcast/RBF methods while that flag is active. WalletManager also checks this flag; code contains paths that can transact if that restriction is disabled. **No independent BIP-110/BLAKE2b SIGHASH_UNIFIED signing audit is recorded here. Do not use real funds or deliberately disable that restriction.**

**Individual-wallet Delete remains hard-disabled in current source** pending independently verified isolated encrypted backup→restore; use **Archive** instead. **Full Uninstallation is different:** the app and CLI include broad deletion routines that may erase the node data directory, wallets and other local information without independently proving recoverability. **Back up and actually verify recovery off-device before using any uninstall/wipe function.** Do not assume the tool leaves zero residual files or can safely distinguish a wallet you wish to keep. Never execute `scripts/clean_uninstall.sh` merely as a development cleanup.

## Build, test, and contribute

- Swift Package Manager project: `Package.swift`; targets `NodePocketApp`, `NodePocketCore`, `NodePocketCoreTests`. Build with `swift build -c release --arch arm64`; test with `swift test` on a suitable macOS host.
- `scripts/build_app.sh`: local application bundle; `scripts/build_dmg.sh`: local drag-to-Applications DMG. **Neither alone is proof of Developer ID signing/notarization.**
- `scripts/package_appstore_archive.sh`: constructs an App Store candidate archive using Swift build and Apple Development signing in the checked-in script; separate Apple distribution/upload processing is **not** verified by hosted CI.
- Hosted CI tests and builds, but does not perform the interactive Keychain test, signed-app GUI wallet recovery, real-funds signing, or independent external audit.
- For exact roles, release gates and required evidence, see [GOVERNANCE](GOVERNANCE.md), [AGENTS](AGENTS.md), [SECURITY](SECURITY.md), [CONTRIBUTING](CONTRIBUTING.md), [Release Matrix](TEST_AND_RELEASE_MATRIX.md) and [Current Status](docs/PROJECT_STATUS.md). Older v7–v14 specifications remain historical references, not current release instructions.

## Support, privacy and attribution

[Issues and support](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues) · [Privacy policy](docs/PRIVACY.md) · [Architecture](docs/ARCHITECTURE.md) · [License and attribution](NOTICE.md).

**Privacy caveat:** Blockchain peers and public market-data providers can observe normal network metadata including IP address. Wallet records are local by design; do not mistake that for a claim that all networking is private or that local device compromise cannot affect a hot wallet.
