# Create Encrypted Wallet — Open P0 Incident

**Status (2026-11-09): unresolved native acceptance; [Project Status](PROJECT_STATUS.md).** The operator reported a wallet-creation attempt failing with “Network connection error: Could not connect to the server.” The previous completion claim was not a verified installed-app success.

**Built remedial code:** #069 introduced RPC readiness/status, typed stage errors and reconciliation after an indeterminate createwallet result. CI mocks cover offline, warming up, 401 and server failures. This does not prove the operator's native failure is solved.

**Confirmed P0:** In WalletManager.swift, if Save in Keychain is requested but storage fails or conflicts, the code records a warning and still sends createwallet. WalletView then clears the entered passphrase and reports the warning. Do **not** treat post-creation advice as secure pre-creation consent.

**Required fix:** If requested Keychain custody fails, stop before createwallet or present an explicit pre-creation confirmation that the complete passphrase is securely recorded offline. Resolve conflicting secrets without replacement or orphaned wallets. Preserve entered passphrase until custody is verified; never reveal it in logs.

**Native acceptance:** On an isolated zero-funds Knots datadir, verify successful encrypted-descriptor creation, actual Keychain read-back/user consent, listwallets/listwalletdir and immediate All Created Wallets UI entry; test Keychain -34018/duplicate/cancel, RPC 401/offline/timeouts and uncertain commit/restart without duplicate creation or wallet loss. Verify a fresh backup→distinct-wallet restore. Distinguish CI mocks, peer screenshots and independent installed-Mac PASS.

**Gate:** NO-GO for real funds/production until P0 passes. No existing operator wallet or Knots state is a test fixture. [Release matrix](../TEST_AND_RELEASE_MATRIX.md).
