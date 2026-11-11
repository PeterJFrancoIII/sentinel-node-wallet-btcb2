# Sentinel Node Wallet — Complete macOS App Store Connect Submission Packet

**Target owner-supplied ASC record:** [App ID 6833290684](https://appstoreconnect.apple.com/apps/6833290684/distribution/macos/version/inflight)  
**Bundle identifier in source:** `app.nodepocket.btcb2` (must match actual ASC app before upload)  
**Repository:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`; review branch `fix/v13-1-security-remediation-20261107`; [PR #10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10)  
**Current classification:** COPY-READY DRAFT, not evidence of Apple account edits, Xcode uploads, TestFlight approval, App Review approval or publication. Language: English (U.S.).  
**Owner directive:** Deliver via Xcode to the existing Apple Developer/App Store Connect macOS app and fill *all applicable* supporting marketing, review, privacy, legal and distribution fields.

## 1. Verified engineering gap — this is not yet an Xcode Organizer upload

The reviewed repository contains `Package.swift` and `scripts/build_app.sh`, which uses `swift build` to assemble an ad-hoc development `.app`. GitHub's recursive tree at `bda762c` did **not** contain any `.xcodeproj` or `.xcworkspace`. Create or identify a real **archive-capable Xcode macOS App target**, preserving SwiftUI entry point `NodePocketApp`, `NodePocketCore`, icon, resources and signed embedded Knots binaries. Do not conflate successful Swift Package CI with `Product → Archive` or an Apple processing receipt.

**Two Apple distribution channels are not interchangeable.**
- For THIS App Store Connect record, use **Apple Distribution / Mac App Store signing**, the correct platform/profile, App Sandbox and entitlements, Xcode Organizer → **Distribute App → App Store Connect → Upload**. The archive's bundle ID, version and unique build number must match the existing ASC app and version.
- `scripts/build_production_dmg.sh` creates a **Developer ID–signed notarized outside-store DMG** candidate (owner-approved only), not a Mac App Store build. Do not upload that DMG to this App Store Connect version.
- Apple's cryptocurrency-wallet review rule **3.1.5(i)** requires an **Organization developer enrollment**. Earlier Mac inspection reported the team as Individual. Verify CURRENT team/enrollment and any actual Apple review guidance. If still ineligible, do not claim App Store approval or publicly submit the wallet. Upload or prepare only what Apple permits under the actual record/status; report exact blockers and owner action.
- Maintain the hard STOP on outbound signing/broadcast/RBF and destructive wallet deletion until separate independent BTCB2/BIP-110 signature and native GUI recovery acceptance. Do not touch any live operator wallet, production node or unrelated TimeProof/mining projects.

## 2. Copy-ready product-page fields (en-US)

| App Store Connect field | Ready/proposed value | Must verify |
|---|---|---|
| App Apple ID | `6833290684` | From owner link; confirm actual app name/platform in authenticated portal |
| App name | `Sentinel Node Wallet` | 30-character maximum, compare with current record |
| Subtitle | `Bitcoin Knots Node & Wallet` | 30-character maximum; keep honest about disabled sending |
| Primary category | `Finance` | Current account eligibility |
| Secondary category | `Utilities` | Optional |
| Bundle ID | `app.nodepocket.btcb2` | **Exact match** in Xcode and actual ASC app record |
| SKU | Existing ASC SKU; proposal `SENTINEL-NODE-WALLET-BTCB2` | Can't change after app created |
| Copyright | `2026 Peter J. Franco III` | Apple automatically supplies ©; confirm rights holder |
| Pricing | Free (proposed) | Owner pricing approval, tax category and allowed regions |
| Marketing URL | `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2` | Replace with approved product landing page if available |
| Support URL | `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues` | Ensure real contact information and support method satisfy Apple's requirements |
| Privacy Policy URL | `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/blob/main/docs/PRIVACY.md` | Verify anonymous HTTP 200 |
| Version/Build | Existing ASC version and next unique build | Never assume `0.1.0 (1)` from old local scripts matches this in-flight version |
| Release setting | **Manual release after approval** (proposed) | Do not publish automatically |
| Localization | English (U.S.) | Add only reviewed genuine translations |

**Promotional Text (under 170 chars)**

```text
Monitor your local BTCB2 node, wallet balances, peer connections and network hashrate in a native macOS app.
```

**Product Description (plain text, under 4,000 chars)**

```text
Sentinel Node Wallet is a native macOS application for monitoring a local BTCB2 (Bitcoin BLAKE2b/BIP-110) node and associated wallets.

RUN YOUR OWN NODE
Use a bundled Bitcoin Knots daemon configured for the supported network. View blockchain synchronization, peer connections, node health and storage usage. Select resource profiles and monitor pruned blockchain storage.

UNDERSTAND THE NETWORK
Explore estimated network hashrate trends using local consensus data. Follow synchronization status and estimated completion time.

MONITOR YOUR WALLETS
View local wallet inventory, receiving addresses, balances, confirmations and transaction history. Local operator authentication and two-factor authentication help protect access. Wallet passphrases may optionally be stored in macOS Keychain by choice.

LOCAL-FIRST DESIGN
Wallet and node management use loopback RPC on your Mac. Blockchain peers communicate over the network. Optional public market-price queries provide estimated fiat values; remote providers and peers can observe standard network metadata, including your IP address.

CURRENT FUNCTIONAL LIMITATIONS
This version does not enable outgoing transaction signing or broadcasting, fee-bump transactions, or destructive wallet deletion. These functions remain unavailable pending independent security qualification. Use a separate verified solution for spending and recovery-critical operations.

Sentinel Node Wallet does not mine cryptocurrency on the Mac, operate a custodial exchange, or require a hosted wallet account.
```

**Keywords (ASCII, under 100 bytes, comma-delimited)**

```text
btcb2,blake2b,bip110,pruned,hashrate,consensus,peers,blockchain,validation,local,privacy,desktop
```

**What's New** — only when adding an update; not applicable for the first submitted version:

```text
Improved local node controls and configurable performance profiles. Refined local sign-in flows and network monitoring. Stability and security refinements for wallet inventory. Outgoing transactions and wallet deletion remain unavailable pending further qualification.
```

Before pasting What's New, confirm each feature exists in the EXACT shipping build. Do not advertise Apple Passwords autofill, passkeys, audited spend/security or notarization until actually accepted on a signed app.

## 3. App Review information (private portal fields)

**Review contact:** enter the actual owner-approved contact name, email and telephone (international format) in App Store Connect only. Do not add personal phone, passwords or credentials to this public repository.

**Sign-in required:** local operator username/password/TOTP may be created by reviewer in a disposable profile. If Apple requests a stable test account, provision a **non-production demo** and enter its credentials in Apple's private App Review account fields only. Never use a real owner's wallet, TOTP seed or passphrase.

**App Review Notes draft — paste privately after validating against the actual archive:**

```text
Sentinel Node Wallet is a native macOS application for running and monitoring a local BTCB2-compatible Bitcoin Knots node and reviewing local wallet data. It is not a custodial exchange and does not mine cryptocurrency on the Mac.

The app communicates with its local node over loopback RPC and may connect to blockchain peers. Optional read-only market-price requests query Neoxa and NonKYC; peers and price providers can observe normal IP/network metadata. There is no hosted wallet account.

The current release intentionally disables outgoing transaction signing/broadcasting, fee bumping and destructive wallet deletion pending independent security acceptance. These actions are intentionally unavailable.

For review, use a disposable zero-funds profile and the documented local operator setup. No real cryptocurrency is necessary to navigate the Node, Network, authentication or wallet-monitoring screens. Initial full-node synchronization can take considerable time because blockchain data is verified locally.

Please refer to the accompanying private reviewer account/setup information for any necessary local demo credentials, tested macOS versions, and reviewer contact. Do not create or use a funded wallet for testing.
```

Owner-side Mac agent must validate the actual build's onboarding, role/username fields, TOTP setup and reviewer test approach before saving.

## 4. Images, videos and other App Store marketing assets

**Mac screenshots:** Apple allows **1–10** JPG/JPEG/PNG per supported Mac display size; **2880×1800**, 16:10, no alpha, is accepted. Prior Gemini local report says `dist/app_store_screenshots/` contains three original captures:
1. `01_Sentinel_Node_Status_2880x1800.png`
2. `02_Sentinel_Network_Hashrate_2880x1800.png`
3. `03_Sentinel_Wallet_Authentication_2880x1800.png`

Open/visually verify each ORIGINAL file on the authorized Mac, check pixels/ICC/alpha and that the screens match the exact submitted app; remove all real names, addresses, credentials, wallet balances, device IDs and host addresses. Prefer fresh zero-funds demo captures. Optional genuine additional images: Wallet inventory and Advanced settings. **These binaries are not present in GitHub and were not inspected here.** Upload with Product Page Information/Media Manager/Asset Library; confirm all target localizations/size placements.

**App icon:** inspect owner-approved `Resources/AppIcon_1024.png` and `Resources/AppIcon.icns` for correct appearance, size and publisher rights; integrate into Xcode Assets/app target.

**App Preview videos:** optional; up to three genuine landscape Mac preview videos per device/locale if available. Do not invent promotional footage. Use real video with an accurate poster frame or leave optional video blank.

**Conditional optional marketing surfaces:** inventory exact app-permitted options for Custom Product Pages, Product Page Optimization, Asset Library creative/header, featuring nominations and any In-App Events. Fill only those applicable to the actual platform/account; no made-up IAP, events, digital goods or screenshots.

## 5. All other App Store Connect fields — status inventory required

For each field record actual portal status **COMPLETE / NOT APPLICABLE / BLOCKED / UNVERIFIED**, plus screenshot or sanitized audit proof. Do not fake values.

- [ ] App Information: name, subtitle, categories, primary language, age-rating questionnaire, content rights/licenses, agreements and SKU/bundle ID.
- [ ] Version page: app name/localization, description, keywords, promotional text, support/marketing URLs, copyright, screenshot sizes/locales, optional preview, build selection, release control and What's New if updating.
- [ ] App Privacy: public privacy-policy URL, complete data-use and app privacy labeling questionnaire; validate external pricing HTTP and P2P IP metadata against shipped binary. Privacy Choices URL if relevant.
- [ ] App Accessibility labels and support URLs: only verify/claim features actually tested.
- [ ] Pricing/Availability: price, availability regions, tax category, business/education distribution and pre-order only if appropriate. Geographic crypto law/licensing should be reviewed by owner.
- [ ] EU Digital Services Act trader status and any legal/business contact requirements; use actual owner-provided legal status and contact, not guesses.
- [ ] Export compliance/encryption classification: evaluate BTCB2 node, wallet encryption and Apple CryptoKit; do not assume exemption.
- [ ] App Review: valid reachable contact (name/email/phone), privacy-safe local demo workflow, private test credentials if required, notes, financial/cryptocurrency rights/permissions, tested Mac hardware and OS.
- [ ] TestFlight: macOS internal tester availability, test information and export declarations only when Apple-processed build qualifies; external testers and beta review require separate evidence.
- [ ] In-App Purchases, subscriptions, Game Center, App Clips, events, ads and any optional Apple services: **N/A unless the actual app implements them.**
- [ ] Review all Apple's flagged fields on this exact in-flight app record and resolve validation warnings; don't change an already submitted/in-review version blindly.

## 6. Xcode deployment steps and signed acceptance

1. Open authenticated [ASC app ID 6833290684](https://appstoreconnect.apple.com/apps/6833290684/distribution/macos/version/inflight); record the **real** existing app name, bundle ID, macOS version, current state, editability, latest build numbers, owner team and account role. Do not create another app record.
2. Implement or locate the archive-capable native macOS Xcode application project (no `.xcodeproj`/workspace in the reviewed Git tree), mapping SwiftUI executable and `NodePocketCore`. Match the exact bundle ID, real app version and incremented `CFBundleVersion`.
3. For App Store, use **Apple Distribution**, correct Apple Team/profile, App Sandbox, network client/server entitlements, proper node process/data-dir permissions, Keychain and associated-domain requirements. Test actual embedded Knots under App Sandbox; if incompatible, report specific blocking API/entitlement rather than substituting Developer ID DMG.
4. Isolated macOS native tests: signed app first-launch, Keychain/Apple Passwords/TOTP user presence accept/deny/cancel; no `-34018` bypass; disposable GUI encrypted-wallet creation, inventory, backup and isolated Knots restore; daemon RPC/chain/network attestation and pre/post-sign binary provenance. Do not spend funds; keep signing/broadcast/delete held.
5. Xcode **Product → Archive**, Organizer → **Distribute App → App Store Connect → Upload**; capture archive version/build/bundle ID, Apple processing ID and eventual processed build in app **6833290684**. A local build, signed bundle or successful CI is NOT proof of uploaded build.
6. Complete the editable ASC product/marketing/legal/privacy/review fields above using this packet, verify uploads and their localizations, and select manual release. If account is Individual or other App Review gates fail, retain safe staged/build state only and document exact owner action.
7. Deliver receipts: Apple app ID, bundle ID, team, version/build, current ASC status, exact fields updated and screenshot/video counts, Apple build-processing status, Xcode signing details, Git SHA/CI evidence, permission/organization status and remaining P0 blockers. No secrets in receipts.

## 7. Official Apple references

- [Required & localized fields](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)
- [Version metadata and reviewer notes](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Xcode/App Store Connect builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Mac screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Manage app assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets)
- [Crypto-wallet review guideline](https://developer.apple.com/app-store/review/guidelines/)
- [Submit app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)

**Critical operating rule:** This packet stages verifiable public-facing copy. It is **not** a successful upload, a TestFlight release, a submitted app or a production authorization.
