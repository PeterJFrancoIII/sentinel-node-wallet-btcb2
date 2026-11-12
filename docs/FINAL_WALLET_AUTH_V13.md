# Wallet Manager v13 — Final Local Login + Apple Passwords Contract

> **Current status:** [Built / In progress / Left](PROJECT_STATUS.md) (2026-11-09). This document is a detailed historical specification or agent receipt, **not** independent production acceptance. Public distribution and real funds: **NO-GO**.

**Product:** Sentinel Node Wallet - BTCB2 (native macOS, BTCB2 BLAKE2b/BIP-110 MainNet only)  
**Status:** Final **implementation specification**, not an already implemented or deployed feature.  
**Owner request:** One local username, strong password, and two-factor login, working with Apple's Passwords app where OS support and verified signing/associated domains permit. No new cloud login service.  
**Scope freeze:** This is the *last feature change* before the full production-security audit and cleanup. Do not mix authentication development with a fresh wallet format, binary update, DATUM gateway, mining/pool integration or additional navigation tabs.

## The hard technical boundary

**macOS Keychain is NOT the same as the Apple Passwords app.** A generic `kSecClassGenericPassword`/`SecItemAdd` item with a private app service name does not guarantee visibility in Apple Passwords or app AutoFill. Apple `CredentialDataManager.save(password:for:title:)` may save a username/password to the user's preferred password manager when supported, but the URL scope must belong to a `webcredentials` Associated Domain verified through an HTTPS `apple-app-site-association` (AASA) file **or** the app must have a real browser entitlement. This local wallet is not a web browser. Claim no Apple Passwords integration until the owner authorizes a domain and a correctly signed Mac binary passes end-to-end tests.

The owner can choose a narrowly scoped dedicated static HTTPS host for `webcredentials`/AASA. Its only purpose is to prove app ownership and permit Apple Passwords credential association; **it must not handle wallet passwords, TOTP, accounts, seeds, RPC, addresses or transaction requests**. Do not assume a specific existing business/mining domain is authorized. Preserve historical bundle ID `app.nodepocket.btcb2` and the existing Apple Team ID/Keychain services until a separately tested migration plan proves no wallet will be stranded. AASA must match the real signed `TEAMID.bundleID`, not a guessed ID.

## Minimal user experience — Wallet tab only

- The **Node** and **Network** tabs remain visible and validating/relaying in the background while Wallet is locked; never pause IBD or fail node startup merely because the user has not logged in.
- Before authentication the Wallet tab shows only a compact lock surface: `Username`, `Password`, `Verification code`, `Unlock Wallet Manager` and a `Forgot login / recovery` flow. Show no wallet names, balances, addresses, history or fiat amount in the locked state; no previews from stale sessions. No additional app account tab, web server or analytics service.
- First setup: user chooses a unique local username and a **strong randomly generated password** (support manual strong passwords). Explain that the **wallet encryption passphrase is separate from this login password**, and neither is a BIP39 recovery seed.
- Offer **Save login to Apple Passwords** only through system-mediated, user-approved AuthenticationServices and verified domain association when genuinely supported. Autocomplete suggestions and saving must be tested on the real signed macOS app. If unsupported, offer a truthful manual-copy/save instruction and the local secure Keychain-based login; **never** falsely claim Apple Passwords storage succeeded.
- Second factor: enrollment generates a standards-compliant `otpauth://totp/` provisioning QR and text key for a TOTP authenticator. Apple Passwords can generate and autofill those verification codes; also permit an independent authenticator, which offers better separation of factors. Never reuse a wallet's receiving QR for TOTP.
- Wallet management after a successful **username + password + TOTP** login: individual wallets/balances, history, receive address, trusted recipients, backup, archive and verified delete. A concise lock icon in the Wallet header permits immediate manual lock.
- A **fresh macOS user-presence challenge** (Touch ID or device password, with Keychain access control checked) remains mandatory for high-risk actions. One successful session MUST NOT grant unattended signing, wallet-passphrase access, trusted-recipient changes, password/2FA reset, backup/export, restore, archive/delete, transaction fee-bump or transfer authorization.

## Authentication architecture — local, offline-first

