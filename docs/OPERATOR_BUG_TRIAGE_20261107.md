# Operator Bug Fixes — 2026-11-07 (development review)

> **Current status:** [Built / In progress / Left](PROJECT_STATUS.md) (2026-11-09). This document is a detailed historical specification or agent receipt, **not** independent production acceptance. Public distribution and real funds: **NO-GO**.

## Owner-reported defects

1. **Max connected peers** input does not appear to change effective node limit.
2. **Wallet Manager Locked / Operator Sign-In** does not offer system Apple Passwords AutoFill or a user-consented Touch ID / Mac-password credential selection.
3. **Profile Active** on the Node page should appear at the top.

## Root causes and changes

### 1. P2P cap and inbound listening

- `NodeConfig` writes `maxconnections=<value>` to bitcoin.conf, but `NodeManager.start(ultraOverride: true)` supplies `-maxconnections=4` on the command line. The CLI override takes precedence. The old UI showed the configured cap as though it was the running cap.
- Power-state reporting used `SyncProfile.preset`, masking custom peer limits after they were applied.
- The Advanced Settings `Enable Inbound P2P` toggle previously did not flow into `NodeConfig`; new installs previously hard-coded `listen=1` despite the UI stating default off.
- Now `allowInboundP2P` persists in bitcoin.conf, preserves existing explicit `listen` values across upgrades, defaults to off on new installations, and is passed through Settings to `NodeManager.applyConfiguration`.
- During running Ultra Power, changes to the configured peer limit are **saved/queued**, not falsely reported as effective; the daemon continues with the intentional 4-peer override. On return to stable AC, the managed restart uses the saved operator profile. Normal managed changes apply through graceful shutdown/restart and RPC readiness verification.
- The Node and Network screens distinguish configured maximum from verified app-owned running cap; adopted/external daemon effective cap is **unverified**.
- **Critical semantics:** `maxconnections` is a ceiling, **not a target** or a command to open that many outbound connections. Outbound selection and inbound firewall/NAT/listening determine observed count. No automated port forwarding or unsafe RPC exposure is added.
- Never erase/reindex existing IBD, block data, wallet files, RPC credentials or chainstate when applying settings.

### 2. Apple Passwords operator sign-in

- Add `textContentType(.username)`, `textContentType(.password)` (macOS 14+ guarded) and `textContentType(.oneTimeCode)` to login inputs; prefill only the public enrolled local username.
- Add **Fill from Apple Passwords…** invoking `ASAuthorizationPasswordProvider` with `ASAuthorizationController`. macOS handles user consent and any Touch ID / system password authentication, then returns the approved credential to the sign-in fields. The app does not enumerate Passwords, read vault files, skip 2FA, or save credentials without consent.
- Clear transient password/TOTP on successful login or when the Wallet tab relocks.
- **NOT YET END-TO-END WORKING IN CURRENT DEVELOPMENT BUILD:** Apple requires the owner-approved HTTPS `webcredentials:` Associated Domain, hosted AASA containing the actual Team ID and app bundle ID, a properly signed app, and a preexisting matching credential. No owner-approved domain or signing configuration exists in this branch. The credential provider should fail/return no credentials rather than inventing stored passwords. A one-click Apple Passwords *saving* flow using `CredentialDataManager.save` is separately pending those same prerequisites. A user must still verify a six-digit TOTP or use protected recovery.

### 3. Node profile position

- Relocate the **Active Sync Profile** summary directly below the Node View status header, before the launch button, controls, metrics, and ETA. Preserve existing accessibility and details.

## Tests and acceptance

- New regression tests cover custom `maxconnections` persisted across reopen; inbound OFF/ON switching and preservation across upgrade; Ultra 4-peer mode cap without deleting saved 40-peer profile; absent live cap on stopped node.
- Existing consensus-safety test updated to require `listen=0` on **new** installations, with explicit preservation of existing `listen=1` configs.
- CI should compile the complete macOS app (including AuthenticationServices) and run native Swift tests; success in CI is not a substitute for live signed-hardware tests.
- Real Mac verification required: P2P restart/actual process arguments; Ultra on battery and custom cap resume on AC; inbound port and NAT; Apple Passwords correct credential list, consent, Touch ID/password fallback and TOTP; no user data loss across restart.
- Do not merge PR10/this stacked PR as production, use funds, delete wallets, reset IBD, or claim Apple Passwords working until signing and hardware verification are proven.
