# Test and Release Matrix — Sentinel Node Wallet BTCB2

**Snapshot:** 2026-11-10 (EST); code **7bdfd0e**; [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) open/unmerged. [CI #42940525641](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42940525641): **133 executed / 132 passed / 0 failed / 1 skipped** (interactive Keychain). **No release authorization.**

**Evidence classes:** SOURCE = implemented, CI = automated tests, PEER = agent's unreproduced native claim, NATIVE = independently recorded on-device test, OPEN = missing/failed/insufficient. A skipped or conditional test is **not** NATIVE PASS.

| Gate | Current evidence | Decision |
|---|---|---|
| Three-tab app, sync/profile, Ultra=4/listen=0 | SOURCE + CI | Built; native transition OPEN |
| Multi-user local password/TOTP/recovery, step-up | SOURCE + CI | Built; real user-presence/2FA OPEN |
| Neoxa/NonKYC price quotes and override | SOURCE + tests | Built; live pricing/fallback OPEN |
| Wallet inventory, Archive, Delete, backup | SOURCE + CI: Archive active; **Trash/delete hard-disabled** at 2aa0e15 until isolated encrypted Knots recovery proof; prior ignored failed live restore removed | **SOURCE+CI PASS for NO-DELETE HOLD; recoverable deletion P0 OPEN** |
| Real Knots descriptor wallet recovery on isolated CI worker | 7bdfd0e CI #42940525641: real regtest daemon in temporary datadir; 24,576-byte backup, distinct restored wallet, locked state and address ownership verified using CLI | **PASS (isolated real-Knots CLI CI); NOT equivalent to signed app/UI recovery or production deletion proof** |
| Encrypted descriptor create via installed Wallet UI | RPC/mocks and separate real Knots CLI check; user previously reported UI runtime failure | **P0 OPEN — independently verify GUI and full backup flow** |
| Keychain requested-save failure and duplicate credential | Creation-only pre-save now fails before RPC on unavailable/mismatched/canceled Keychain; injected unit tests; actual Mac behavior not yet tested | **SOURCE + CI PASS (5 custody tests); NATIVE OPEN — P0** |
| Adopt existing Knots via bitcoin.conf or .cookie | SOURCE #071 + CI negative tests; live success PEER | **P0 OPEN** positive/PID/RPC binding |
| Dock/Cmd+Tab/closed-window/zoom | SOURCE #070; live use PEER | P1 OPEN zero-window/force-unwrap |
| Apple Passwords + signed app, consent and Keychain test | Candidate UI; CI interactive test SKIPPED | **P0 OPEN** |
| BTCB2 send and RBF security hold | #079 had executable sendtoaddress/bumpfee path; c19332b restores WalletManager, generic RPC and UI hard gates; 2 new native Swift CI regressions passed | **SOURCE + CI PASS for application-layer HOLD; signing and live funds remain P0 BLOCKED** |
| Bitcoin Knots binary/checkpoint + BIP-110 SIGHASH_UNIFIED PSBT/signing | Partial source and Python reference-only tests; no independently verified signed transaction or funded PSBT binding | **P0 OPEN — do not enable funds** |
| Optimized SwiftUI Release executable and ad-hoc .app bundle | CI #42940525641: optimized release compile, pinned Knots archive/executable SHA256 check, ad-hoc codesign verification, Info.plist validation, and build manifest PR SHA PASS | **SOURCE + CI PASS (NOT Developer ID/notarized or installed app acceptance)** |
| Full signed app, embedded daemon, notarized DMG, Gatekeeper, updater, SBOM and external audit | New guarded Developer ID/AASA/notary script `scripts/build_production_dmg.sh`; owner certificates, HTTPS domain, native notarization and audits NOT RUN | **P0 OPEN, NOT DISTRIBUTED** |

**Required next evidence:** (1) fail-closed passphrase custody and native isolated create→inventory→backup→restore; (2) positive cookie/conf adoption and negative endpoint/PID/file-type tests; (3) native window/Ultra/2FA and Apple Passwords; (4) signing, binary provenance, independent security and distribution. No real operator wallet or live funds may be used for qualification.

**Provenance:** [Project Status](docs/PROJECT_STATUS.md) · SCM session Session_Gemini_NodePocketBTCB2_20261106-1741; last peer MSG:SENTINEL-DAEMON-ADOPT-REPAIR-RECEIPT-20261109-071; [SCM rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md). New receipts must include exact SHA, CI and separately sourced native PASS/FAIL/SKIP evidence.
