# Privacy Policy — Sentinel Node Wallet

**Effective date:** November 11, 2026 · **Last revised:** November 14, 2026  
**App Store record:** `6833290684` · **Current release bundle identifier:** `pool.sentineldefensetechnologies.co.za`  
**Current GitHub release:** [v1.0.0 Build 3](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build3)

This policy describes the intended data handling and externally observable connections of Sentinel Node Wallet, a native macOS BTCB2 node and self-custodial wallet. It supersedes earlier bundle-identity and send/delete descriptions. App Store privacy labels should be independently verified against the **exact shipped binary**, not inferred solely from source comments.

## Local accounts and wallet records

- The app provides local operator accounts. Password verifier/metadata records, encrypted wallet databases, receive addresses, transaction history, configuration and node blockchain state reside in app-managed local storage rather than a hosted Sentinel wallet account.
- macOS Keychain may store selected credential material such as locally protected TOTP secrets, operator credentials and optional wallet passphrases. Touch ID / macOS user presence is used for supported operations according to local OS policy. Do not assume every Keychain item is always Secure Enclave-backed, cloud-sync-disabled or equivalent to Apple's separate Passwords app.
- Backup files created or exported by users can be copied outside the app's container. Their availability, encryption and deletion depend on the location selected and the user's backup management.

## Network communications

- **Local node RPC:** Embedded Bitcoin Knots communicates with the application through authenticated HTTP JSON-RPC bound to `127.0.0.1` (default port 8332); a local listening socket receives those requests.
- **Blockchain peers:** The Knots daemon initiates peer-to-peer blockchain connections, and may accept user-enabled inbound P2P. Remote peers can observe the client's IP address, protocol metadata and connection timing. Decentralized public blockchain transactions and addresses may also be visible on chain.
- **Optional fiat-value quotes:** The app uses public, read-only HTTPS GET requests to `https://neoxa.exchange/api/exchange/ticker/BTCB2_USDC` and `https://api.nonkyc.io/api/v2/ticker/BTCB2_USDT`. These requests do not intentionally include wallet balances, addresses, password material or transaction history. Price-provider servers can observe normal internet metadata such as IP address, headers and request timing.
- Neither a local RPC binding nor the absence of an analytics SDK guarantees complete anonymity. Users should consult the relevant peers' and pricing providers' policies for their independent processing.

## Analytics, cloud services and advertising

The current source does not implement an operator-hosted cloud wallet account, an advertising SDK or a dedicated analytics/telemetry collection backend. This is a statement about the inspected source design, **not** a guarantee against operating-system logs, third-party network metadata, public-chain visibility, connected services or future versions. The developer should reassess Apple's App Privacy questionnaire whenever data flows change.

## Wallet transactions and deletion

- The current node/RPC interface defaults to broadcast-restricted mode and rejects selected send/sign/RBF methods while restricted. Code contains conditional outbound transaction paths if the restriction is deliberately disabled; independently reviewed BTCB2 signing safety is not established by this policy.
- **Individual-wallet Delete** in current source fails pending independent isolated wallet-recovery verification, while nondestructive Archive is implemented.
- A separate **Full Uninstallation / storage-wipe** feature and standalone uninstall script can delete the app's local blockchain data **including wallet databases and user records**. This can be irreversible. Users should verify independent encrypted wallet backups and recovery before using this option, and should not assume that uninstall removes data from backups, other volumes or third-party network records.

## Security and choices

The user controls local wallet creation, optional Keychain storage, peer settings and outgoing pricing requests where exposed in app settings. Device compromise, lost passphrases and unsafe disposal of backup files can cause loss of access or assets. Do not treat this policy as a guarantee of financial security, independent code auditing or Apple notarization.

## Contact and support

- [Support and issue reporting](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues)
- [Project information](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)
- [Security policy](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/blob/main/SECURITY.md)

The privacy policy may be revised as supported app features, independently verified data flows and distribution requirements change.
