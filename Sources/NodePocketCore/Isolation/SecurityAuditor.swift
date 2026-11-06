import Foundation

public struct SecurityAuditResult: Sendable {
    public let isPassed: Bool
    public let violations: [String]
    public let warnings: [String]
}

public enum SecurityAuditor {
    public static let forbiddenSubstrings = [
        "sentinel pool",
        "sentinel mining",
        "ethereum mining corp",
        "bm-s3",
        "console8"
    ]

    /// Audits a string or configuration payload for forbidden cross-project strings.
    public static func auditContent(_ content: String) -> SecurityAuditResult {
        var violations: [String] = []
        let lower = content.lowercased()

        for term in forbiddenSubstrings {
            if lower.contains(term) {
                violations.append("Content contains forbidden isolation term: '\(term)'")
            }
        }

        // Secret scanning: check for raw private keys
        if content.range(of: #"xprv[a-zA-Z0-9]{100,}"#, options: .regularExpression) != nil {
            violations.append("Potential unencrypted extended private key (xprv) detected in content.")
        }
        if content.range(of: #"[5KL][1-9A-HJ-NP-Za-km-z]{50,51}"#, options: .regularExpression) != nil {
            violations.append("Potential unencrypted WIF private key detected in content.")
        }

        return SecurityAuditResult(
            isPassed: violations.isEmpty,
            violations: violations,
            warnings: []
        )
    }

    /// Verifies that RPC endpoint configuration is strictly local.
    public static func auditRPCHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "127.0.0.1" || trimmed == "localhost"
    }

    /// Verifies that workspace is strictly outside forbidden parent directories.
    public static func auditWorkspacePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        for term in forbiddenSubstrings {
            if lower.contains(term) {
                return false
            }
        }
        return true
    }

    /// Verifies file permissions (0700 for directory, 0600 for files).
    public static func auditPermissions(at path: String, isDirectory: Bool) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let posix = attrs[.posixPermissions] as? NSNumber else {
            return false
        }
        let perms = posix.intValue
        if isDirectory {
            return (perms & 0o077) == 0 // No permissions for group or others
        } else {
            return (perms & 0o077) == 0 // Strictly private file
        }
    }
}
