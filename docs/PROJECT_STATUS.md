# Sentinel Node Wallet BTCB2 — Current Project Status

**Snapshot:** November 14, 2026, America/New_York. **Single active status register.** Current public [GitHub v1.0.0 (Build 3) release](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3); previous [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) is **merged**, not open. Baseline `main` before this documentation review: `31f888b61f2fbf8bf0e1425b367f0783a23c0174`.

## Current milestone and independent evidence

| Item | Verified information | Qualification |
|---|---|---|
| GitHub release | Published `v1.0.0-build3` with macOS arm64 DMG, checksum file and JSON build manifest | **PUBLICLY AVAILABLE**; not automatically notarized |
| DMG | `Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg`, SHA-256 `892798a3a7bf4c50b4cf220d6ac3e4a0b071c8c8acc1d993da1d04212d01b114` from GitHub's asset metadata | Release asset metadata verified; installed artifact signature not independently verified |
| Release source | Release notes identify `357766bf8d5e219208148101dde5bc7c26f59b0e` | No independent source-to-DMG reproducibility report |
| GitHub Actions | [Current-main CI #43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) succeeded at `31f888b`. [Release-source CI #43663728634](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663728634) succeeded at `357766bf`. | Both report **144 executed / 143 passed / 0 failed / 1 skipped**, optimized Release compile, ad-hoc bundle and isolated Knots regtest recovery |
| App Store identity | Apple app `6833290684`, bundle `pool.sentineldefensetechnologies.co.za`, `1.0 (3)` as configured in current packaging scripts | Actual Apple review/approval state needs authenticated first-party verification |
| Embedded node | Bitcoin Knots `29.4.3.knots20260508` pinned in fetch/package scripts | Binary publisher/updated upstream audit remains separate |
| Build signing | GitHub DMG script optionally signs with **Apple Development** identity, while a separate Developer ID/notary script exists | No public record here proving Build 3 DMG Developer ID notarization or Gatekeeper acceptance |
| Shared memory | Operator references `MSG:gemini-sentinel-v100-build3-github-dmg-release-121` and `SentinelNodeWallet_BTCB2_v100_Build3_GitHub_Release_and_DMG_Deployment` | Agent dispatch is not an independent signed-package audit |

**Evidence labels:** **SOURCE** current code; **CI** automated tests on exact SHA; **RELEASE** publicly posted asset and metadata; **PEER** another agent's local or Apple portal report; **NATIVE** independently inspected signed installed app; **OPEN** missing/failed proof.

## Current implemented architecture and features

- **Standalone native app:** SwiftUI Node, Wallet and Network screens; Advanced sheet; Apple Silicon/macOS 13+.
- **Node control:** Bundled Knots executable, one-click local node startup or bypass, RPC restricted to `127.0.0.1`, syncing status/ETA, connected peers, chain identity and resource monitoring; optional user-approved incoming P2P.
- **Storage:** New-install default prune target 2,048 MiB, minimum 550 MiB, initial-sync pruning at 550 MiB, user-selected archival storage where supported; preserve pre-existing user settings. **Prune limits block files, not total disk use.**
- **Profiles:** Quiet **1 thread / 128 MiB / 3 peers**; Balanced **2 / 256 / 8**; Fast **4 / 1,024 / 24**; Ultra automatic battery **1 / 128 / 4, inbound off**. Customized options and actual effective caps may differ.
- **Wallet:** Local encrypted descriptor wallets, multi-operator ownership isolation, receiving/QR, balances, history and coinbase maturity, wallet backup/restore infrastructure, nondestructive Archive; source contains transaction preview, fee and RBF paths gated by broadcast-restricted mode.
- **Authorization:** Local username/password, TOTP and recovery codes; local Keychain and Touch ID/system-password hooks. Hosted CI **skips** device-interactive Keychain test; native user consent is not automatically established.
- **Network analytics:** 30-block local-consensus hashrate dot plot, fast/slow EMA and MACD, difficulty, block interval and network peers. Optional read-only price queries to Neoxa and NonKYC.
- **Uninstallation:** Full Uninstallation UI and `scripts/clean_uninstall.sh` can erase application data, wallets and blockchain state. **Individual-wallet Delete remains blocked** without independent isolated restore verification. The two workflows have different risk profiles.

## Current safety observations — source-backed, not promotional claims

1. **Send/sign/RBF:** `BitcoinRPCClient` has `isBroadcastRestricted=true` by default; both its generic RPC path and WalletManager guard outgoing calls when restricted. But the code retains send/RBF execution paths when restriction is disabled. Independent BTCB2 BLAKE2b/BIP-110 SIGHASH_UNIFIED transaction/fee/recipient/replay audit is not included in CI. **No real-funds acceptance.**
2. **Individual-wallet Delete:** `WalletInventory.deleteWalletFromMac` currently always throws `restoreVerificationFailed` after backup checks; no file Trash is executed on that normal Delete code path. Nondestructive Archive is an available alternative.
3. **Full-Uninstallation risk:** Separate AppState and CLI uninstaller may permanently erase the entire node datadir, including wallet files, and attempt deletion of the app bundle and sandbox container. These routines do **not** establish independent backup recoverability, may be interrupted by macOS sandbox restrictions, and must not be represented as guaranteed complete or lossless.
4. **Keychain:** App source contains Touch ID/system-password and Keychain/TOTP handling; 1 interactive XCTest is SKIPPED in hosted CI. Native Mac consent, failures and recovery must be separately validated on the actual signed binary.
5. **Networking and privacy:** Node RPC remains loopback; optional blockchain P2P and exchange-ticker HTTPS requests expose normal network metadata. Apple server entitlement supports a node RPC listener and user-enabled inbound P2P; the exact signed App Sandbox helper behavior must be proven.
6. **Distribution:** GitHub release file SHA is reported and can be verified after download. Build 3 notarization, third-party signature audits, accepted App Store build and Apple policy status are **not** verified by GitHub asset metadata.

## Open acceptance work

- Verify actual downloaded Build 3 DMG hash, embedded signed executables, hardened runtime, Developer ID signature/notary ticket if claimed, Gatekeeper and safe clean installation on an isolated Apple Silicon Mac.
- Audit the pinned Knots fork against publisher provenance and independently confirm BTCB2 signing rules, changes of signature hash, fees, RBF, safe replay handling and user-authorized recipients.
- Run real signed-app GUI encrypted wallet create→lock→backup→restore in a new isolated datadir, verify addresses/ownership and Keychain accept/cancel/denial. Do not test against user funds.
- Verify app runtime with network.client/network.server entitlements, local listening socket, actual P2P inbound opt-in, peer caps, Ultra power transitions, pruned storage under pressure and user-preserving migrations.
- Replace broad destructive uninstaller assumptions with permission-aware confirmation, isolated restoration proof, rollback/error handling and honest warnings. Treat irreversible wallet-state removal as a major separate security gate.
- Confirm Apple App Store Connect `6833290684` Build 3 processing/review status, account eligibility, App Privacy/marketing, entitlements, App Review feedback and actual release setting using first-party authenticated evidence.

## Governance / history

The [README](../README.md), [GOVERNANCE](../GOVERNANCE.md), [SECURITY](../SECURITY.md), [TEST AND RELEASE MATRIX](../TEST_AND_RELEASE_MATRIX.md) and [PRODUCTION RELEASE CHECKLIST](PRODUCTION_RELEASE_CHECKLIST.md) should agree with this status. Historic documents named `V7`, `V10`, `V11`, `V12`, `V13`, `V14`, and date-stamped incident/handoff receipts preserve their original context; they do **not** state current release status.

Use the canonical SCM session `Session_Gemini_NodePocketBTCB2_20261106-1741` and `InterAgent_Dialogue_Channel` with exact message provenance. Never share real wallet names, balances, keys, contacts or sensitive local host information in repo documentation.

**Current decision:** GitHub distribution **YES** (artifact exists); independent trusted/notarized distribution evidence **OPEN**; Apple approval **UNVERIFIED**; real-funds security **NOT CLEARED**.