1. A minimal `WalletAuthCoordinator` / `WalletAuthGate` acts as the **single security authority**. UI state is presentation only. The core Wallet Manager must require a valid, narrowly scoped authorization capability at entry to **every wallet-sensitive RPC path**, and high-risk paths require a fresh owner-presence/approval capability. Do not rely on SwiftUI `isUnlocked`, an unprotected boolean, a public `AppState` method or a global basic-auth RPC credential.
2. Enrollment is explicit; no default username/password/TOTP seed or shared factory credentials. Store only a **versioned password verifier**: unique CSPRNG salt and a reviewed memory-hard Argon2id implementation with calibrated parameters; require owner-reviewed dependency/license if adding a hashing library. When dependency-free CommonCrypto PBKDF2 is chosen for macOS compatibility, document its limitations, calibrate its work factor and never call unsalted SHA256 or fast hashing adequate password storage. Never store the raw login password in files/UserDefaults/CI/Shared Memory.
3. Generate the TOTP secret with `SecRandomCopyBytes` (at least 160 bits), store it in a user-scoped macOS Keychain item with mandatory `SecAccessControl.userPresence` as appropriate to the verified signing identity. Verify RFC 6238 TOTP (default 6 digits/30 seconds; ±1 tick maximum with reasoned skew handling) using constant-time comparison, and reject replay of the last accepted counter. Do not log, sync or send this secret. The Apple Passwords copy of the code, if enabled by the user, is theirs to manage.
4. Enforce persistent per-account attempt throttling with reasonable exponential backoff and a maximum session lifetime; failed attempts NEVER delete wallet files, alter wallet passphrases or reset Keychain items. Do not permanently lock a legitimate user out of independently backed-up wallets. TOTP activation requires proving a fresh correct code before enabling.
5. Authorization states: `NOT_ENROLLED`, `LOCKED`, `AUTHENTICATING`, `UNLOCKED_READ`, `STEP_UP_REQUIRED`, `RECOVERY`. Only approved, short-lived **in-memory** capabilities transition to wallet access. Clear login password/OTP form fields on success/cancel/failure. Auto-lock on inactivity, macOS login-window lock, sleep/user switching and app quit; never automatically unlock on app relaunch.
6. Step-up approval binds the exact wallet identity, source chain, requested action, destination full address, integer-satoshi amount and fee/inputs/change when relevant. It expires quickly, is single use, and is rechecked inside the wallet RPC/transaction pipeline. Merely signing in with Apple Passwords or Touch ID is not a substitute for BTCB2 `SIGHASH_UNIFIED`, verified fork identity, real funded PSBT, or separately encrypted Knots wallets.
7. Treat Keychain `errSecMissingEntitlement -34018` as a **security configuration failure**, not permission to downgrade to an unprotected item. **P0 current source finding:** `KeychainHelper.savePassphrase` retries a less-protected `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` item after -34018/-50, and `getPassphrase` can retry retrieval without the explicit user-presence context. Replace these silent fallbacks with explicit, safe macOS entitlement/signing diagnostics and verified user choices; never silently create an unencrypted wallet or weaken existing credential protection. Audit/migrate any legacy weaker items **without deleting or overwriting them** before a reversible backup-tested migration.
8. Local IPC/RPC boundary: Bitcoin Knots stays `127.0.0.1` authenticated with least privilege and strict cookie permissions. The native app must never expose private wallet actions through unauthenticated local web endpoints. A local username/login **cannot reliably stop malware that controls the same user session or direct RPC cookie**; protect critical signing and export with an independently enforced Keychain/device-owner gate. Consider a hardware/offline signer for high-value funds. Do not claim protection against fully compromised macOS/root access.

## Recovery without fund loss

- Generate at least 10 one-time recovery codes, display them once for **offline** storage, save only independently salted/hashed verifiers (or equivalent sealed values), and consume codes irreversibly after successful use. Account recovery needs recovery code **plus** a device-owner/Keychain consent step where feasible; cannot silently disable 2FA or replace a wallet-passphrase without authorization.
- If login/password/TOTP credentials are lost, make the app's `local login identity` recoverable with a documented, physically authorized procedure **without deleting** any Knots descriptor wallet, Keychain secret, transaction history, UTXO database or blockchain datadir. A separately verified encrypted-wallet backup and its passphrase are essential for moving to another Mac; a TOTP recovery code is not wallet backup.
- `ThisDeviceOnly` Keychain data does not necessarily follow iCloud/Time Machine or migrate to a replacement Mac. Test cold-device recovery from separately stored wallet backup and secret, not from login credentials alone.
- No account reset simply on failed app upgrade, temporary AASA outage, missing network, Apple Passwords not running, or an ad-hoc development signature.

