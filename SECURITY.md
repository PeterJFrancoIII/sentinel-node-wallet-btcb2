# Security Policy — Sentinel Node Wallet BTCB2

**Development only; no public release, production deployment or real funds.** Report vulnerabilities privately through the repository's security-advisory channel or a verified maintainer, without exposing exploits, credentials or user data. [Current threat/acceptance register](docs/PROJECT_STATUS.md).

## Boundaries

- BTCB2 BLAKE2b/BIP-110 MainNet-only, authenticated loopback RPC, verified Knots daemon, owned datadir/configuration and pinned fork/chain anchors; no unrelated runtime coupling, wallet cloud sync or remote RPC.
- Encrypted descriptor wallets and explicitly authorized local multi-user login (password + TOTP + recovery). Enforce authentication and high-risk device-owner approval **in core**, not only UI. Never silently weaken failed Keychain entitlements or user-presence enforcement.
- Preserve wallets, secrets, backup identity, metadata and chainstate. Backup before reversible Trash deletion; fail closed on nonzero/unknown balance, mismatch, non-durable backup, cancellation or restore uncertainty.
- Core send/broadcast stays disabled until independent BTCB2 SIGHASH_UNIFIED replay-safe signing, integer-satoshi fees, trusted-recipient/PSBT binding, one-use approval and locked-after-action semantics are proven.
- Apple Passwords requires owner-approved HTTPS webcredentials + AASA, actual Team ID/bundle ID and signed app; a generic app Keychain item is **not** an Apple Passwords login. Do not claim secure two-factor behavior without hardware acceptance. A compromised user session/OS can defeat a software hot wallet.

## Open security findings (fail-release)

1. **P0 native acceptance still open** Requested Keychain save failure, duplicate mismatch and canceled user presence now block createwallet **in source and CI** at 5e7a597 (five deterministic regressions passed). Verify behavior on an actually signed Mac, explicit offline-custody acknowledgment, and durable passphrase recovery before declaring the risk closed.
2. **P0** Installed-app encrypted wallet creation, inventory after create, network-loss retry, isolated backup/restore and Keychain interactive consent not independently demonstrated.
3. **P0** Adopted-daemon PID/executable and authenticated RPC listener are checked independently; credential file existence/owner is insufficient for contents, symlink/type/mode or endpoint binding. Positive auth-mode tests missing.
4. **P0** Independent signing/fork-binary provenance, backup-durability recovery, notarization and supply-chain review incomplete.
5. **P1** Native window lifecycle has incomplete zero-window fallback and unsafe force-unwrap selector.

**Release:** independent native Mac tests; no-loss wallet recovery; Apple Passwords consent; fork signature/Knots provenance; signed embedded binary + Developer ID app, notarized/stapled DMG, Gatekeeper and verified update chain. All P0s must pass with reproducible evidence. [Matrix](TEST_AND_RELEASE_MATRIX.md) · [Audit protocol](docs/FINAL_PRODUCTION_SECURITY_AUDIT_V13.md).
