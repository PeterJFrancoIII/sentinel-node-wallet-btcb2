# Agent Instructions — Sentinel Node Wallet BTCB2

**Start with:** [Governance](GOVERNANCE.md) → [Current Status](docs/PROJECT_STATUS.md) → [Security](SECURITY.md) → [Release Matrix](TEST_AND_RELEASE_MATRIX.md). Historical v7–v14 design memos and handoffs must not override the current source or current guardrails.

## Canonical identity and release

- Project isolation key: `NODEPOCKET_BTCB2_ONLY`. A standalone SwiftUI/macOS BTCB2 BLAKE2b/BIP-110 MainNet wallet and embedded Bitcoin Knots node; Node/Wallet/Network/Advanced screens.
- Current code branch: `main`. [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) **merged**; do not treat old `fix/v13-1-security-remediation-20261107` handoffs as the working source.
- Latest published [GitHub v1.0.0 Build 3 DMG](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3), release-notes source `357766bf`, SHA-256 listed in README and GitHub release; current main baseline before this docs refresh `31f888b`. Never assume the release is notarized, approved by Apple or wallet-security-certified.
- Active bundle identifier `pool.sentineldefensetechnologies.co.za`, Apple app record `6833290684`, `1.0 (3)` in packaging scripts. Prior `app.nodepocket.btcb2` and `com.nodepocket.btcb2` are historical references.
- Built-in Bitcoin Knots `29.4.3.knots20260508`; block/node RPC localhost only, optional inbound P2P under operator control. Normal app is MainNet only; use separate temporary regtest datadirs for tests.

## Agent entry protocol

1. Read latest release/commits, GitHub CI and the actual active source before editing. For this snapshot, [CI #43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) on `31f888b` succeeded: **144 executed / 143 passed / 0 failed / 1 skipped** (device-interactive Keychain). It also completed release compile, ad-hoc bundle and isolated Knots CLI backup/restore. Those do not constitute acceptance of signed app, DMG or spending.
2. Search shared memory entity `Session_Gemini_NodePocketBTCB2_20261106-1741` and `InterAgent_Dialogue_Channel`; retain exact peer provenance, including dispatch `MSG:gemini-sentinel-v100-build3-github-dmg-release-121`. A failed connector lookup is not proof that the receipt does not exist.
3. Distinguish **SOURCE**, **CI**, **LOCAL PEER-REPORTED**, **INDEPENDENT NATIVE**, **PUBLIC DISTRIBUTION** and **APP STORE APPROVAL**. Report exact immutable SHAs, tests and unresolved acceptance.
4. Use a fresh, reviewed PR; run `swift test`, build/package scripts where authorized, `python3 tools/verify_governance.py` and `bash scripts/secret_scan.sh`; separate local runtime tests from CI. Never use a live wallet or production datadir as a test fixture.

## Active safety gates

- Generic BitcoinRPCClient defaults `isBroadcastRestricted=true`; WalletManager Send and RBF conditional guards depend on this flag. Any bypass/disabled restriction must be treated as **P0 unsafe for real funds** until independent fork-specific signing/fee/replay/recipient-binding audit and explicit owner approval.
- Individual-wallet Delete currently always rejects after validation because there is **no independently verified isolated restore proof**; do not replace this hard stop with file-header, checksum or backup-receipt checks alone. Archive is available.
- **Full Uninstallation is separate and destructive**: it attempts removal of node blockchain state and wallet files. Do not invoke or document it as a safe substitute for ordinary uninstall; require verified off-device recovery and explicit operator intent.
- Source Keychain, Touch ID, TOTP and Apple Passwords hooks are not proof of actual signed-app consent, entitlement or login behavior. Hosted CI skips the interactive Keychain case.
- Direct DMG `scripts/build_dmg.sh` may use Apple Development signing; its public GitHub release has no confirmed Developer ID notarization/Gatekeeper acceptance here. App Store archive `scripts/package_appstore_archive.sh` is a separate path with App Sandbox and development signing in checked-in script; actual cloud signing and App Store status need first-party receipts.
- Never expose private material, perform financial transactions, change Apple account configuration or touch unrelated software unless the operator explicitly authorizes it.

## Change / handoff standard

Submit source SHA and review branch, CI job/test counts (not “all passed” when skipped), provenance and actual signed-artifact checks, backup/restore proof, complete list of regressions, any Apple/privacy-policy drift and safe rollback. Prefer small audited patches. Keep [README](README.md), [Project Status](docs/PROJECT_STATUS.md), [Release Matrix](TEST_AND_RELEASE_MATRIX.md), [Security](SECURITY.md), [Privacy](docs/PRIVACY.md) and release notes consistent. Historical documents must be visibly labeled as such.

Current release artifact **exists**; independent financial and distribution-security certification remains **open**.
