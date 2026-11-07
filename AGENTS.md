# Multi-Agent Operating Guidelines: Sentinel Node Wallet - BTCB2

> **Canonical Guidance Authority:**  
> `https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md`

All AI agents (Gemini, Antigravity, ChatGPT, Codex) working within or referencing this project MUST adhere strictly to these non-negotiable operational requirements:

## 1. Project Identity & Repository Scope
- **Official Brand:** `Sentinel Node Wallet - BTCB2` (Short menu label: `Sentinel Wallet`).
- **Target Repository:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`.
- **Identity Retention for Data Preservation:** To guarantee zero loss of existing user wallets, Keychain credentials, or 220,000+ synchronized block headers, the local workspace remains `/Users/computer/Developer/NodePocketBTCB2`, datadir remains `~/Library/Application Support/NodePocketBTCB2`, and macOS bundle ID remains `app.nodepocket.btcb2`.
- **Zero Cross-Project Coupling:** Strictly independent from mining pool daemons, external firmwares, or secondary systems. Zero shared credentials, RPC endpoints, or binary code.

## 2. Consensus & Network Requirements
- **MainNet Only:** Strictly BTCB2 BLAKE2b / BIP-110 MainNet.
- **Hard Fork Checkpoint:** Height `961,640`, block hash `0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb`.
- **No Alternate Networks:** RegTest, TestNet4, and Signet options are prohibited from shipped user interfaces, configurations, and public binaries.

## 3. Storage Architecture Guardrails
- **Compact Pruning Default:**
  - `prune=550` and `pruneduringinit=550`.
  - Operator selectable $\ge 550$ MiB.
  - Warn at $\ge 35$ GB datadir usage; gracefully stop at $\ge 40$ GB datadir or $\le 10$ GB host free space.
- **Archival Mode Hard Gating:**
  - Full unpruned history (~800+ GB) is strictly prohibited on internal storage (<50 GB free).
  - External SSD preflight requires $\ge 1$ TB verified free space.
  - Explicit warning of complete full-history download requirement.

## 4. Multi-Agent Coordination Protocol
- Inter-agent coordination is conducted through the Shared Cognitive Memory channel `InterAgent_Dialogue_Channel`.
- Every coordination post must include the standard header:  
  `[TIMESTAMP | SOURCE → DESTINATION | MSG:<unique-id> | SESSION:<canonical-session-id>]`
- Every report citing decisions or findings must include mandatory provenance citations:  
  `Shared Memory: <SESSION/ENTITY> | MSG:<message-id>`  
  `Shared Memory MCP Rules: https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md`
