# Distribution and Security Release Checklist — Sentinel Node Wallet BTCB2

**Updated November 14, 2026.** [GitHub v1.0.0 Build 3](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) is published with a macOS DMG, `BUILD_MANIFEST.json` and `SHA256SUMS.txt`. A downloadable artifact is **not** automatically a notarized, Gatekeeper-accepted or independently audited release. [Project Status](PROJECT_STATUS.md) provides the current evidence register.

## Public GitHub asset (confirmed)

- Asset: `Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg`; GitHub release asset reports **12,430,628 bytes** and SHA-256 `892798a3a7bf4c50b4cf220d6ac3e4a0b071c8c8acc1d993da1d04212d01b114`.
- Release notes identify source `357766bf8d5e219208148101dde5bc7c26f59b0e`; [CI #43663728634](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663728634) succeeded (144 executed / 143 passed / 1 skipped, zero failed), optimized release compile, development app packaging, and isolated regtest backup→restore.
- `scripts/build_dmg.sh` creates a drag-to-Applications DMG and **optionally signs it with an Apple Development identity**. Development signing is **not Developer ID distribution signing**. The GitHub release does not provide verifiable Apple notarization/Gatekeeper evidence in this record.
- Independent verification required: download exact bytes, run SHA-256, inspect attached manifest and signatures of `.dmg`, `.app`, `bitcoind` and `bitcoin-cli`, test on a clean authorized Apple Silicon Mac. If Gatekeeper rejects the asset, do not tell users to disable OS security.

## Independent release channels

### A. Outside Mac App Store (Developer ID)

For a public trustable outside-store DMG, use a properly authorized **Developer ID Application** identity, hardened runtime, correctly signed embedded binaries and notarization/stapling with Apple's notary service. `scripts/build_production_dmg.sh` provides a guarded candidate pipeline; do **not** assume it was used for the published Build 3 DMG. Prerequisites include:

- Owner-installed valid Developer ID certificate and local notarization credentials; never commit Apple keys or profiles.
- Owner-approved HTTPS associated-domain AASA matching actual team and **current** bundle `pool.sentineldefensetechnologies.co.za` if Apple Passwords is used. The old `app.nodepocket.btcb2` AASA in historical documentation is not the packaging identifier.
- Independent BTCB2 consensus/signing and complete native credential/backup acceptance; no live wallet testing.
- Final accepted notarization receipt, stapling validation, trusted Gatekeeper assessment and signed-file hash manifest. Public download only after approved release gates.

### B. Mac App Store

The current packaging source labels Apple app `6833290684`, bundle `pool.sentineldefensetechnologies.co.za`, version `1.0 (3)`. `scripts/package_appstore_archive.sh` packages a manually constructed `.xcarchive` signed using **Apple Development** in checked-in source. A separately performed cloud-managed **Apple Distribution** re-sign, processing receipt and Apple's review outcome require authenticated evidence. App Store Connect `WAITING_FOR_REVIEW` in historical agent reports is not approval and may no longer be current.

Check genuine App Sandbox entitlements (including the loopback RPC listener and optional P2P server function), child process and data-directory permissions, actual seller eligibility under cryptocurrency wallet rules, truthful privacy labels and review notes. Keep the outside-store and Mac App Store signing pipelines separate.

## Safety gates before real funds or destructive operations

- [ ] BTCB2 BIP-110/BLAKE2b SIGHASH_UNIFIED, PSBT/funded transaction, outputs, fees, RBF, replay and allowlist independently audited; do not disable default `isBroadcastRestricted=true` before explicit approval.
- [ ] Signed native app operator enrollment, Touch ID/system-password authorization, TOTP, denial/cancel, Keychain errors and credential recovery tested on authorized **isolated, zero-funds** Mac data.
- [ ] Actual encrypted-wallet creation→backup→fresh isolated restore→ownership/address verification→relock tested on shipping app. Individual-wallet Delete remains blocked until this proof exists.
- [ ] Full Uninstallation and CLI wipe's broad data-erasure paths reviewed for authorization, backup requirements, location safety and permission failures; never treat “zero residual” claim as proof.
- [ ] Pinned Knots publisher/signature verification, authenticated daemon PID/RPC/socket binding, network/sandbox, pruning and Ultra battery-mode acceptance.
- [ ] Checked release DMG SHA, signed binaries, Gatekeeper/notary receipt if claimed, App Store processing/approval where relevant, rollback and support instructions.
- [ ] Correct current Git SHA, test counts, separately sourced native PASS/FAIL/SKIPPED, owner approval and immutable artifacts attached to review.

## Verification commands — read-only on an authorized Mac

```bash
shasum -a 256 "Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg"
codesign --display --verbose=4 "/Applications/Sentinel Node Wallet.app"
codesign --verify --strict --deep --verbose=2 "/Applications/Sentinel Node Wallet.app"
spctl --assess --type execute --verbose=4 "/Applications/Sentinel Node Wallet.app"
xcrun stapler validate "/Applications/Sentinel Node Wallet.app"
```

These commands inspect the installed app; only run after verifying the install source. Failed trust checks are a **blocker**, not an instruction to bypass Gatekeeper.

**Decision:** Public GitHub artifact **YES**; real-funds, safe destructive workflow, independently accepted Apple distribution and trusted notarization **OPEN**.
