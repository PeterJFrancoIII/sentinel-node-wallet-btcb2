#!/usr/bin/env python3
"""Fail-closed verifier and staging normalizer for Sentinel Node Wallet production macOS bundles.

Verifies Apple Developer ID provisioning profile authenticity (CMS trust against macOS
SystemRootCertificates), validates team/prefix/bundle/cert/entitlement bindings, normalizes
and audits distributable app bundle file modes without mutating secrets or production installs,
and cross-checks final signed Mach-O entitlements against the embedded provisioning profile.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from typing import Any


MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",  # MH_MAGIC
    b"\xce\xfa\xed\xfe",  # MH_CIGAM
    b"\xfe\xed\xfa\xcf",  # MH_MAGIC_64
    b"\xcf\xfa\xed\xfe",  # MH_CIGAM_64
    b"\xca\xfe\xba\xbe",  # FAT_MAGIC
    b"\xbe\xba\xfe\xca",  # FAT_CIGAM
}

RESOURCE_NON_EXECUTABLE_SUFFIXES = {
    ".plist",
    ".provisionprofile",
    ".strings",
    ".nib",
    ".icns",
    ".json",
    ".css",
    ".h",
    ".modulemap",
    ".png",
    ".md",
    ".txt",
}

RESTRICTED_ENTITLEMENT_KEYS = {
    "com.apple.application-identifier",
    "application-identifier",
    "com.apple.developer.team-identifier",
    "com.apple.developer.associated-domains",
    "keychain-access-groups",
    "com.apple.security.application-groups",
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.ubiquity-kvstore-identifier",
}

DEBUG_ENTITLEMENT_KEYS = (
    "get-task-allow",
    "com.apple.security.get-task-allow",
)

APPLE_ROOT_ORG_RE = re.compile(r"O\s*=\s*Apple(\s+Inc\.|\s+Computer,\s*Inc\.)", re.IGNORECASE)


def _normalize_sha256_hex(digest: str, label: str) -> str:
    cleaned = str(digest or "").strip()
    if not re.match(r"^[0-9A-Fa-f]{64}$", cleaned):
        raise VerificationError(f"{label} must be a 64-character hex SHA-256 digest (got '{cleaned}').")
    return cleaned.lower()


def _assert_no_debug_entitlements(entitlements: dict[str, Any], context: str) -> None:
    for key in DEBUG_ENTITLEMENT_KEYS:
        if key in entitlements and entitlements[key] is not False:
            raise VerificationError(
                f"Debug entitlement '{key}={entitlements[key]}' is strictly forbidden in production ({context})."
            )


class VerificationError(Exception):
    """Raised when a bundle, profile, permission, or signature invariant fails."""


def fail(msg: str) -> None:
    print(f"RELEASE VERIFICATION BLOCKED: {msg}", file=sys.stderr)
    raise SystemExit(1)


def is_macho_file(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            head = f.read(4)
        return len(head) == 4 and head in MACHO_MAGICS
    except OSError:
        return False


def to_utc(dt: datetime.datetime) -> datetime.datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def export_apple_root_cas(roots_pem_path: str) -> int:
    keychain = "/System/Library/Keychains/SystemRootCertificates.keychain"
    res = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple", "-p", keychain],
        capture_output=True,
    )
    if res.returncode != 0 or not res.stdout:
        raise VerificationError(
            f"Unable to export Apple Root CAs from SystemRootCertificates ({res.returncode}): {res.stderr.decode(errors='replace')}"
        )
    raw = res.stdout.decode("utf-8", errors="replace")
    apple_blocks: list[bytes] = []
    for chunk in raw.split("-----BEGIN CERTIFICATE-----")[1:]:
        pem = ("-----BEGIN CERTIFICATE-----" + chunk).encode("utf-8")
        info = subprocess.run(
            ["openssl", "x509", "-noout", "-subject"],
            input=pem,
            capture_output=True,
        )
        if info.returncode == 0 and APPLE_ROOT_ORG_RE.search(info.stdout.decode(errors="replace")):
            apple_blocks.append(pem)
    if not apple_blocks:
        raise VerificationError("No genuine Apple Root CA certificates found in SystemRootCertificates.")
    with open(roots_pem_path, "wb") as f:
        f.write(b"".join(apple_blocks))
    return len(apple_blocks)


def _verify_apple_profile_cms_signer(signer_pem_path: str) -> None:
    if not os.path.isfile(signer_pem_path):
        raise VerificationError("CMS verification produced no Apple signer certificate.")
    res = subprocess.run(
        ["openssl", "x509", "-in", signer_pem_path, "-noout", "-subject", "-issuer"],
        capture_output=True,
    )
    if res.returncode != 0:
        raise VerificationError(
            f"Unable to inspect provisioning profile CMS signer certificate: {res.stderr.decode(errors='replace').strip()}"
        )
    text = res.stdout.decode("utf-8", errors="replace")
    subj_line = ""
    issuer_line = ""
    for line in text.splitlines():
        if line.startswith("subject="):
            subj_line = line
        elif line.startswith("issuer="):
            issuer_line = line
    if not APPLE_ROOT_ORG_RE.search(subj_line) or "Apple" not in subj_line:
        raise VerificationError(
            f"Provisioning profile CMS signer is NOT an Apple organization certificate ({subj_line.strip()})."
        )
    if not APPLE_ROOT_ORG_RE.search(issuer_line):
        raise VerificationError(
            f"Provisioning profile CMS signer issuer is NOT an Apple CA ({issuer_line.strip()})."
        )


def verify_profile_cms(
    profile_path: str,
    out_plist_path: str,
    expected_profile_sha256: str | None = None,
) -> None:
    if not os.path.isfile(profile_path) or os.path.islink(profile_path):
        raise VerificationError(f"Provisioning profile missing or is a symlink: {profile_path}")

    if expected_profile_sha256:
        expected_hex = _normalize_sha256_hex(expected_profile_sha256, "expected-profile-sha256")
        with open(profile_path, "rb") as pf:
            actual_hex = hashlib.sha256(pf.read()).hexdigest().lower()
        if actual_hex != expected_hex:
            raise VerificationError(
                f"Provisioning profile SHA-256 ({actual_hex}) does not match expected pinned digest ({expected_hex})."
            )

    with tempfile.TemporaryDirectory() as td:
        os.chmod(td, 0o700)
        roots_pem = os.path.join(td, "apple_roots.pem")
        signer_pem = os.path.join(td, "cms_signer.pem")
        export_apple_root_cas(roots_pem)

        cms_verify = subprocess.run(
            [
                "openssl",
                "cms",
                "-verify",
                "-inform",
                "DER",
                "-in",
                profile_path,
                "-CAfile",
                roots_pem,
                "-signer",
                signer_pem,
                "-out",
                out_plist_path,
            ],
            capture_output=True,
        )
        if cms_verify.returncode != 0:
            err = cms_verify.stderr.decode(errors="replace").strip()
            raise VerificationError(f"Apple CMS authenticity verification failed for provisioning profile: {err}")

        _verify_apple_profile_cms_signer(signer_pem)

        sec_cms = subprocess.run(
            ["security", "cms", "-D", "-h", "0", "-i", profile_path],
            capture_output=True,
        )
        if sec_cms.returncode != 0:
            err = sec_cms.stderr.decode(errors="replace").strip()
            raise VerificationError(f"macOS security cms validation failed for provisioning profile: {err}")

    try:
        with open(out_plist_path, "rb") as f:
            pl = plistlib.load(f)
        if not isinstance(pl, dict):
            raise VerificationError("Decoded provisioning profile payload is not a plist dictionary.")
    except Exception as exc:
        raise VerificationError(f"Failed to parse verified provisioning profile plist: {exc}") from exc


def match_prefix_wildcard(allowed: Any, claimed: str, required_prefix: str) -> bool:
    """Validates an identifier/group claim against an Apple profile allowlist with strict prefix enforcement."""
    if not claimed.startswith(required_prefix + "."):
        return False
    allowed_list = [allowed] if isinstance(allowed, str) else list(allowed) if isinstance(allowed, list) else []
    for pattern in allowed_list:
        if not isinstance(pattern, str):
            continue
        if pattern == claimed:
            return True
        if pattern == f"{required_prefix}.*":
            return True
        if pattern.endswith(".*") and pattern.startswith(required_prefix + "."):
            base = pattern[:-1]  # includes trailing dot
            if claimed.startswith(base):
                return True
    return False


def match_associated_domain(allowed: Any, claimed_domain_entry: str) -> bool:
    """Validates a claimed webcredentials:<host> entry against profile com.apple.developer.associated-domains."""
    if ":" not in claimed_domain_entry:
        return False
    service, host = claimed_domain_entry.split(":", 1)
    if not service or not host:
        return False
    if allowed == "*":
        return True
    allowed_list = [allowed] if isinstance(allowed, str) else list(allowed) if isinstance(allowed, list) else []
    for pattern in allowed_list:
        if not isinstance(pattern, str):
            continue
        if pattern == "*" or pattern == claimed_domain_entry or pattern == f"{service}:*":
            return True
        if pattern.startswith(f"{service}:*.") and host.endswith(pattern[len(f"{service}:*") :]):
            # e.g. webcredentials:*.example.com matches foo.example.com (must have subdomain prefix)
            if len(host) > len(pattern[len(f"{service}:*") :]):
                return True
    return False


def validate_profile_plist(
    plist_path: str,
    team_id: str,
    bundle_id: str,
    domain: str,
    cert_sha256: str,
    raw_profile_path: str | None = None,
    expected_profile_sha256: str | None = None,
) -> dict[str, Any]:
    if not os.path.isfile(plist_path) or os.path.islink(plist_path):
        raise VerificationError(f"Profile plist missing or invalid: {plist_path}")
    if not re.match(r"^[A-Z0-9]{10}$", team_id):
        raise VerificationError(f"Invalid Apple Team ID format: {team_id}")
    if not re.match(r"^[0-9A-Fa-f]{64}$", cert_sha256):
        raise VerificationError("Signing certificate SHA-256 must be a 64-char hex digest.")
    expected_cert_sha = cert_sha256.upper()

    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    if not isinstance(pl, dict):
        raise VerificationError("Provisioning profile plist root must be a dictionary.")

    prof_uuid = str(pl.get("UUID") or "").strip()
    prof_name = str(pl.get("Name") or "").strip()
    if not prof_uuid or not re.match(r"^[0-9A-Fa-f-]{36}$", prof_uuid):
        raise VerificationError(f"Provisioning profile has missing or malformed UUID: '{prof_uuid}'")
    if not prof_name:
        raise VerificationError("Provisioning profile has missing Name.")

    now = datetime.datetime.now(datetime.timezone.utc)
    exp = pl.get("ExpirationDate")
    if not isinstance(exp, datetime.datetime):
        raise VerificationError("Provisioning profile missing valid ExpirationDate.")
    exp_utc = to_utc(exp)
    if exp_utc <= now:
        raise VerificationError(f"Provisioning profile '{prof_uuid}' is expired ({exp_utc.isoformat()}).")

    created = pl.get("CreationDate")
    if isinstance(created, datetime.datetime):
        if to_utc(created) > now + datetime.timedelta(minutes=5):
            raise VerificationError("Provisioning profile CreationDate is unexpectedly far in the future.")

    platforms = pl.get("Platform")
    if not isinstance(platforms, list) or not any(p in ("OSX", "macOS") for p in platforms):
        raise VerificationError(f"Provisioning profile Platform does not support macOS (OSX): {platforms}")

    provisioned_devices = pl.get("ProvisionedDevices")
    if provisioned_devices:
        raise VerificationError(
            "Provisioning profile restricts ProvisionedDevices (development/ad-hoc); MAC_APP_DIRECT distribution profile required."
        )
    if pl.get("ProvisionsAllDevices") is not True:
        raise VerificationError(
            f"Provisioning profile must have ProvisionsAllDevices=true for global Developer ID distribution (got {pl.get('ProvisionsAllDevices')})."
        )

    teams = pl.get("TeamIdentifier")
    if not isinstance(teams, list) or team_id not in teams:
        raise VerificationError(f"Provisioning profile TeamIdentifier {teams} does not match expected team '{team_id}'.")

    prefixes = pl.get("ApplicationIdentifierPrefix")
    if not isinstance(prefixes, list) or not prefixes or not all(isinstance(x, str) and re.match(r"^[A-Z0-9]{10}$", x) for x in prefixes):
        raise VerificationError(f"Provisioning profile missing valid ApplicationIdentifierPrefix: {prefixes}")
    app_id_prefix = prefixes[0]
    if app_id_prefix != team_id:
        raise VerificationError(
            f"ApplicationIdentifierPrefix '{app_id_prefix}' differs from TeamIdentifier '{team_id}'; manual prefix migration verification required."
        )

    entitlements = pl.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise VerificationError("Provisioning profile missing Entitlements dictionary.")

    _assert_no_debug_entitlements(entitlements, "provisioning profile")

    ent_team = entitlements.get("com.apple.developer.team-identifier")
    if ent_team is not None and ent_team != team_id:
        raise VerificationError(
            f"Profile com.apple.developer.team-identifier '{ent_team}' mismatches expected team '{team_id}'."
        )

    expected_app_id = f"{app_id_prefix}.{bundle_id}"
    allowed_app_id = entitlements.get("com.apple.application-identifier") or entitlements.get("application-identifier")
    if not allowed_app_id or not match_prefix_wildcard(allowed_app_id, expected_app_id, app_id_prefix):
        raise VerificationError(
            f"Profile com.apple.application-identifier '{allowed_app_id}' does not authorize '{expected_app_id}'."
        )

    allowed_domains = entitlements.get("com.apple.developer.associated-domains")
    required_domain_entry = f"webcredentials:{domain}"
    if not allowed_domains or not match_associated_domain(allowed_domains, required_domain_entry):
        raise VerificationError(
            f"Profile com.apple.developer.associated-domains '{allowed_domains}' does not authorize '{required_domain_entry}'."
        )

    allowed_keychain = entitlements.get("keychain-access-groups")
    if not allowed_keychain or not match_prefix_wildcard(allowed_keychain, expected_app_id, app_id_prefix):
        raise VerificationError(
            f"Profile keychain-access-groups '{allowed_keychain}' does not authorize '{expected_app_id}' with prefix '{app_id_prefix}'."
        )

    dev_certs = pl.get("DeveloperCertificates")
    if not isinstance(dev_certs, list) or not dev_certs:
        raise VerificationError("Provisioning profile contains no DeveloperCertificates.")
    cert_fps = []
    for raw_cert in dev_certs:
        if isinstance(raw_cert, (bytes, bytearray)):
            cert_fps.append(hashlib.sha256(raw_cert).hexdigest().upper())
    if expected_cert_sha not in cert_fps:
        raise VerificationError(
            f"Active signing certificate fingerprint ({expected_cert_sha}) is NOT authorized in profile DeveloperCertificates ({cert_fps})."
        )

    profile_sha256 = None
    if raw_profile_path and os.path.isfile(raw_profile_path):
        with open(raw_profile_path, "rb") as rf:
            profile_sha256 = hashlib.sha256(rf.read()).hexdigest()
    if expected_profile_sha256:
        pinned_hex = _normalize_sha256_hex(expected_profile_sha256, "expected-profile-sha256")
        if not profile_sha256:
            raise VerificationError(
                "expected-profile-sha256 was requested without a readable --raw-profile path."
            )
        if profile_sha256.lower() != pinned_hex:
            raise VerificationError(
                f"Provisioning profile SHA-256 ({profile_sha256.lower()}) does not match expected pinned digest ({pinned_hex})."
            )

    return {
        "uuid": prof_uuid,
        "name": prof_name,
        "expiration_iso": exp_utc.isoformat(),
        "team_id": team_id,
        "app_id_prefix": app_id_prefix,
        "bundle_id": bundle_id,
        "expected_app_id": expected_app_id,
        "cert_sha256": expected_cert_sha,
        "profile_sha256": profile_sha256,
    }


def _expected_file_mode(rel_path: str, full_path: str) -> int:
    name = os.path.basename(rel_path)
    _, ext = os.path.splitext(name)
    ext_lower = ext.lower()
    norm_rel = rel_path.replace(os.sep, "/")

    is_macho = is_macho_file(full_path)
    if ext_lower in RESOURCE_NON_EXECUTABLE_SUFFIXES or name in {"PkgInfo", "CodeResources"}:
        if is_macho:
            raise VerificationError(f"Resource file unexpectedly contains Mach-O executable magic: {rel_path}")
        return 0o644

    # Known executable / framework dynamic library slots
    in_macos_dir = "/Contents/MacOS/" in f"/{norm_rel}" and os.path.basename(os.path.dirname(full_path)) == "MacOS"
    is_framework_dylib = bool(re.match(r"^Contents/Frameworks/([^/]+)\.framework/Versions/[^/]+/\1$", norm_rel))
    is_autoupdate_helper = norm_rel.endswith(".framework/Versions/B/Autoupdate") or norm_rel.endswith(".framework/Versions/A/Autoupdate")

    if is_macho:
        if not (in_macos_dir or is_framework_dylib or is_autoupdate_helper):
            raise VerificationError(f"Mach-O executable located outside authorized executable/framework slot: {rel_path}")
        return 0o755

    if in_macos_dir:
        raise VerificationError(f"File in Contents/MacOS is not a valid Mach-O binary: {rel_path}")

    return 0o644


def normalize_and_audit_permissions(
    app_path: str,
    audit_only: bool,
    require_profile: bool,
    expected_profile_sha256: str | None,
) -> None:
    if not os.path.isdir(app_path) or os.path.islink(app_path) or not app_path.endswith(".app"):
        raise VerificationError(f"App bundle must be a real directory ending in .app: {app_path}")

    real_app = os.path.realpath(app_path)

    # Check outer root permission as well
    root_st = os.lstat(app_path)
    if not audit_only:
        os.chmod(app_path, 0o755)
        root_st = os.lstat(app_path)
    root_mode = stat.S_IMODE(root_st.st_mode)
    if root_mode != 0o755:
        raise VerificationError(f"Unsafe mode {oct(root_mode)} on root bundle {app_path} (expected 0o755).")

    for dirpath, dirnames, filenames in os.walk(app_path, topdown=True, followlinks=False):
        # Validate and process subdirectories (including symlinks that look like dirs)
        real_dirs_to_descend = []
        for d in sorted(dirnames):
            full = os.path.join(dirpath, d)
            st = os.lstat(full)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(full)
                if os.path.isabs(target):
                    raise VerificationError(f"Absolute symlink forbidden inside bundle: {full} -> {target}")
                resolved = os.path.realpath(full)
                if resolved != real_app and not resolved.startswith(real_app + os.sep):
                    raise VerificationError(f"Escaping symlink inside bundle: {full} -> {target}")
                continue

            if not audit_only:
                os.chmod(full, 0o755)
                st = os.lstat(full)
            mode = stat.S_IMODE(st.st_mode)
            if mode != 0o755:
                rel = os.path.relpath(full, app_path)
                raise VerificationError(f"Unsafe directory mode {oct(mode)} at '{rel}' (expected 0o755).")
            real_dirs_to_descend.append(d)

        # Prevent os.walk from descending through symlinked directories
        dirnames[:] = real_dirs_to_descend

        for fn in sorted(filenames):
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, app_path)
            st = os.lstat(full)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(full)
                if os.path.isabs(target):
                    raise VerificationError(f"Absolute symlink forbidden inside bundle: {rel} -> {target}")
                resolved = os.path.realpath(full)
                if resolved != real_app and not resolved.startswith(real_app + os.sep):
                    raise VerificationError(f"Escaping symlink inside bundle: {rel} -> {target}")
                continue
            if not stat.S_ISREG(st.st_mode):
                raise VerificationError(f"Unexpected non-regular file inside bundle: {rel}")

            expected_mode = _expected_file_mode(rel, full)
            if not audit_only:
                os.chmod(full, expected_mode)
                st = os.lstat(full)

            actual_mode = stat.S_IMODE(st.st_mode)
            if actual_mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
                raise VerificationError(f"Special mode bits forbidden on '{rel}': {oct(actual_mode)}")
            if actual_mode & (stat.S_IWGRP | stat.S_IWOTH):
                raise VerificationError(f"Group/world write bits forbidden on '{rel}': {oct(actual_mode)}")
            if actual_mode != expected_mode:
                raise VerificationError(
                    f"Incorrect file mode {oct(actual_mode)} on '{rel}' (expected {oct(expected_mode)})."
                )

    # Verify Sparkle framework symlink preservation if embedded
    sparkle_fw = os.path.join(app_path, "Contents", "Frameworks", "Sparkle.framework")
    if os.path.exists(sparkle_fw):
        cur_link = os.path.join(sparkle_fw, "Versions", "Current")
        root_bin_link = os.path.join(sparkle_fw, "Sparkle")
        if not os.path.islink(cur_link) or not os.path.islink(root_bin_link):
            raise VerificationError("Sparkle.framework symlinks (Versions/Current or Sparkle) were flattened or missing.")

    # Required binary checks
    main_bin = os.path.join(app_path, "Contents", "MacOS", "SentinelNodeWallet")
    if not os.path.isfile(main_bin) or os.path.islink(main_bin):
        raise VerificationError("Main binary Contents/MacOS/SentinelNodeWallet missing or is a symlink.")
    if stat.S_IMODE(os.lstat(main_bin).st_mode) != 0o755:
        raise VerificationError("Main binary Contents/MacOS/SentinelNodeWallet does not have 0o755 mode.")

    # Provisioning profile presence and mode checks
    emb_prof = os.path.join(app_path, "Contents", "embedded.provisionprofile")
    if require_profile:
        if not os.path.isfile(emb_prof) or os.path.islink(emb_prof):
            raise VerificationError("Missing Contents/embedded.provisionprofile (or is a symlink).")
        emb_mode = stat.S_IMODE(os.lstat(emb_prof).st_mode)
        if emb_mode != 0o644:
            raise VerificationError(f"Contents/embedded.provisionprofile mode must be 0o644 (got {oct(emb_mode)}).")
        if expected_profile_sha256:
            with open(emb_prof, "rb") as pf:
                actual_sha = hashlib.sha256(pf.read()).hexdigest().lower()
            if actual_sha != expected_profile_sha256.lower():
                raise VerificationError(
                    f"Embedded provisioning profile SHA-256 ({actual_sha}) != expected ({expected_profile_sha256.lower()})."
                )


def verify_entitlements_against_profile(
    profile_plist: dict[str, Any],
    signed_entitlements: dict[str, Any],
    team_id: str,
    bundle_id: str,
    domain: str,
) -> None:
    prefixes = profile_plist.get("ApplicationIdentifierPrefix") or []
    if not isinstance(prefixes, list) or not prefixes:
        raise VerificationError("Profile missing ApplicationIdentifierPrefix.")
    prefix = prefixes[0]
    prof_ents = profile_plist.get("Entitlements") or {}
    if not isinstance(prof_ents, dict):
        raise VerificationError("Profile missing Entitlements dictionary.")

    expected_app_id = f"{prefix}.{bundle_id}"
    expected_domain = f"webcredentials:{domain}"

    _assert_no_debug_entitlements(prof_ents, "provisioning profile")
    _assert_no_debug_entitlements(signed_entitlements, "signed bundle entitlements")

    # Verify required claims exist in final signed binary
    if signed_entitlements.get("com.apple.application-identifier") != expected_app_id:
        raise VerificationError(
            f"Signed entitlement com.apple.application-identifier '{signed_entitlements.get('com.apple.application-identifier')}' != '{expected_app_id}'."
        )
    if signed_entitlements.get("com.apple.developer.team-identifier") != team_id:
        raise VerificationError(
            f"Signed entitlement com.apple.developer.team-identifier '{signed_entitlements.get('com.apple.developer.team-identifier')}' != '{team_id}'."
        )
    signed_domains = signed_entitlements.get("com.apple.developer.associated-domains")
    if not isinstance(signed_domains, list) or expected_domain not in signed_domains:
        raise VerificationError(
            f"Signed entitlement com.apple.developer.associated-domains '{signed_domains}' missing '{expected_domain}'."
        )
    signed_keychains = signed_entitlements.get("keychain-access-groups")
    if not isinstance(signed_keychains, list) or expected_app_id not in signed_keychains:
        raise VerificationError(
            f"Signed entitlement keychain-access-groups '{signed_keychains}' missing '{expected_app_id}'."
        )

    # Verify EVERY restricted entitlement claimed by the signed app is allowed by profile Entitlements
    for key, val in signed_entitlements.items():
        if key not in RESTRICTED_ENTITLEMENT_KEYS:
            continue
        if key not in prof_ents:
            raise VerificationError(f"Signed bundle claims restricted entitlement '{key}' absent from provisioning profile.")
        prof_val = prof_ents[key]
        if key in ("com.apple.application-identifier", "application-identifier"):
            if not isinstance(val, str) or not match_prefix_wildcard(prof_val, val, prefix):
                raise VerificationError(f"Claimed {key}='{val}' not permitted by profile '{prof_val}'.")
        elif key == "com.apple.developer.team-identifier":
            if val != prof_val or val != team_id:
                raise VerificationError(f"Claimed team-identifier '{val}' mismatches profile '{prof_val}'.")
        elif key == "com.apple.developer.associated-domains":
            if not isinstance(val, list) or not all(isinstance(d, str) and match_associated_domain(prof_val, d) for d in val):
                raise VerificationError(f"Claimed associated-domains {val} not permitted by profile {prof_val}.")
        elif key == "keychain-access-groups":
            if not isinstance(val, list) or not all(isinstance(g, str) and match_prefix_wildcard(prof_val, g, prefix) for g in val):
                raise VerificationError(f"Claimed keychain-access-groups {val} not permitted by profile {prof_val}.")
        else:
            if prof_val != val and prof_val != "*":
                raise VerificationError(f"Claimed restricted entitlement {key}='{val}' not permitted by profile '{prof_val}'.")


def _extract_codesign_entitlements_plist(binary_or_app_path: str) -> dict[str, Any]:
    res = subprocess.run(
        ["codesign", "--display", "--entitlements", "-", "--xml", binary_or_app_path],
        capture_output=True,
    )
    if res.returncode != 0:
        raise VerificationError(
            f"codesign --display --entitlements failed for {binary_or_app_path}: {res.stderr.decode(errors='replace')}"
        )
    if not res.stdout.strip():
        return {}
    data = plistlib.loads(res.stdout)
    if not isinstance(data, dict):
        raise VerificationError(f"Signed entitlements for {binary_or_app_path} did not parse to a dict.")
    return data


def _extract_codesign_metadata(path: str) -> str:
    res = subprocess.run(["codesign", "--display", "--verbose=4", path], capture_output=True)
    if res.returncode != 0:
        raise VerificationError(f"codesign --display failed for {path}: {res.stderr.decode(errors='replace')}")
    return res.stdout.decode(errors="replace") + "\n" + res.stderr.decode(errors="replace")


def _extract_codesign_leaf_cert_sha256(path: str) -> str:
    with tempfile.TemporaryDirectory() as td:
        os.chmod(td, 0o700)
        prefix = os.path.join(td, "cert-")
        res = subprocess.run(
            ["codesign", "--display", f"--extract-certificates={prefix}", path],
            capture_output=True,
        )
        if res.returncode != 0:
            raise VerificationError(
                f"Failed to extract signing certificates from '{path}': {res.stderr.decode(errors='replace').strip()}"
            )
        leaf_path = f"{prefix}0"
        if not os.path.isfile(leaf_path):
            raise VerificationError(
                f"Unsigned or ad-hoc code object has no X.509 leaf signing certificate: {path}"
            )
        with open(leaf_path, "rb") as cf:
            der = cf.read()
        if not der:
            raise VerificationError(f"Extracted empty leaf signing certificate from '{path}'.")
        return hashlib.sha256(der).hexdigest().upper()


def _iter_nested_signed_targets(app_path: str) -> list[str]:
    contents_dir = os.path.join(app_path, "Contents")
    if not os.path.isdir(contents_dir):
        raise VerificationError(f"Bundle missing Contents directory: {app_path}")
    targets: list[str] = []
    seen_real: set[str] = set()
    main_bin_real = os.path.realpath(os.path.join(contents_dir, "MacOS", "SentinelNodeWallet"))

    for dirpath, dirnames, filenames in os.walk(contents_dir, topdown=True, followlinks=False):
        clean_dirs = []
        for d in sorted(dirnames):
            full_d = os.path.join(dirpath, d)
            if os.path.islink(full_d):
                continue
            if d == "_CodeSignature":
                continue
            if d.endswith((".app", ".xpc", ".framework", ".appex")):
                real_d = os.path.realpath(full_d)
                if real_d not in seen_real:
                    seen_real.add(real_d)
                    targets.append(full_d)
            clean_dirs.append(d)
        dirnames[:] = clean_dirs

        for fn in sorted(filenames):
            full_f = os.path.join(dirpath, fn)
            if os.path.islink(full_f):
                continue
            real_f = os.path.realpath(full_f)
            if real_f == main_bin_real or real_f in seen_real:
                continue
            if is_macho_file(full_f):
                seen_real.add(real_f)
                targets.append(full_f)

    return targets


def verify_signed_claims(
    app_path: str,
    team_id: str,
    bundle_id: str,
    domain: str,
    cert_sha256: str,
    expected_profile_sha256: str | None = None,
) -> None:
    expected_cert_sha = _normalize_sha256_hex(cert_sha256, "cert-sha256").upper()
    emb_prof = os.path.join(app_path, "Contents", "embedded.provisionprofile")
    with tempfile.TemporaryDirectory() as td:
        os.chmod(td, 0o700)
        verified_plist = os.path.join(td, "verified_profile.plist")
        verify_profile_cms(
            emb_prof,
            verified_plist,
            expected_profile_sha256=expected_profile_sha256,
        )
        validate_profile_plist(
            plist_path=verified_plist,
            team_id=team_id,
            bundle_id=bundle_id,
            domain=domain,
            cert_sha256=expected_cert_sha,
            raw_profile_path=emb_prof,
            expected_profile_sha256=expected_profile_sha256,
        )
        with open(verified_plist, "rb") as pf:
            prof_pl = plistlib.load(pf)

    prof_cert_fps = {
        hashlib.sha256(raw_cert).hexdigest().upper()
        for raw_cert in (prof_pl.get("DeveloperCertificates") or [])
        if isinstance(raw_cert, (bytes, bytearray))
    }
    if expected_cert_sha not in prof_cert_fps:
        raise VerificationError(
            f"Expected signing certificate ({expected_cert_sha}) absent from verified profile DeveloperCertificates."
        )

    # Verify outer bundle signature and Hardened Runtime
    verify_cmd = subprocess.run(["codesign", "--verify", "--strict", "--deep", "--verbose=2", app_path], capture_output=True)
    if verify_cmd.returncode != 0:
        raise VerificationError(
            f"codesign --verify --strict --deep failed: {verify_cmd.stderr.decode(errors='replace')}"
        )

    meta = _extract_codesign_metadata(app_path)
    if f"TeamIdentifier={team_id}" not in meta:
        raise VerificationError(f"Outer bundle TeamIdentifier != {team_id}.")
    if "Authority=Developer ID Application:" not in meta:
        raise VerificationError("Outer bundle missing Developer ID Application authority.")
    if "(runtime)" not in meta:
        raise VerificationError("Outer bundle missing Hardened Runtime flag (0x10000(runtime)).")

    outer_leaf_sha = _extract_codesign_leaf_cert_sha256(app_path)
    if outer_leaf_sha != expected_cert_sha:
        raise VerificationError(
            f"Outer signed bundle leaf certificate SHA-256 ({outer_leaf_sha}) != expected signing cert ({expected_cert_sha})."
        )
    if outer_leaf_sha not in prof_cert_fps:
        raise VerificationError(
            f"Outer signed bundle leaf certificate SHA-256 ({outer_leaf_sha}) is NOT authorized in profile DeveloperCertificates."
        )

    signed_ents = _extract_codesign_entitlements_plist(app_path)
    verify_entitlements_against_profile(prof_pl, signed_ents, team_id, bundle_id, domain)

    # Require critical Knots helper binaries and verify ALL nested signed code objects (Mach-Os, frameworks, helpers)
    for helper in ("bitcoind", "bitcoin-cli"):
        helper_path = os.path.join(app_path, "Contents", "MacOS", helper)
        if not os.path.isfile(helper_path):
            raise VerificationError(f"Missing required nested binary: {helper_path}")

    for target_path in _iter_nested_signed_targets(app_path):
        rel = os.path.relpath(target_path, app_path)
        t_meta = _extract_codesign_metadata(target_path)
        if f"TeamIdentifier={team_id}" not in t_meta or "(runtime)" not in t_meta or "Authority=Developer ID Application:" not in t_meta:
            raise VerificationError(
                f"Nested signed target '{rel}' lacks Developer ID Application + TeamID '{team_id}' + Hardened Runtime."
            )
        t_leaf_sha = _extract_codesign_leaf_cert_sha256(target_path)
        if t_leaf_sha != expected_cert_sha or t_leaf_sha not in prof_cert_fps:
            raise VerificationError(
                f"Nested signed target '{rel}' leaf certificate SHA-256 ({t_leaf_sha}) != expected leaf cert ({expected_cert_sha})."
            )
        t_ents = _extract_codesign_entitlements_plist(target_path)
        _assert_no_debug_entitlements(t_ents, f"nested signed target '{rel}'")
        if any(k in t_ents for k in RESTRICTED_ENTITLEMENT_KEYS):
            raise VerificationError(
                f"Nested helper/framework target '{rel}' unexpectedly claims restricted entitlements: {sorted(k for k in t_ents if k in RESTRICTED_ENTITLEMENT_KEYS)}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify Sentinel Node Wallet production bundle invariants.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_cms = sub.add_parser("verify-profile-cms")
    p_cms.add_argument("--profile", required=True)
    p_cms.add_argument("--out-plist", required=True)
    p_cms.add_argument("--expected-profile-sha256", required=False)

    p_val = sub.add_parser("validate-profile-plist")
    p_val.add_argument("--plist", required=True)
    p_val.add_argument("--team-id", required=True)
    p_val.add_argument("--bundle-id", required=True)
    p_val.add_argument("--domain", required=True)
    p_val.add_argument("--cert-sha256", required=True)
    p_val.add_argument("--raw-profile", required=False)
    p_val.add_argument("--expected-profile-sha256", required=False)
    p_val.add_argument("--json-out", required=False)

    p_perm = sub.add_parser("normalize-and-audit-permissions")
    p_perm.add_argument("--app", required=True)
    p_perm.add_argument("--audit-only", action="store_true")
    p_perm.add_argument("--require-profile", action="store_true")
    p_perm.add_argument("--expected-profile-sha256", required=False)

    p_claims = sub.add_parser("verify-signed-claims")
    p_claims.add_argument("--app", required=True)
    p_claims.add_argument("--team-id", required=True)
    p_claims.add_argument("--bundle-id", required=True)
    p_claims.add_argument("--domain", required=True)
    p_claims.add_argument("--cert-sha256", required=True)
    p_claims.add_argument("--expected-profile-sha256", required=False)

    p_ent = sub.add_parser("check-entitlements-allowlist")
    p_ent.add_argument("--profile-plist", required=True)
    p_ent.add_argument("--entitlements-plist", required=True)
    p_ent.add_argument("--team-id", required=True)
    p_ent.add_argument("--bundle-id", required=True)
    p_ent.add_argument("--domain", required=True)

    args = parser.parse_args()
    try:
        if args.cmd == "verify-profile-cms":
            verify_profile_cms(args.profile, args.out_plist, args.expected_profile_sha256)
            print("✓ Verified Apple CMS authenticity of provisioning profile.")
        elif args.cmd == "validate-profile-plist":
            summary = validate_profile_plist(
                args.plist,
                args.team_id,
                args.bundle_id,
                args.domain,
                args.cert_sha256,
                args.raw_profile,
                args.expected_profile_sha256,
            )
            if args.json_out:
                with open(args.json_out, "w", encoding="utf-8") as jf:
                    json.dump(summary, jf, indent=2)
            print(json.dumps(summary, indent=2))
        elif args.cmd == "normalize-and-audit-permissions":
            normalize_and_audit_permissions(
                args.app,
                args.audit_only,
                args.require_profile,
                args.expected_profile_sha256,
            )
            print("✓ Audited distributable bundle permissions, symlinks, and embedded profile cleanly.")
        elif args.cmd == "verify-signed-claims":
            verify_signed_claims(
                args.app,
                args.team_id,
                args.bundle_id,
                args.domain,
                args.cert_sha256,
                args.expected_profile_sha256,
            )
            print("✓ Verified final signed entitlements against embedded MAC_APP_DIRECT provisioning profile.")
        elif args.cmd == "check-entitlements-allowlist":
            with open(args.profile_plist, "rb") as pf:
                prof_pl = plistlib.load(pf)
            with open(args.entitlements_plist, "rb") as ef:
                ent_pl = plistlib.load(ef)
            verify_entitlements_against_profile(prof_pl, ent_pl, args.team_id, args.bundle_id, args.domain)
            print("✓ Claimed entitlements satisfied by profile allowlist.")
    except VerificationError as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
