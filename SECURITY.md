# Security Policy — Sentinel Node Wallet BTCB2

**Release presence is not security certification.** The [v1.0.0 Build 3 macOS DMG](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) is published. However, independent BTCB2 transaction-signing, signed native credential/user-presence tests, GUI backup→restore and Developer ID notarization/Gatekeeper verification have not been established in this public audit record. **Do not entrust real funds to the build on the basis of GitHub publication or CI alone.**

Report vulnerabilities privately through GitHub's security-advisory reporting mechanism when available, or through an authenticated maintainer channel. Do not publish seeds, private keys, passwords, TOTP values, wallet backups, RPC cookies, exploit details or personal user data in public issues.

## Protected boundaries

- Local-only authenticated node RPC at `127.0.0.1:8332`; optional P2P inbound port 8333 is user controlled. Blockchain peers and price-query providers still see network metadata such as IP addresses.
- BTCB2 BLAKE2b/BIP-110 MainNet anchor checks; pinned Bitcoin Knots `29.4.3.knots20260508` built from a SHA-verified pinned archive. Verify upstream publisher signatures and provenance independently before changing the pinned executable.
- Multi-operator access and wallet ownership checks, encrypted descriptor wallet data, local password/TOTP/Keychain flows and protected user-presence interactions. Never claim a local Keychain item automatically equals Apple Passwords or Secure Enclave custody.
- User-owned datadir, wallet files, archives and Keychain credentials must not be used for automated regression tests.

## Outbound transaction risk

`BitcoinRPCClient` defaults to `isBroadcastRestricted=true` and hard-denies a list of send, signing and RBF RPC methods while restricted. `WalletManager` also checks this flag before executing send and fee bump. **Implementation still contains paths that can unlock and broadcast when that flag is disabled.** Independent BTCB2 BIP-110/SIGHASH_UNIFIED signature, change/fee, replay-resistance and recipient-binding approval is **OPEN**. Do not disable the restricted mode or execute funded sends without explicit independent security acceptance.

## Wallet deletion and full uninstall are different

- **Individual-wallet Delete:** `WalletInventory.deleteWalletFromMac` presently throws `restoreVerificationFailed` after validating the backup file, because it lacks an independently verified encrypted-wallet isolated restore. No ordinary Delete/Trash should proceed on this code path. Continue using nondestructive Archive.
- **Full Uninstallation:** `AppState.fullyUninstallApplicationAndAllFiles` and `scripts/clean_uninstall.sh` are broad data-erasure mechanisms, potentially including **wallet databases and blockchain state**. They are NOT a substitute for wallet deletion's recovery proof and should never be invoked as cleanup on a valued wallet. Neither “zero residual” nor successful destruction is a recovery guarantee. Recoverable off-device backups and explicit operator consent are mandatory.

## CI and artifact evidence

[Current main CI #43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) at baseline `31f888b`: **144 executed / 143 passed / 0 failed / 1 skipped** (interactive Keychain). It compiles SwiftUI Release, checks a development app bundle and runs an isolated Knots regtest encrypted backup→restore via CLI. This **does not** validate actual signed-app Keychain acceptance, a user's GUI restore or real-funds transfers.

The published Build 3 GitHub DMG asset has SHA-256 `892798a3a7bf4c50b4cf220d6ac3e4a0b071c8c8acc1d993da1d04212d01b114`. Current `scripts/build_dmg.sh` attempts signing with an **Apple Development** identity, not independently verified Developer ID/notarization. SHA-256 checks content integrity only. Obtain an authorized on-device `codesign`, Gatekeeper, notarization and source-to-binary supply-chain report before stating public macOS security acceptance.

## Outstanding release gates

1. Independent BTCB2 SIGHASH_UNIFIED/signing, PSBT, fee, replay and wallet-output audit; test on isolated zero-value contexts before any funded action.
2. Signed-app native Apple Passwords/Keychain/TOTP user-presence, denial/cancel and credential recovery tests, including the interactive CI-skipped test.
3. Complete installed GUI encrypted wallet creation→backup→restore, integrity/ownership/lock verification; safe handling of all destructive operations, including full uninstall.
4. Daemon PID/executable, signed embedded binaries, chain identity, RPC endpoint, P2P/sandbox behavior, data migration and disk safeguards.
5. Developer ID notarized DMG/Gatekeeper acceptance for outside-store distribution **or** separately accepted Mac App Store signing, privacy, review and eligibility; public artifact release does not imply either.

Use [Test Matrix](TEST_AND_RELEASE_MATRIX.md), [Project Status](docs/PROJECT_STATUS.md), [Governance](GOVERNANCE.md) and [Production Release Checklist](docs/PRODUCTION_RELEASE_CHECKLIST.md) for current evidence. Historical v13 audit documents are archived snapshots, not a current GO decision.
