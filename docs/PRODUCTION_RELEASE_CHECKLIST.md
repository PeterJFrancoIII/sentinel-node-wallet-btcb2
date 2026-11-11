# Owner-controlled production signing and notarization checklist

**Release status: NO-GO** until an independent reviewer approves all P0 items. Building a native executable does not qualify the wallet for custody, deletion, signing or funds sending.

## Verified automated build foundation

GitHub Actions #42938948275 at source SHA 2aa0e15 completed **SUCCESS: 133 executed / 132 passed / 0 failed / one interactive Keychain skip; optimized Release-mode SwiftUI NodePocketApp compile PASS; all packaging script syntax checks PASS**. This is source/CI qualification only. The packaged app, embedded Knots provenance, Apple Passwords saving, real Keychain presence prompts, wallet recovery, Gatekeeper and notarization require separate evidence.

Wallet Send and RBF remain disabled. Destructive wallet deletion is also blocked until a separately verified encrypted-wallet restore has been completed on an isolated Knots daemon. Use Archive instead. Never test against live operator wallet files, real Keychain items, datadir, IBD or chainstate.

## Release prerequisites

- Owner-managed Apple Developer Program team and installed Developer ID Application certificate, with validated Team ID.
- Owner-approved standalone HTTPS Apple Passwords webcredentials domain serving an AASA file with webcredentials.apps containing the exact TEAMID.app.nodepocket.btcb2 application identifier. The AASA host must never receive wallet data, passwords or TOTP secrets.
- Apple notarization credentials stored on the authorized Mac via xcrun notarytool store-credentials, not in Git or plaintext build logs.
- Independent binary provenance audit of the embedded BTCB2-compatible Knots fork, including publisher authenticity, BTCB2/BIP-110 compatibility and exact binary hashes.
- Signed native macOS tests of password/TOTP user consent (including -34018, cancel and denial), wallet creation and restoring an encrypted zero-funds descriptor wallet using a dedicated temporary datadir.
- Positive/negative RPC daemon PID/executable/datadir binding; authorized Ultra battery/charging transitions; UI/window and complete release security/supply-chain review; independent wallet transaction-signing audit before ever enabling Send.
- Explicit external approval before setting SENTINEL_RELEASE_SECURITY_APPROVED=1. This is a manual approval assertion; the environment variable by itself is not security certification.

## Owner-run build command (after all prerequisites)

On the authorized macOS host, set the environment values locally without copying credentials, IDs or keys into chat/Git:

    export SENTINEL_RELEASE_SECURITY_APPROVED=1
    export SENTINEL_DEVELOPER_ID_APPLICATION="Developer ID Application: <owner identity>"
    export SENTINEL_APPLE_TEAM_ID="<approved 10-character Team ID>"
    export SENTINEL_WEBCREDENTIALS_DOMAIN="<approved HTTPS domain without scheme>"
    export SENTINEL_NOTARY_PROFILE="<existing local Keychain notarytool profile>"
    bash scripts/build_production_dmg.sh

The guarded script validates public HTTPS AASA association, builds the pinned Knots bundle, applies hardened-runtime Developer ID signing to the app and embedded daemon/tools, verifies signed Team ID and entitlements, refreshes final signed-file SHA-256 hashes, notarizes the DMG with notarytool, staples/validates the ticket and records the DMG checksum. It does not publish a GitHub release, restart a node or install software on a user's Mac.

On a clean Gatekeeper-enabled Mac, verify actual installed behavior and independent audit results before the production GO decision. App notarization is necessary but not sufficient to declare BTCB2 wallet security.

Apple official workflow: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
