# Distribution and Security Release Checklist — Sentinel Node Wallet BTCB2

**Updated November 25, 2026.** [GitHub v1.0.0 Build 8](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build8) is published (`2026-11-26T00:21:45Z`) with Developer ID notarized macOS arm64 DMG, `SHA256SUMS.txt`, `BUILD_MANIFEST.json`, `RELEASE_ATTESTATION.json`, and `SPARKLE_SIGNATURE.base64`, plus live signed Sparkle feed `dist/appcast.xml` verified by Phase C (`45736669756`). [Project Status](PROJECT_STATUS.md) provides the current evidence register.

## Public GitHub asset (confirmed)

- Asset: `Sentinel-Node-Wallet-BTCB2-v1.0.0-build8-macOS-arm64-notarized.dmg`; **14,197,833 bytes** and SHA-256 `449323dce965e1ae35a539d3e655a397f6a2b12f6df25421dd765c7510646119`.
- Approved candidate commit `bfc314c7ea7f352784cc0421ab0a7a815099cfc6`; [CI #45564463622](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/45564463622) succeeded (`339` executed / `338` passed / `1` skipped, zero failed), optimized release compile, and isolated regtest verification.
- Phase A (`45717133027`), Phase B (`45732601504`), and Phase C (`45736669756`) verified Developer ID signing (`S8QMQZA656`), embedded provisioning profile (`043f266e...`), Apple notarization/stapling, Swift `CryptoKit` Ed25519 signature, and live CDN `dist/appcast.xml` (`90eaebe859c413648f60f50ca8d6ad0479f0410e3e504a3d8db525231a597f83`, `1,576` bytes).
- Scheduled checks & operator-initiated Sparkle 2 updates (`Check for Updates…`) are served by `dist/appcast.xml`, while unattended background `autoDownload` remains intentionally disabled.
- Direct-DMG upgrades should preserve `~/Library/Application Support/NodePocketBTCB2` (do not advise destructive reset of existing data). If Gatekeeper rejects an unsigned or unprofiled asset, do not tell users to disable OS security.

## Independent release channels

### A. Outside Mac App Store (Developer ID)

For a public trustable outside-store DMG, the guarded release workflow (`release-macos.yml` + `scripts/build_production_dmg.sh`) uses a properly authorized **Developer ID Application** identity (`S8QMQZA656`), hardened runtime, embedded provisioning profile (`pool.sentineldefensetechnologies.co.za`), correctly signed embedded binaries, and notarization/stapling with Apple's notary service. Prerequisites include:

- Owner-provisioned Developer ID certificate, embedded provisioning profile (`043f266e...`), and App Store Connect API notarization credentials in protected GitHub Environments; never commit Apple keys or profiles.
- Owner-approved HTTPS associated-domain AASA matching team `S8QMQZA656` and bundle `pool.sentineldefensetechnologies.co.za`.
- Independent BTCB2 consensus/signing and complete native credential/backup acceptance; no live wallet testing.
- Final accepted notarization receipt, stapling validation, trusted Gatekeeper assessment, Sparkle EdDSA attestation, and Phase C live CDN verification of `dist/appcast.xml`.

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
