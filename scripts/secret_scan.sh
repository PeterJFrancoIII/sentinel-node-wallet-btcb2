#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Running Pre-Release Secret & Isolation Audit ==="

VIOLATIONS=0

# Check for forbidden cross-project strings
FORBIDDEN=(
    "sentinel pool"
    "sentinel mining"
    "ethereum mining corp"
    "bm-s3"
    "console8"
)

for term in "${FORBIDDEN[@]}"; do
    MATCHES=$(git -C "${ROOT_DIR}" grep -i "${term}" ":(exclude)scripts/secret_scan.sh" ":(exclude)Tests/NodePocketCoreTests/IsolationSecurityTests.swift" ":(exclude)Sources/NodePocketCore/Isolation/SecurityAuditor.swift" ":(exclude)docs/ISOLATION_REPORT.md" ":(exclude)tools/verify_governance.py" || true)
    if [ -n "${MATCHES}" ]; then
        echo "❌ Isolation violation found for term '${term}':"
        echo "${MATCHES}"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

# Secret scan for private keys
KEY_MATCHES=$(git -C "${ROOT_DIR}" grep -E "(xprv[a-zA-Z0-9]{100,}|[5KL][1-9A-HJ-NP-Za-km-z]{50,51})" ":(exclude)Tests/NodePocketCoreTests/IsolationSecurityTests.swift" ":(exclude)Sources/NodePocketCore/Isolation/SecurityAuditor.swift" || true)
if [ -n "${KEY_MATCHES}" ]; then
    echo "❌ Secret leak violation (private keys detected):"
    echo "${KEY_MATCHES}"
    VIOLATIONS=$((VIOLATIONS + 1))
fi

if [ ${VIOLATIONS} -eq 0 ]; then
    echo "✅ Audit passed: 0 isolation violations, 0 secret leaks detected."
    exit 0
else
    echo "❌ Audit FAILED: ${VIOLATIONS} violation(s) detected."
    exit 1
fi
