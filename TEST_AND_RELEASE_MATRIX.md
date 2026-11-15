# Test and Release Matrix — Sentinel Node Wallet BTCB2

**Snapshot:** November 14, 2026 (America/New_York). [GitHub v1.0.0 Build 3](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) publicly published; [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) **merged**. Current main before this docs update `31f888b`; exact-[SHA CI #43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) **SUCCESS: 144 executed / 143 passed / 0 failed / 1 skipped**. No independent real-funds or notarization certification.

**Evidence taxonomy:** SOURCE = current source behavior; CI = automated checkout/test; RELEASE = publicly available GitHub artifact; PEER = agent-reported host/Apple claims; NATIVE = independently captured signed-app result; OPEN = unproven or failing. A skipped test is not a pass.

| Capability / gate | Evidence at Build 3 source baseline | Status |
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
| GitHub macOS DMG | Build 3 release with DMG, SHA256SUMS.txt, BUILD_MANIFEST.json, published asset digest `892798a3...` | **RELEASE VERIFIED**; notarization/Gatekeeper/source-to-DMG independently **OPEN** |
| App Store Connect | App ID 6833290684, active script bundle `pool.sentineldefensetechnologies.co.za`, v1.0 Build3 | SOURCE/peer report; **Apple final approval NOT independently verified** |
| Full signed/native security and financial release | No independent BTCB2 signing, GUI restore, interactive Keychain and notarization acceptance packet | **NO FUNDS/SECURITY GO** |

**Current CI evidence:** [Build 3 source run #43663728634](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663728634) also succeeded at `357766bf`. GitHub logs for both runs show 144 XCTest executions with one interactive Keychain skip, and isolated Knots CLI encrypted recovery. Do not print “144 passed” for this run.

**Required closeout:** verify DMG file bytes/checksum and final code signature + Gatekeeper, independently test installed signed SwiftUI GUI, confirm wallet recovery and all destructive flows, commission an independent fork-signing audit, and prove current Apple disposition by authenticated first-party record. All test work must use disposable zero-funds datadirs.

[Project Status](docs/PROJECT_STATUS.md) · [Security](SECURITY.md) · [Governance](GOVERNANCE.md) · [Release Checklist](docs/PRODUCTION_RELEASE_CHECKLIST.md)
