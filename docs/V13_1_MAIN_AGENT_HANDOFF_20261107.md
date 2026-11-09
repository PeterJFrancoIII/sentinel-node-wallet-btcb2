# Current Agent Handoff — Sentinel Node Wallet v13.1

**Current snapshot supersedes 2026-11-07 headings:** 2026-11-09. **Project status and blockers:** [PROJECT_STATUS.md](PROJECT_STATUS.md). **Decision:** development progress accepted; public release, real funds and production deployment **NO-GO**.

- **Review location:** [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), branch fix/v13-1-security-remediation-20261107; still unmerged.
- **Independently audited code SHA:** [35cee85d](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/commit/35cee85d870c2df2e16f30409ebcc4b9bc536179).
- **CI:** [42578630048](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42578630048) 113 passed, 0 failed, 1 interactive Keychain test skipped.
- **Canonical session:** Session_Gemini_NodePocketBTCB2_20261106-1741; bus InterAgent_Dialogue_Channel; last peer receipt **MSG:SENTINEL-DAEMON-ADOPT-REPAIR-RECEIPT-20261109-071** (#069 wallet RPC diagnostics; #070 windows; #071 daemon adoption). Keep peer and auditor claims separate.

## Built / working / left

**Built in source:** native Node/Wallet/Network app; Knots RPC/consensus checks, node sync/health/Ultra; multi-wallet encrypted-descriptor path, inventory/archive/backup; local multi-account password/TOTP/recovery; price feeds and Apple Passwords hooks. Spend deliberately blocked.

**In progress:** Keychain requested-save failure **P0**, native wallet create→inventory and recovery **P0**, successful authenticated daemon adoption + RPC/PID binding **P0**, zero-window restore/zoom **P1**, backup durability and failed-operation cleanup **P0**.

**Left to qualify:** on-device device-owner/Apple Passwords/2FA; actual fork signing and trustworthy Knots supply chain; Ultra/power transitions; signed/notarized app+embedded daemon, updater and independent audit. See [matrix](../TEST_AND_RELEASE_MATRIX.md) for precise evidence states.

## Next agent procedure

1. Read [AGENTS](../AGENTS.md), [GOVERNANCE](../GOVERNANCE.md), [SECURITY](../SECURITY.md), [PROJECT_STATUS](PROJECT_STATUS.md). Fetch fresh HEAD and CI; query SCM via search_nodes → open_nodes for exact session and dialogue bus.
2. Work only on reviewed dev branch. Use isolated zero-funds test daemons/wallets. Never change the real node, operator wallet, Keychain, IBD, funds or external projects. **No merge/production action without separate owner approval.**
3. Fix and test the P0 Keychain fail-open first. Then independently demonstrate installed-app wallet creation, inventory and backup/restore. Next verify daemon positive/negative cases, native windows and release gates.
4. Report exact SHA + CI + native/CI distinction + redacted reproduction + unresolved gates. Preserve receipt provenance and mark supersession; never print secrets.

[Full historic v7/v12/v13 contracts](FINAL_PRODUCTION_SECURITY_AUDIT_V13.md) remain reference, not release approval.
