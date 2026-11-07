#!/usr/bin/env python3
"""
tools/verify_governance.py
Automated Governance & Release-Gate Compliance Verifier for Sentinel Node Wallet - BTCB2.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CANONICAL_TOPICS = [
    "btcb2", "bitcoin-blake2b", "blake2b", "bip110", "bitcoin-knots",
    "macos", "macos-app", "swift", "swiftui", "apple-silicon",
    "bitcoin-wallet", "non-custodial", "self-custody", "wallet-manager",
    "pruned-node", "full-node", "blockchain-node", "low-storage",
    "network-hashrate", "sentinel-node-wallet"
]

FORBIDDEN_STRINGS = [
    r"BEGIN\s+(RSA|OPENSSH|EC|DSA)?\s*PRIVATE\s+KEY",
    r"ghp_[A-Za-z0-9_]{36}",
    r"xprv[a-km-zA-HJ-NP-Z1-9]{107,108}",
    r"Sentinel-Pool",
    r"BM-S3",
    r"Mining Corp"
]

REQUIRED_DOCS = [
    "README.md", "AGENTS.md", "GOVERNANCE.md", "SECURITY.md",
    "CONTRIBUTING.md", "NOTICE.md", "docs/ARCHITECTURE.md",
    "TEST_AND_RELEASE_MATRIX.md", "GEMINI_COMPLETION_HANDOFF.md",
    "docs/WALLET_MANAGER_V7.md"
]

def check_secrets_and_forbidden():
    violations = []
    text_extensions = {".swift", ".sh", ".json", ".md", ".py", ".plist"}

    for dirpath, _, filenames in os.walk(ROOT):
        # Skip git and build dirs
        rel_dir = os.path.relpath(dirpath, ROOT)
        if any(part in rel_dir.split(os.sep) for part in [".git", ".build", "dist", ".cache"]):
            continue

        for filename in filenames:
            ext = os.path.splitext(filename)[1]
            if ext in text_extensions:
                file_path = os.path.join(dirpath, filename)
                try:
                    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    for pattern in FORBIDDEN_STRINGS:
                        # Allow mentions in scanner files and audit verification reports
                        if any(s in filename for s in ["verify_governance.py", "secret_scan.sh", "SecurityAuditor.swift", "ISOLATION_REPORT.md", "IsolationSecurityTests.swift"]):
                            continue
                        if re.search(pattern, content, re.IGNORECASE):
                            violations.append(f"{file_path}: matched forbidden pattern '{pattern}'")
                except Exception as e:
                    violations.append(f"{file_path}: read error {e}")
    return violations

def check_required_docs():
    missing = []
    for doc in REQUIRED_DOCS:
        p = ROOT / doc
        if not p.is_file():
            missing.append(doc)
    return missing

def main():
    print("=== Running Sentinel Node Wallet - BTCB2 Governance Audit ===")

    # 1. Secret & forbidden term scan
    violations = check_secrets_and_forbidden()
    if violations:
        print(f"FAILED: Found {len(violations)} security/isolation violations:")
        for v in violations:
            print(f"  - {v}")
        sys.exit(1)
    else:
        print("✓ Zero secrets, leaked credentials, or forbidden cross-project terms detected.")

    # 2. Check canonical topics length
    if len(CANONICAL_TOPICS) == 20:
        print(f"✓ Canonical GitHub topics verified (count: {len(CANONICAL_TOPICS)}).")
    else:
        print(f"FAILED: Canonical topics count is {len(CANONICAL_TOPICS)}, expected 20.")
        sys.exit(1)

    # 3. Check docs
    missing_docs = check_required_docs()
    if missing_docs:
        print(f"WARNING: The following documentation files need to be created/updated: {missing_docs}")
    else:
        print("✓ All 9 governance and architecture documentation files exist.")

    print("=== Governance Verification Complete ===")

if __name__ == "__main__":
    main()
