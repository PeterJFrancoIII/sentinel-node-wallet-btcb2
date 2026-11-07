# Wallet creation incident — corrective release gate

**Product:** Sentinel Node Wallet - BTCB2  
**Status:** candidate source fix only; a successful GitHub merge or XCTest mock does **not** prove the installed Mac wallet-creation dialog works.

## User-reported failure

On November 6, 2026, the owner reported that **Create Encrypted Wallet still does not work**, despite Gemini's preceding "verified and merged" handoff. That real-world report supersedes any blanket completion claim for wallet onboarding. The first-run flow was not adequately exercised.

## Reproduced source defects

1. **No-wallet startup incorrectly labeled failed.** Previously \`AppState.startNode()\` called \`WalletManager.ensureDefaultWalletLoaded()\`, which threw a generic "unencrypted wallet prohibited" error when no wallet existed. The outer catch set the entire startup to "Failed" although Knots might be syncing normally.
2. **Silent auto-creation from Keychain.** If a saved encryption passphrase existed but the wallet database was missing, startup could create a fresh wallet with a different descriptor/keyspace. This cannot recover the old wallet and risks false restoration assumptions.
3. **No collision preflight.** Creating a wallet with an existing disk name could write a Keychain entry before Knots returned "wallet already exists." A failed RPC could leave a saved passphrase for an unverified wallet.
4. **Success was not verified end-to-end.** The UI called \`WalletManager.createEncryptedDescriptorWallet\` directly, closed the modal, and asynchronously requested an address, but did not update \`AppState.walletSnapshot\` or the startup state as one verified operation. The UI could still appear empty.
5. **RPC lookup errors were swallowed.** Failures of \`listwallets\` and \`listwalletdir\` were incorrectly treated as evidence that no wallet existed.

## Candidate changes

- Start Knots first. If it is reachable and there is no wallet, display **Node running — create an encrypted wallet**. Continue IBD; do not stop Knots or erase a datadir.
- Make first wallet creation **explicit**; never reconstruct a wallet from its passphrase alone.
- Restrict new wallet names to a conservative safe set; check both loaded and on-disk names before writing the Keychain or sending \`createwallet\`.
- Serialize creation within \`WalletManager\` to prevent double-click/duplicate RPC calls.
- Preserve any existing saved passphrase; a same-name retry requires authorized retrieval and exact passphrase match. Never overwrite, delete, or print an existing credential.
- After \`createwallet\`, query the **wallet-scoped** \`getwalletinfo\` and \`getbalances\`; verify the wallet name, \`descriptors=true\`, and that it is actually encrypted (\`unlocked_until\` present), before returning success. Return a recoverable error for ambiguous RPC timeouts, not permission to blindly create another wallet.
- Route new and existing wallet activation through \`AppState\`, refreshing balances and a receive address on success. Offer **Load Existing** inside the create sheet.
- Keep the encryption passphrase separate from a **required encrypted wallet database backup**. The passphrase is not a mnemonic recovery seed; a new wallet with the same passphrase is not a restored wallet.
- No operation may alter existing BTCB2 MainNet chainstate, active node settings, other projects, existing wallet files, or previously stored Keychain items.

## Required native macOS acceptance — every scenario needs evidence

| Scenario | Evidence required |
| --- | --- |
| Fresh install, no wallets | Start node, see "Node running — create an encrypted wallet," continue MainNet sync; no fatal startup state |
| Generate and create new empty wallet | Supply unique name, generate phrase, save to protected Keychain, RPC \`createwallet\`, wallet-scoped \`getwalletinfo\` confirms descriptor/encrypted, UI shows correct wallet and receive address |
| Close/reopen app | Existing wallet loads; balance/address still present; no fresh wallet silently initialized |
| Duplicate name | Existing wallet not overwritten; name collision explained; **Load Existing** works; Keychain credential not replaced |
| RPC unauthorized/unavailable | Distinct actionable error, never claim no wallet or success |
| Keychain prompt denied/canceled/locked | Fail closed, preserve any existing secret, no plain-file fallback and no false creation success |
| Ambiguous RPC timeout | Inspect on-disk and loaded wallet state; never retry \`createwallet\` blindly or lose a passphrase |
| Save to Keychain unchecked | Wallet must still be encrypted; user responsible for separate passphrase and wallet backup |
| Create action twice | Exactly one create RPC, not two operations racing |
| Partial success | UI says which step failed; any newly created wallet is discoverable/loadable without deleting or recreating it |
| Backup/restore | A separate encrypted wallet backup recovers addresses/descriptors; passphrase alone is insufficient |
| Security and compatibility | No secrets in logs/screenshots/GitHub, and no change to existing app bundle ID, Keychain service, or data directory |

## Test policy

\`Tests/NodePocketCoreTests/EncryptedWalletOnboardingTests.swift\` provides a deterministic offline URLSession/JSON-RPC fixture exercising first run, duplicate handling and successful encrypted descriptor creation. **This does not replace native macOS interactive testing**, and it must never use real BTCB2 funds or start TestNet/RegTest.

During the Mac test capture real, **redacted** result codes from Keychain \`SecItemAdd\`/retrieval, Knots \`listwalletdir\`, \`listwallets\`, \`createwallet\`, \`getwalletinfo\` and \`getbalances\`; capture OS and binary version, app commit, PID, data directory inode/ownership, and unchanged chain tip continuity. Never report a passphrase, seed, address, transaction ID, or backup content.

**Do not label the release "wallet working" until the user-visible create-and-load flow is observed on the installed app.** Keep send/broadcast disabled until independent fork-safe signing/fee and per-send authorization gates pass; the general final-release audit remains paused.
