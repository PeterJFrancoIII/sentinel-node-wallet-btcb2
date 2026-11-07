# Security policy — Sentinel Node Wallet - BTCB2

**Development wallet: do not store real funds until independent audit and signed release gates are complete.** Report vulnerabilities privately through GitHub's repository security advisory or a verified maintainer contact, never a public issue containing exploitable details or user secrets.

## Threat model

Assume hostile websites, malicious browser extensions, clipboard substitution, compromised RPC peers, untrusted dependencies, unattended Mac sessions, stolen/unlocked devices, user tricked into approval and partial malware compromise. **No local hot wallet can guarantee security if the user account, process, memory or operating system is fully controlled by an attacker.** An independently controlled external signer is stronger than software-only controls for high-value funds.

## Hard safeguards

- Native encrypted descriptor wallets must **never** silently default to empty passphrase; fail closed and request deliberate user setup. A locked wallet can still receive and report chain status.
- Wallet passphrases belong to macOS Keychain with documented `SecAccessControl` / device-owner user-presence enforcement on each signing authorization. Avoid silent Keychain auto-retrieval, plaintext on-disk fallback, permanent process caches and unattended unlock.
- Keep current bundle ID, datadir, wallet identity and Keychain service stable until a separately tested migration; don't lose access while rebranding.
- RPC only on `127.0.0.1` with authenticated app-owned cookie and strict file permissions; no remote RPC, shared Sentinel services, public HTTP wallet endpoint or logs of secrets. Audit older persistent rpcuser/rpcpassword and move to cookie auth without breaking the user's existing node.
- Validate BTCB2 BLAKE2b hard-fork checkpoint at 961,640 and later anchor; fresh MainNet sync, correct replay-protected signing `SIGHASH_UNIFIED` and native encrypted-wallet ownership before authorizing transfer. The previous `sendtoaddress` call and UI's height-only gating are **not sufficient proof**.
- Permit only allowlisted BTCB2 addresses with explicit user-verified labels. Add/change/remove/disable the allowlist requires user-presence approval. Final send must bind the exact address, BTCB2 amount, fee and change/inputs; recheck immediately before signing; do not trust mutable UI fields.
- Use non-signing PSBT/funded raw transaction preview and integer satoshis. Default fee ceilings, validate relay policy, per-tx caps, dust and sufficient mature funds. Fail closed on no fee data; no hard-coded transaction vsize guesses.
- Authenticate and rate-limit spend flow against double-click/replay and unsolicited local IPC. Require a short-lived one-time approval token tied to immutable transaction details. Lock wallet immediately after use, on error and on cancel; avoid relying only on fire-and-forget asynchronous `defer Task` for lock.
- Log minimal redacted financial events; never export seeds/passphrases/address books to public CI, markdown, issue comments, telemetry, or Shared Cognitive Memory. No automatic background contact sync or explorer lookup.
- Bounded backup/restore workflows: verify backup readability, application wallet ownership, source chain identity and pruned history warnings; restore must not overwrite an existing wallet or corrupt encryption state.
- All-Wallet Inventory and Safe Deletion (V12):
  - Wallet Archive is strictly in-memory deactivation (`unloadwallet(name, load_on_startup=false)`). Wallet databases, descriptors, private keys, and Keychain credentials are fully preserved.
  - Wallet Deletion ('Delete from this Mac') enforces fail-closed safeguards: deletion is strictly blocked if spendable, pending, or immature balances are non-zero, or if balance state is unverified.
  - Deletion requires mandatory export of a verified non-empty backup file before any file movement.
  - Requires user presence and typing the exact full wallet name to confirm.
  - Execution uses macOS `FileManager.trashItem` (reversible Trash); `rm -rf` or unrecoverable deletion is prohibited.
  - Keychain credentials remain intact for disaster recovery.

## Explorer privacy

The BTCB2-compatible explorer `https://mempool.guide/tx/{txid}` may learn a viewer's IP and the TXID when clicked. Show an explicit external-link indicator; do **not** query or open it automatically. Ordinary `mempool.space` is the wrong chain unless a specifically verified BTCB2-compatible instance is selected.

## P0 public-code observations that need fixing

- `WalletManager.ensureDefaultWalletLoaded` currently risks an unencrypted wallet with empty-passphrase fallback.
- `WalletManager.send` currently accepts `tb1`/`bcrt1` and relies on `sendtoaddress` without proof of `SIGHASH_UNIFIED`, and uses `Double` amounts.
- `WalletView.isSendAllowed` currently checks IBD/height only, not a verified fork hash, recipient allowlist, quote binding or authentication.
- `KeychainHelper` uses basic when-unlocked device-only accessibility but no confirmed mandatory per-send user-presence policy.

Do not close any of these by UI wording alone. Fix code and verify with both mock adversity tests and actual authorized Mac Security.framework interactions.

## Security release gates

Unresolved P0 => no public notarized release and no recommendation to custody real funds. Independent review of signing correctness, storage/migration, dependencies and wallet recovery is required. This policy does not claim that Apple notarization proves wallet security.
