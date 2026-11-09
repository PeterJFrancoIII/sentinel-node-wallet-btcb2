# Test and Release Matrix — Sentinel Node Wallet BTCB2

**Snapshot:** 2026-11-09; code **5e7a597**; [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) open/unmerged. [CI #42705121938](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42705121938): **118 executed / 117 passed / 0 failed / 1 skipped** (interactive Keychain). **No release authorization.**

**Evidence classes:** SOURCE = implemented, CI = automated tests, PEER = agent's unreproduced native claim, NATIVE = independently recorded on-device test, OPEN = missing/failed/insufficient. A skipped or conditional test is **not** NATIVE PASS.

| Gate | Current evidence | Decision |
|---|---|---|
| Three-tab app, sync/profile, Ultra=4/listen=0 | SOURCE + CI | Built; native transition OPEN |
| Multi-user local password/TOTP/recovery, step-up | SOURCE + CI | Built; real user-presence/2FA OPEN |
| Neoxa/NonKYC price quotes and override | SOURCE + tests | Built; live pricing/fallback OPEN |
| Wallet inventory, archive, Trash guard, backup | SOURCE + CI | Built; crash/durability/recovery NATIVE OPEN |
| Encrypted descriptor create via installed Wallet UI | RPC/mocks; user reported runtime failure | **P0 OPEN** |
| Keychain requested-save failure and duplicate credential | Creation-only pre-save now fails before RPC on unavailable/mismatched/canceled Keychain; injected unit tests; actual Mac behavior not yet tested | **SOURCE + CI PASS (5 custody tests); NATIVE OPEN — P0** |
| Adopt existing Knots via bitcoin.conf or .cookie | SOURCE #071 + CI negative tests; live success PEER | **P0 OPEN** positive/PID/RPC binding |
| Dock/Cmd+Tab/closed-window/zoom | SOURCE #070; live use PEER | P1 OPEN zero-window/force-unwrap |
| Apple Passwords + signed app, consent and Keychain test | Candidate UI; CI interactive test SKIPPED | **P0 OPEN** |
| Bitcoin Knots binary/checkpoint + BIP-110 SIGHASH_UNIFIED PSBT/send | Partial source; send disabled | **P0 OPEN — no funds** |
| Full signed app, embedded daemon, notarized DMG, Gatekeeper, updater, SBOM and external audit | Development packaging claims only | **P0 OPEN** |

**Required next evidence:** (1) fail-closed passphrase custody and native isolated create→inventory→backup→restore; (2) positive cookie/conf adoption and negative endpoint/PID/file-type tests; (3) native window/Ultra/2FA and Apple Passwords; (4) signing, binary provenance, independent security and distribution. No real operator wallet or live funds may be used for qualification.

**Provenance:** [Project Status](docs/PROJECT_STATUS.md) · SCM session Session_Gemini_NodePocketBTCB2_20261106-1741; last peer MSG:SENTINEL-DAEMON-ADOPT-REPAIR-RECEIPT-20261109-071; [SCM rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md). New receipts must include exact SHA, CI and separately sourced native PASS/FAIL/SKIP evidence.