## Apple Passwords implementation / acceptance details

**Prerequisites:** Developer ID/team identity with valid signed `app.nodepocket.btcb2` (or separately approved compatible migrated identifier), owner-approved HTTPS host, correct `com.apple.developer.associated-domains` value `webcredentials:HOST`, deployed `/.well-known/apple-app-site-association` with matching `TEAMID.bundleID`, and verified entitlement inside the installed app. Associated-domain hosting is **static discovery metadata only**, never an online wallet service.

**Preferred OS integration:** Native SwiftUI username/password/TOTP fields with platform-supported AutoFill hints, real AuthenticationServices credential save after *user approval* and successful registration, credential retrieval via the system UI, and Apple Passwords verification-code enrollment through `otpauth://`. Check actual macOS API availability/build requirements; prefer no unsupported OS assumptions. Avoid using a fake browser entitlement or hijacking an unrelated domain. If API or associated-domain verification is unavailable, the feature must clearly show `Apple Passwords integration unavailable; manual sign-in remains supported` rather than success.

**End-to-end Mac evidence:** (i) Apple Passwords shows the wallet-login username/password after owner consents, (ii) app relaunch autofills only following OS user interaction, (iii) Apple Passwords can generate a correct TOTP and offer an autofill suggestion on the real signed app, or the UI documents manual copy if unsupported, (iv) offline login still works with a locally configured account and authenticator; (v) ad-hoc build without entitlements reports degraded availability without weakening local wallet encryption.

**2FA caveat:** Password and TOTP in the same Apple Passwords account create two protocol factors but share one credential manager and may be compromised together. For wallet export/send/backup/delete, add device-owner Secure Enclave/Keychain user-presence step-up. Independent authenticator on an iPhone/security device offers better factor separation.

## Mandatory adversarial tests (Swift + actual Mac)

- No enrollment => Wallet locked, Node sync continues; no default account. Correct/incorrect username, wrong password, OTP wrong/expired/replayed and rate limiting; TOTP clock skew at ±1 step, restored clock.
- App relaunched/slept/locked, session expiry, multiwindow, rapid tap, restored state and concurrent tasks; direct call to every WalletManager RPC without auth must be rejected; no isolated bypass via `BitcoinRPCClient`.
- Password manager disabled/absent, no associated domain, invalid AASA, wrong Team ID, ad-hoc signing, entitlement -34018, biometric deny/cancel; no false AutoFill success or weaker Keychain secret creation.
- Approved Apple Passwords saving/autofill and OTP login with real signed app; verify never uploading passwords or wallet keys to the application owner's servers.
- Login password/TOTP change and recovery under high-risk step-up; back up an empty encrypted descriptor wallet, recover on another Mac, preserve all funds/history if existing wallet already present.
- Confirm every high-risk action blocked without fresh owner-presence and transaction/recipient/fee binding; no real-fund sends during tests.
- Keep the earlier Ultra correction (battery+charging: **maxconnections=4**, `listen=0`, `par=1`, owned bitcoind low CPU/I/O priority), only one Settings button, pruned new-install default, all-wallet inventory, accurate rolling-history coverage and BTCB2-fork protections.

## Source references

- Apple `CredentialDataManager.save(password:for:title:)`: https://developer.apple.com/documentation/authenticationservices/credentialdatamanager/save%28password%3Afor%3Atitle%3A%29
- Apple Associated Domains: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains
- Apple Passwords verification codes: https://support.apple.com/guide/passwords/mchl873a6e72/mac
- Apple Password AutoFill: https://developer.apple.com/documentation/security/password-autofill
- Apple Passkeys (optional future alternative; domain is required): https://developer.apple.com/documentation/authenticationservices/supporting-passkeys

**Do not represent this specification as completed source functionality, Apple-approved capability, production-safe signing or installed Mac verification.**
