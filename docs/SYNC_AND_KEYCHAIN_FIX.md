# Targeted fixes: sync profiles and wallet passphrases

**Status:** code committed to a review branch; **NOT** yet installed or validated on the user's Mac. This document does not declare the wallet suitable for real funds. Do not merge, notarize, or publish as a production release until the native acceptance tests pass.

## 1. Quiet / Balanced / Fast — root cause and fix

The old Advanced sheet had two independent asynchronous pathways: `state.applyStorageMode(...)` and `nodeManager.switchProfile(...)`, each potentially stopping/restarting Knots, with `try?` hiding failures. The requested profile could therefore be overwritten or ignored. The battery health monitor could silently downgrade Fast to Balanced. The application also defaulted to Quiet on every startup, regardless of previously configured resource limits.

**Correction on this branch:**
- One `AppState.applyNodeSettings(profile:storageMode:)` call drives a single serialized `NodeManager.applyConfiguration` transaction.
- Atomic settings write and at most one graceful Knots stop/start, followed by RPC readiness verification; on failure restore prior config and disclose the error.
- Previously stored `bitcoin.conf` profile comment and numeric `par`, `dbcache`, `maxconnections`, and `maxuploadtarget` values are reloaded instead of resetting at launch.
- A user-selected Fast profile stays selected on battery; a one-time low-power suggestion replaces the forced downgrade.
- GUI selection and status change **only after** the configuration call succeeds. No concurrent Apply, no unbounded cache/threads/peers.
- If a previously running daemon has only been adopted and is not owned by this app session, the change currently **fails with a visible explanation** rather than killing an unverified node. Gemini must implement and prove datadir/PID-verified ownership for safe restarting of adopted app-owned nodes; do not use arbitrary PID matching or assume localhost port 8332 establishes ownership.
- Compact retention stays independent of resource profiles (`prune=550` is not reset when choosing Fast).

**Mac acceptance:**
1. Back up current app-owned wallet and capture current sync height/prune usage.
2. On a known app-owned Knots process, select Quiet, Balanced and Fast in turn; compare intended values **and actual on-disk config**, inspect one clean restart and verified RPC recovery for each; record exact PID and startup log/effective settings, not just a highlighted picker.
3. Restart the whole app. Confirm the selected profile and numeric limits survive unchanged.
4. Select Fast while on battery: profile stays Fast, with a power warning but no unsolicited downgrade. Confirm Quiet does not silently resume Balanced.
5. Inject failed RPC shutdown, locked config path and adopted-daemon cases; no false success, overlapping restarts, wallet corruption, or deleted chain data.
6. Compare storage footprint, pruning and wallet identity before/after. NO full IBD reset. Empty test wallet only, no real fund transfers.

## 2. Encrypted-wallet creation — generation and credential fill

**A Knots descriptor-wallet encryption passphrase is not a BIP39 or other recovery seed.** A random string cannot reconstruct an entire descriptor wallet. The user must separately back up the encrypted wallet database.

**Supported native macOS implementation:**
- `WalletPassphraseGenerator` uses Apple `SecRandomCopyBytes` for 32 random bytes (256-bit entropy), encoded as a URL-safe 43-character passphrase.
- Create Wallet has **Generate Strong Passphrase**, Show/Hide, Confirm, and opt-in `Save in macOS Keychain` (default on).
- The Keychain entry uses the wallet name as its account and a user-presence `SecAccessControl` item for the new passphrase, with `WhenUnlockedThisDeviceOnly` access and the legacy app service identifier kept stable.
- Keychain storage is attempted **before** wallet creation; errors block creation rather than silently leaving an unprotected secret. A duplicate is never blindly overwritten or deleted: user-approved retrieval and exact equality are required for a retry after an ambiguous RPC timeout.
- **Use Saved Passphrase** triggers explicit Mac owner authentication and securely fills the form when the user chooses it; retrieval is performed off the UI actor.
- On cancellation/success, SwiftUI passphrase fields are cleared; wallet names and secrets never go into logs/telemetry.
- This is an **application Keychain item**, which is not guaranteed to appear in Apple's separate **Passwords** app nor to receive browser-style AutoFill. Apple Passwords website-credential access requires an actual associated-domain and user-consent workflow; do not fake that integration or automatically export wallet keys to a website. Mac Keychain retrieval is the lightweight supported experience.
- `ThisDeviceOnly` does **not** guarantee migration or iCloud sync to another Mac. Display this limitation and require a verified encrypted wallet backup and an independently stored passphrase/recovery procedure.

**Mac acceptance:**
1. Generate 20+ passphrases; verify 43 URL-safe characters, 32-byte CSPRNG provenance and no duplicates in the sample.
2. Create a NEW EMPTY test-only descriptor wallet. Confirm it is encrypted and that the Keychain item is associated with the correct wallet name.
3. Close/reopen app; request **Use Saved Passphrase**, verify Mac authentication is required and the correct phrase is filled only on approval. Cancellation, locked Keychain and authentication failure must not return the secret.
4. Simulate wallet RPC creation timeout after Keychain save. Never delete a potentially valuable stored secret; user-approved retry must preserve the exact passphrase.
5. Export, verify and restore wallet backups, including a clean-mac/local-Keychain-unavailable scenario. Passphrase alone must never be called a recovery seed.
6. Ensure no secret appears in git, user defaults, logs, crash reports, clipboard, Shared Memory, a bundled DMG or test snapshots. No live MainNet transaction is to be sent.

## Release gate

The source branch also contains unrelated **final security corrections** (unsafe sends are disabled until replay-safe PSBT signing is audited; force-kill removed; pending full-history migration blocked; coinbase expiry timestamp fixed; read-only BTCB2 price oracle prototype). Review the **whole branch diff** and test these as part of the eventual full release assessment. No real-funds or production-release declaration until all P0 wallet/authentication, update-signing, fork-consensus, Apple notarization and wallet recovery requirements are met.
