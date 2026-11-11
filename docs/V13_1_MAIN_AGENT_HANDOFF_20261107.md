# Current Agent Handoff — Sentinel Node Wallet v13.1

**Current snapshot supersedes 2026-11-07 headings:** 2026-11-10. **Project status and blockers:** [PROJECT_STATUS.md](PROJECT_STATUS.md). **Decision:** development progress accepted; public release, real funds and production deployment **NO-GO**.

- **Review location:** [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), branch fix/v13-1-security-remediation-20261107; still unmerged.
- **Latest source/CI code SHA:** [2aa0e15](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/commit/2aa0e155329c141cbee72a9ea8adb1b20ccb392a) (maintains the c19332b send/RBF HOLD; also removes unsafe ignored failed live-daemon restore and disables destructive wallet Delete pending isolated proof; adds owner-gated Developer ID/notary candidate script and optimized app Release compile in CI).
- **CI:** [42938948275](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42938948275) 133 executed, **132 passed, 0 failed, 1 interactive Keychain test skipped**. Optimized macOS SwiftUI Release executable compile PASS and packaging-script syntax PASS; no signed native app test.
- **Canonical session:** Session_Gemini_NodePocketBTCB2_20261106-1741; previous Antigravity implementation receipts live in Session_Antigravity_SentinelNodeWallet_20261110-0415 but do not supersede canonical ownership; bus InterAgent_Dialogue_Channel; last receipts **MSG:SENTINEL-WALLET-MGMT-MEMPOOL-REMEDIATION-RECEIPT-20261110-078** and **MSG:SENTINEL-NODE-WALLET-BTCB2-CONSENSUS-HASHRATE-AND-ARMED-SEND-RECEIPT-20261110-079** (#075 reconciliation; #076 windows; #077 wallet creation; #078 wallet management & mempool fees; #079 consensus hashrate, armed send & live USD). Keep peer and auditor claims separate.

## Built / working / left

**Built in source:** native Node/Wallet/Network app; Knots RPC/consensus checks, node sync/health/Ultra; multi-wallet encrypted-descriptor path, inventory/archive/backup; local multi-account password/TOTP/recovery; price feeds and Apple Passwords hooks; wallet renaming; RBF bump fee (BIP-125); pending vs confirmed balance differentiation; live mempool suggested fees; sync-gated 30-block consensus hashrate tracker; previously armed send transaction pipeline with Bech32 validation and estimated PSBT preview (P0 regression now blocked in c19332b before unlock/sign/broadcast/RBF at wallet and RPC levels); reactive live USD calculation stays informational.

**In progress:** core send NO-GO gate reinstated (SOURCE+CI PASS) while independent SIGHASH_UNIFIED signing proof remains P0; destructive Delete/Trash now disabled until isolated recovery proof exists; native Keychain validation on authorized signed Mac **P0**, backup durability and failed-operation cleanup **P0**, developer ID signing and Apple notarization preparation **P0**.

**Left to qualify:** on-device device-owner/Apple Passwords/2FA; actual fork signing and trustworthy Knots supply chain; Ultra/power transitions; signed/notarized app+embedded daemon, updater and independent audit. See [matrix](../TEST_AND_RELEASE_MATRIX.md) for precise evidence states.

## Next agent procedure

1. Read [AGENTS](../AGENTS.md), [GOVERNANCE](../GOVERNANCE.md), [SECURITY](../SECURITY.md), [PROJECT_STATUS](PROJECT_STATUS.md). Fetch fresh HEAD and CI; query SCM via search_nodes → open_nodes for exact session and dialogue bus.
2. Work only on reviewed dev branch. Use isolated zero-funds test daemons/wallets. Never change the real node, operator wallet, Keychain, IBD, funds or external projects. **No merge/production action without separate owner approval.**
3. Reproduce and verify the 5e7a597 Keychain fail-closed fix on an authorized signed Mac; no user wallet testing. Then independently demonstrate installed-app isolated wallet creation, inventory and backup/restore. Next verify daemon positive/negative cases, native windows and release gates.
4. Report exact SHA + CI + native/CI distinction + redacted reproduction + unresolved gates. Preserve receipt provenance and mark supersession; never print secrets.

[Full historic v7/v12/v13 contracts](FINAL_PRODUCTION_SECURITY_AUDIT_V13.md) remain reference, not release approval.
