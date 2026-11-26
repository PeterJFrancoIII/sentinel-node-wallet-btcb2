# Test and Release Matrix — Sentinel Node Wallet BTCB2

**Snapshot:** November 25, 2026 (America/New_York). [GitHub v1.0.0 Build 8](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build8) publicly published (`2026-11-26T00:21:45Z`), approved candidate commit `bfc314c7ea7f352784cc0421ab0a7a815099cfc6`; exact-[SHA CI #45564463622](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45564463622) **SUCCESS: 339 executed / 338 passed / 0 failed / 1 skipped**; [Phase C #45736669756](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45736669756) **SUCCESS** (`dist/appcast.xml` SHA-256 `90eaebe859c413648f60f50ca8d6ad0479f0410e3e504a3d8db525231a597f83`). No independent real-funds certification.

**Evidence taxonomy:** SOURCE = current source behavior; CI = automated checkout/test; RELEASE = publicly available GitHub artifact; PEER = agent-reported host/Apple claims; NATIVE = independently captured signed-app result; OPEN = unproven or failing. A skipped test is not a pass.

| Capability / gate | Evidence at Build 8 source baseline (`bfc314c7`) | Status |
|---|---|---|
| Native SwiftUI Node / Wallet / Network + Advanced | Source present; optimized Release CI compile | **SOURCE + CI PASS** |
| Embedded Bitcoin Knots 29.4.3 and BTCB2 anchors | Pinned source/archive verification; isolated CLI regtest | **SOURCE + CI PASS**, signed binary provenance independent review **OPEN** |
| RPC listener and P2P | `server=1`, loopback `rpcbind=127.0.0.1`, configurable `listen=0/1`; packaging includes server/client sandbox entitlements | SOURCE; signed sandboxed runtime **OPEN** |
| Sync profiles | Quiet 1/128/3, Balanced 2/256/8, Fast 4/1024/24; Ultra battery 1/128/4 (threads/cache MiB/peer cap) | SOURCE; all real mode transitions **OPEN** |
| Pruned / archival storage | New default 2,048 MiB prune, minimum 550 MiB, optional external archival; existing selections preserved | SOURCE; storage migration QA **OPEN** |
| 30-block hash rate / dual-EMA MACD charts | HashrateTracker, MACDCalculator, SwiftUI views and unit tests | SOURCE + CI PASS; real runtime chart acceptance **OPEN** |
| Local operator authorization / wallet ownership | Multi-operator auth, TOTP, local Keychain, step-up, ownership isolation | SOURCE + CI; signed Mac human-interaction QA **OPEN** |
| Encrypted descriptor wallet create, inventory, receive, history | WalletManager/WalletView and test coverage | SOURCE + CI; shipping-app GUI with real encrypted restore **OPEN** |
| Wallet backup and isolated restore | Actual temporary Knots regtest CLI backup→restore completed in CI | **CI PASS (test-only)**; GUI/destructive restore authorization **OPEN** |
| Individual-wallet destructive Delete | Current `WalletInventory` unconditionally rejects after backup-header checks, absent isolated restore proof | **SOURCE HOLD**; do not enable without acceptance |
| Full Uninstallation / wipe | AppState and standalone script can broadly remove local data, including wallets | **SOURCE EXISTS; P0 SAFE-UNINSTALL REVIEW OPEN** |
| Outbound Send/RBF | RPC defaults broadcast restricted; conditional manager guards; alternate paths exist when deliberately unrestricted | **RESTRICTED BY DEFAULT; independent fork signing P0 OPEN** |
| Apple Passwords / Touch ID / Keychain | Source hooks; hosted interactive Keychain XCTest skipped | SOURCE + partial CI; **NATIVE P0 OPEN** |
| Optional Neoxa/NonKYC ticker | Read-only GET endpoints in price service; network metadata exposure documented | SOURCE; live network privacy/availability **OPEN** |
| GitHub macOS DMG & Signed Sparkle Feed | Build 8 (`v1.0.0-build8`) DMG `14,197,833` bytes (`449323dce965e1ae35a539d3e655a397f6a2b12f6df25421dd765c7510646119`), `S8QMQZA656` Developer ID notarized/stapled, CryptoKit EdDSA + Phase C feed verified; Build 7->8 OTA upgraded after `22:08 EST` app quit following earlier `21:29 EST` AppKit `App termination blocked by modal sheet` block when Settings sheet remained open | **RELEASE + NOTARIZATION + FEED VERIFIED; OTA MODAL-SHEET RELAUNCH CAVEAT** (close Settings/modal sheets before OTA install; sheet-dismissal fix staged on PR branch for next candidate; post-enrollment GUI **OPEN**) |
| App Store Connect | App ID 6833290684, active script bundle `pool.sentineldefensetechnologies.co.za`, v1.0 Build3 | SOURCE/peer report; **Apple final approval NOT independently verified** |
| Full signed/native security and financial release | No independent BTCB2 signing, GUI restore, interactive Keychain and notarization acceptance packet | **NO FUNDS/SECURITY GO** |

**Current CI evidence:** [PR #41 CI #45564463622](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45564463622) at `bfc314c7` executed 339 XCTests with 338 passing, 0 failing, and 1 interactive Keychain skip, plus release broadcast-lock verification and isolated Knots CLI encrypted recovery. Do not omit the skipped interactive Keychain test when reporting counts.

**Required closeout:** verify DMG file bytes/checksum and final code signature + Gatekeeper, independently test installed signed SwiftUI GUI, confirm wallet recovery and all destructive flows, commission an independent fork-signing audit, and prove current Apple disposition by authenticated first-party record. All test work must use disposable zero-funds datadirs.

[Project Status](docs/PROJECT_STATUS.md) · [Security](SECURITY.md) · [Governance](GOVERNANCE.md) · [Release Checklist](docs/PRODUCTION_RELEASE_CHECKLIST.md)
