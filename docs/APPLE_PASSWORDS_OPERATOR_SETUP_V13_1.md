# v13.1 — First-Time Operator Setup: Apple Passwords

**Status:** Implementation and acceptance framework, not deployed Apple Passwords functionality.
**Goal:** During first enrollment in the existing Wallet tab, offer operator-chosen Apple Passwords strong-password creation/saving and separate optional 2FA-key enrollment to Apple Passwords, without adding any cloud account or new tab.

## Minimal three-stage flow

**1. Operator username and password**
- Username (macOS SwiftUI textContentType.username).
- Password input (textContentType.newPassword) so properly-associated system UI can suggest strong passwords. Offer "Use Suggested Strong Password", "Generate Strong Password", and "Enter My Own". If Apple's suggestion is unavailable, the app fallback must use SecRandomCopyBytes, check OSStatus, supply at least 128 bits of entropy and satisfy the current password policy.
- Independent user opt-in "Save login in Apple Passwords". For a signed, verified app, call AuthenticationServices CredentialDataManager.save(password:for:title:) with ASPasswordCredential and ASAutoFillURLScope; await system result, then verify the user sees the credential in Apple Passwords. This saves to the user's preferred password manager; distinguish Apple Passwords from another selected manager. Never claim a generic macOS Keychain secret is an Apple Passwords login.
- Required prerequisites: an OWNER-APPROVED static HTTPS webcredentials domain, valid apple-app-site-association file (AASA) linking actual Apple Team ID and stable macOS bundle ID, matching associated-domains entitlement, real Developer ID signed application and compatible macOS API availability. No owner domain/team authorized yet. The domain hosts only AASA metadata — NO user login, wallet requests, RPC, passwords or TOTP.
- If domain/signature/API unavailable, show "Apple Passwords automatic saving unavailable — continue with secure manual save". Never silently save in a weaker Keychain item; preserve existing credentials.

**2. Set up two-factor verification**
- Offer two separate user choices: "Add Verification Code to Apple Passwords" and "Use Another Authenticator". Default neither without consent.
- Generate >=160-bit RFC6238 TOTP secret. Keep server-side verifier copy only in protected app Keychain (not in plaintext auth_registry.json). Apple Passwords receives a separate user-approved copy as the user's authenticator.
- For Apple Passwords, open Apple-documented apple-otpauth://totp/Service:username?secret=BASE32&issuer=...&digits=6&period=30 from a REAL button click. The Apple system prompts the user to choose a saved password entry and attach the code. Opening a URL alone does not prove the secret was stored; demand actual code verification afterward. Never upload the URI or seed, log it, paste it automatically, or save it in browser history.
- For another authenticator show ordinary otpauth QR/manual masked key, with copy only on explicit click. Keep independent authenticator option for better factor separation.
- Verification code field uses macOS SwiftUI textContentType.oneTimeCode; check the six-digit code and anti-replay before enabling account. Warn: storing password and TOTP in the same vault reduces factor independence; high-risk wallet actions still demand independent macOS owner/Touch ID approval.

**3. Finish securely**
- Explain exactly which of: password save success, 2FA authenticator configured+verified, recovery codes saved OFFLINE. Distinguish "requested", "system prompt opened", "saved & verified", "declined", "unavailable", and "failed".
- Do not activate operator account without verified TOTP. Enroll app credential and wallet account without losing either on partial save, failure, migration or relaunch. Never silently delete or replace old Apple Passwords or Keychain entries. Require offline backup of encrypted descriptor wallet and separate high-entropy recovery codes.
- Keep Node and Network running while Wallet locked, no extra tabs, no new services or DATUM.

## Engineering sequence

1. Read latest Gemini P0 security remediation receipt MSG:SENTINEL-V13-SECURITY-REMEDIATION-RECEIPT-20261106-028 and merged PR #8 (main 2923ea9). Confirm no TOTP plaintext; review KeychainHelper because its current savePassphrase still falls back after -34018 to a less-restricted item. Repair with proper entitlements and fail-closed migration before general release.
2. Implement minimal isolated native AuthenticationServices bridge. Add UI choices in WalletView.enrollmentCard; preserve login/2FA auth coordinator as core enforcement and secure Keychain verifier. Do not add login server.
3. Handle save during provisional enrollment: system Passwords entry may need to exist before apple-otpauth attaches 2FA; only commit final app enrollment after verified code. Failures keep safe retry and truthful status; don't leave app believing credential saved if OS canceled.
4. Test real signed macOS app with owner-approved AASA; Apple Passwords receipt, invalid signing, no AASA, denied/canceled save, OS unavailable, password strength, TOTP replay, app restart, recovery and no secrets in disk/log/clipboard.
5. Retain v12 Ultra 4 peers/zero inbound, pruned node, existing wallets and MainNet only. Full production audit remains BLOCKED pending safe sending, signed/verifiable Knots and notarization.

## Acceptance tests

- System suggests strong password on supported signed-associated build; user can opt into/off, choose manual, or CSPRNG fallback; password meets rules, not logged.
- Save-to-Apple-Passwords approved creates correct username at real signed domain; denial/cancel/timeout fail without false success.
- apple-otpauth opens system-controlled Save Verification Code UI for existing account; verify output is accepted as the 6-digit RFC6238 code. Other authenticator works without Apple Passwords.
- Same-vault 2FA warning and separate user-presence for sensitive wallet operations remain enforced at CORE methods.
- No entropy/security/credential downgrade on -34018; no Keychain or descriptor-wallet data loss. Existing operator enrollment is preserved.
- macOS native build+UI tests PASS, exact signed binary/TeamID/AASA verified, compile API availability, no real funds. Report PASS/FAIL/NOT RUN, do not call feature shipped until actual Apple Passwords device test.

**Apple primary docs**
- https://developer.apple.com/documentation/authenticationservices/credentialdatamanager/save%28password%3Afor%3Atitle%3A%29
- https://developer.apple.com/documentation/AuthenticationServices/securing-logins-with-icloud-keychain-verification-codes
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains
- https://support.apple.com/en-gb/guide/passwords/mchl873a6e72/mac
