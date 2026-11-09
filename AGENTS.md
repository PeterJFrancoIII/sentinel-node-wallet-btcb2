# Agent Instructions — Sentinel Node Wallet BTCB2

**Read first:** [Current project status](docs/PROJECT_STATUS.md) → [Governance](GOVERNANCE.md) → [Security](SECURITY.md) → [Test/release matrix](TEST_AND_RELEASE_MATRIX.md). Older implementation receipts are historical, not current instructions.

**Scope:** NODEPOCKET_BTCB2_ONLY. Standalone macOS SwiftUI BTCB2/BLAKE2b/BIP-110 MainNet-only Knots app: Node, Wallet, Network + Advanced sheet. No changes to unrelated repositories, operators' other systems, wallets, credentials or processes. No remote RPC or additional consumer chains. Preserve the real datadir, Keychain service, app identity, sync/IBD and all wallet files.

## At entry

1. Query canonical SCM **Session_Gemini_NodePocketBTCB2_20261106-1741** via search_nodes then open_nodes; search **InterAgent_Dialogue_Channel** for latest exact-session peer receipts. Apply [SCM rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md).
2. Fetch [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), its **fresh** HEAD and CI. Latest verified source+CI baseline: **5e7a597**; 117 passed, 0 failed, one interactive Keychain test skipped. This does not establish native Keychain PASS. Branch is **unmerged**.
3. Confirm status evidence in [Project Status](docs/PROJECT_STATUS.md). Distinguish **BUILT source**, **PEER-REPORTED native**, and **independently verified**. Do not recast stale V12/v13 planning as undone code.

## Current work order (priority)

- **P0** Keychain failure/mismatched-secret creation path is now source/CI remediated (5e7a597); independently verify actual Keychain hardware accept/deny/cancel and offline-custody acknowledgment, then prove encrypted wallet RPC creation and immediate inventory on an installed Mac using only isolated zero-funds test data.
- **P0** Prove positive bitcoin.conf and cookie-only daemon adoption; bind RPC endpoint to PID/executable/datadir; validate credentials and safe file types/permissions.
- **P1** Correct window recreation/force unwrap/targeted zoom; independently exercise Dock/Cmd+Tab/closed window.
- **P0 release gates** Native Keychain/2FA/Apple Passwords, recoverable backups, Ultra profile transitions, fork/signing and distribution audit. Keep send disabled.

## Safety and receipts

- No production daemon stop/restart, app deployment, wallet delete/restore, funded test, file/chainstate reset, unreviewed PR merge or spend. Operator authorization is a separate gate.
- Isolated regtest is **test-only**; never expose an alternate network in the product. Preserve immutable wallet/passphrase identity; passphrase alone is not a wallet backup.
- Do not bypass signingPathUnverified, Keychain OSStatus errors, daemon-verification rejection or backup durability uncertainty.
- Handoff with exact SHA, CI URL/counts, native environment + redacted reproduction, PASS/FAIL/SKIPPED/NOT RUN, superseded receipt IDs, open blockers and next safe action. No secrets or personal data.

See detailed legacy contracts in docs/; they do not override these current release controls.
