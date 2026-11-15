# Sentinel Node Wallet — BTCB2

**Latest GitHub release:** [v1.0.0 (Build 3)](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) · **macOS:** 13+ on Apple Silicon · **BTCB2:** BLAKE2b / BIP-110 MainNet.

Sentinel Node Wallet is an independent SwiftUI macOS application that bundles a local Bitcoin Knots daemon and provides node operations, encrypted-descriptor wallet management and locally calculated blockchain network analytics. The project is **not** an exchange, mining program, cloud wallet or part of any other operational system.

| Identity / release | Current record |
|---|---|
| GitHub release tag | `v1.0.0-build3` |
| Release source commit (identified in release notes) | [`838f119c`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/commit/838f119cd5a748313fe2e9cc537dbce0074bf8a7) |
| Installer asset | [`Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg`](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build3/Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg) |
| DMG SHA-256 from GitHub release asset metadata | `7b5adb42155cff6f18fd312778b9edfcf46987731927f79b7d057dac3bec9f3a` |
| App Store Connect record | [App ID `6833290684`](https://appstoreconnect.apple.com/apps/6833290684/distribution/macos/version/inflight) |
| Current macOS bundle identifier in release scripts | `pool.sentineldefensetechnologies.co.za` |
| Version / build in packaging scripts | `1.0 (3)` |
| Pin in build scripts | Bitcoin Knots `29.4.3.knots20260508` |
| CI for current main docs/source baseline | [#43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) — **144 executed, 143 passed, 0 failed, 1 skipped** |

> **Release qualification:** The DMG asset is publicly available on GitHub; that is **not** evidence of Apple Developer ID notarization, Gatekeeper acceptance, App Store approval or an independently audited BTCB2 wallet. The direct-DMG script attempts **Apple Development** signing when that identity is installed, not Developer ID signing/notarization. The interactive Keychain XCTest remains skipped in hosted CI. Consult [Project Status](docs/PROJECT_STATUS.md), [Security](SECURITY.md) and [Test Matrix](TEST_AND_RELEASE_MATRIX.md) before trusting the app with funds.

## Install the published DMG

1. Open the [Build 3 release](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) and download the DMG.
2. Verify its SHA-256 against the value above and the downloadable `SHA256SUMS.txt` release asset: `shasum -a 256 Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg`.
3. Mount the DMG and drag **Sentinel Node Wallet.app** to **Applications**.
4. Review the installed app's macOS signature and Gatekeeper decision before running. Do **not** assume a development-signed image is trusted or notarized; do not bypass security warnings merely to install.
5. On first launch, use a **disposable, zero-funds wallet** until the pending native acceptance and BTCB2 signing audits are completed.

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
