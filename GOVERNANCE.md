# Governance — Sentinel Node Wallet BTCB2

**Single current-status authority:** [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) (built / active / remaining). The [release matrix](TEST_AND_RELEASE_MATRIX.md) is the acceptance ledger; historic v7–v13 memos are specifications and receipts, not blanket completion evidence.

## Immutable boundary

- Native Apple Silicon/macOS SwiftUI application, **Node / Wallet / Network** and one Advanced sheet; local BTCB2 BLAKE2b/BIP-110 MainNet-only Knots and self-custodial wallets.
- Isolate source, credentials, runtime and datadir from every other project. No hosted wallet, pool, gateway, miner control, remote RPC or consumer TestNet/RegTest. Isolated test-only regtest is allowed off-product.
- Preserve the operator's existing node, wallet identity, Keychain, backups, prune settings, blockchain state and active synchronization. No data deletion, spend, production stop/restart, new app identity or network exposure without explicit operator permission.
- **Fail closed:** encrypted descriptor wallets; no silent weaker Keychain fallback; authenticated, verified daemon; owned/secured files; independent confirmation before destructive operations; send/broadcast disabled until BTCB2 SIGHASH_UNIFIED and all security gates are proven.

## Change authority and evidence

- Review on [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10), branch fix/v13-1-security-remediation-20261107. **No unreviewed merge or production release.** Preserve historical receipts; report supersession explicitly.
- Every change/receipt records exact code SHA, test run + pass/fail/skip, installed-Mac evidence versus mocked/source proof, unresolved P0/P1 and operator impact. Never call an optional/skipped test a native PASS.
- Code and CI evidence baseline: **2aa0e15**; CI [42938948275](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42938948275): **132 passed / 0 failed / 1 skipped** (133 executed); optimized native SwiftUI Release executable and packaging shell syntax compile PASS. The earlier Keychain creation fail-open correction and c19332b app-layer send/RBF HOLD remain intact. New deletion HOLD prevents moving any wallet to Trash until isolated restoration proof is implemented. `scripts/build_production_dmg.sh` remains owner-controlled and unexecuted; production notarization/native security audit still OPEN. This documents development progress only.
- All security/production release gates in [SECURITY.md](SECURITY.md) and [TEST_AND_RELEASE_MATRIX.md](TEST_AND_RELEASE_MATRIX.md) require independently inspectable evidence; the owner authorizes production changes separately.

## Shared agent governance

Use canonical Shared Cognitive Memory session **Session_Gemini_NodePocketBTCB2_20261106-1741**, **InterAgent_Dialogue_Channel**, search_nodes → open_nodes and exact peer-message provenance. Follow the [canonical SCM rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md). Never write secrets, private keys, passphrases, addresses, full wallet logs or user financial records to shared memory or the repository.

**Decision:** Development candidate only; production, distribution and real-funds use **NO-GO** until independent security and device acceptance clears every P0.
