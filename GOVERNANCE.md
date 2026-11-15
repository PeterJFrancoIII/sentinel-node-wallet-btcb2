# Governance — Sentinel Node Wallet BTCB2

**Current baseline (November 14, 2026, America/New_York):** [GitHub v1.0.0 Build 3 release](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3) is **published**; [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10) was **merged**. The current development base is `main`; its exact SHA and CI must be checked afresh before each change. [Project Status](docs/PROJECT_STATUS.md) is the current-status record; [Release Matrix](TEST_AND_RELEASE_MATRIX.md) tracks acceptance.

## Release states are distinct

1. **Source merged / CI green:** automated unit and simulated/isolated tests are passing on a particular SHA; not proof of wallet custody, signed GUI behavior, App Store acceptance or installer integrity.
2. **GitHub release published:** binary assets are downloadable. Build 3 DMG is attached with a reported SHA-256; the direct DMG script uses optional **Apple Development** signing. Public availability is not equivalent to notarization or independently approved funds use.
3. **Apple App Store Connect:** record `6833290684`, version `1.0 (3)` in current scripts. Portal upload, review state, regulatory eligibility and final approval require separate authenticated evidence. Do not infer those states from a GitHub release or Gemini's unverified report.
4. **Wallet production approval:** independent BIP-110/BLAKE2b transaction-signing, native credential custody, encrypted backup/restore and destructive-operation reviews are separately required. **Public installer exists; real-funds and security certification remain NOT CLEARED.**

## Project and data boundaries

- Standalone native SwiftUI Apple Silicon/macOS client for the BTCB2 BLAKE2b/BIP-110 MainNet, bundled Bitcoin Knots, local self-custody, three views and Advanced settings.
- Do not couple software or secrets to any other project. No cloud-hosted wallet backend, remote external RPC, automatic router changes, or alternative consumer blockchain mode. Isolated ephemeral regtest for tests is allowed.
- Preserve the user's live wallet, local data directory, Keychain entries, daemon, chainstate, pruning settings and identity. Do not run destructive cleanup, real-funds transfers, MainNet mutation or production node restarts for testing.
- Confirm exact app identity: public source currently uses bundle `pool.sentineldefensetechnologies.co.za` with Apple record `6833290684`. Old documentation may mention `app.nodepocket.btcb2` or `com.nodepocket.btcb2`; these are historical, **not current bundle IDs**.

## Code-level safety obligations

- The generic RPC client defaults `isBroadcastRestricted=true`; WalletManager conditionally stops send/RBF when restricted. **Treat any path that can set this false as privileged and unapproved for real funds until fork-specific independent signing review.** Do not advertise transaction security as audited.
- Individual-wallet Delete throws `restoreVerificationFailed` in current source even with a readable backup header; Archive is nondestructive. An independently verified recovery proof is required before authorizing Delete.
- **Full Uninstallation is a separate, broader destructive workflow.** It can delete the entire local data directory, including wallet files. It must not be conflated with wallet Delete or represented as a proven lossless process. Confirm backups and user authorization.
- Authentication and Keychain code must be tested on the actual signed app with device-owner accept/cancel and failures; a skipped interactive test is never a pass.

## Changes, evidence and approvals

- Use feature/documentation branches and reviewed PRs against `main`; do not bypass required checks or merge code that changes real-funds or destructive behavior without explicit security signoff. A docs-only update is not itself a wallet release.
- Each release receipt must include immutable commit and asset SHAs, complete test count (executed / passed / failed / skipped), Apple-signing identity and entitlements where relevant, on-device evidence separately from CI, distribution channel, exact app bundle ID and any open P0 findings.
- GitHub Build 3 source is identified in release notes as `357766bf8d5e219208148101dde5bc7c26f59b0e`; current main CI [#43663913374](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/43663913374) reports 144 executed / 143 passed / 0 failed / 1 skipped. The source/CI count does not certify the signed DMG's contents.
- Release notes, source, README and privacy disclosures must stay synchronized. Correct mistakes such as “144 passed” where the underlying run records **144 executed with one skipped**; never rewrite historical receipts as if they were latest.

## Shared Cognitive Memory

Canonical project session: `Session_Gemini_NodePocketBTCB2_20261106-1741`; coordination entity: `InterAgent_Dialogue_Channel`. Follow the [shared-agent rules](https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md). Cite message IDs verbatim, distinguish agent claims from verified artifacts, and never post passwords, tokens, wallet descriptors, seed material or private financial records. Latest operator-referenced release dispatch: `MSG:gemini-sentinel-v100-build3-github-dmg-release-121`.

**Decision:** Build 3 is publicly distributed via GitHub, but **independently verified real-funds safety, notarization/Gatekeeper and Apple final approval are not demonstrated here**.
