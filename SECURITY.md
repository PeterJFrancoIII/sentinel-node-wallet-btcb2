# Security Policy — Sentinel Node Wallet BTCB2

**Release presence is not security certification.** The [v1.0.0 Build 8 macOS DMG](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build8) is Developer ID signed, Apple notarized/stapled, and published on the signed Sparkle feed (`dist/appcast.xml`). However, independent BTCB2 transaction-signing, signed native credential/user-presence tests, and full GUI backup→restore acceptance remain open in this public audit record. **Do not entrust real funds to the build on the basis of GitHub publication, notarization, or CI alone.**

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

[PR #41 CI #45564463622](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45564463622) at candidate `bfc314c7`: **339 executed / 338 passed / 0 failed / 1 skipped** (interactive Keychain). [Phase C #45736669756](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45736669756) verified live CDN `dist/appcast.xml` (`90eaebe859c413648f60f50ca8d6ad0479f0410e3e504a3d8db525231a597f83`). This **does not** validate full post-enrollment signed-app Keychain `.userPresence` acceptance, a user's GUI restore, or real-funds transfers.

The published Build 8 GitHub DMG asset has SHA-256 `449323dce965e1ae35a539d3e655a397f6a2b12f6df25421dd765c7510646119` (`14,197,833` bytes), Developer ID signing (`S8QMQZA656`), embedded provisioning profile (`043f266e...`), and stapled Apple notarization ticket. Direct local `scripts/build_dmg.sh` builds are unsandboxed/development-signed unless produced by the hardened Developer ID release workflow.

## Outstanding release gates

1. Independent BTCB2 SIGHASH_UNIFIED/signing, PSBT, fee, replay and wallet-output audit; test on isolated zero-value contexts before any funded action.
2. Signed-app native Apple Passwords/Keychain/TOTP user-presence, denial/cancel and credential recovery tests, including the interactive CI-skipped test.
3. Complete installed GUI encrypted wallet creation→backup→restore, integrity/ownership/lock verification; safe handling of all destructive operations, including full uninstall.
4. Daemon PID/executable, signed embedded binaries, chain identity, RPC endpoint, P2P/sandbox behavior, data migration and disk safeguards.
5. Developer ID notarized DMG/Gatekeeper acceptance for outside-store distribution **or** separately accepted Mac App Store signing, privacy, review and eligibility; public artifact release does not imply either.

Use [Test Matrix](TEST_AND_RELEASE_MATRIX.md), [Project Status](docs/PROJECT_STATUS.md), [Governance](GOVERNANCE.md) and [Production Release Checklist](docs/PRODUCTION_RELEASE_CHECKLIST.md) for current evidence. Historical v13 audit documents are archived snapshots, not a current GO decision.
