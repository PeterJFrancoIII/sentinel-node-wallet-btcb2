import Foundation

/// Validates Git release tags and operator authorization tokens for production distribution.
/// Enforces fail-closed grammar validation, strict regex patterns, and monotonic build sequence.
public struct ReleaseTagValidator: Sendable {
    /// Strict tag regex pattern: ^v[0-9]+\.[0-9]+\.[0-9]+-build[0-9]+$
    public static let strictTagRegex = "^v[0-9]+\\.[0-9]+\\.[0-9]+-build[0-9]+$"

    public enum ValidationError: Error, Equatable, LocalizedError {
        case emptyTag
        case invalidFormat(String)
        case nonMonotonicBuild(Int, minimumRequired: Int)
        case operatorApprovalMissing(String)

        public var errorDescription: String? {
            switch self {
            case .emptyTag:
                return "Release tag cannot be empty."
            case .invalidFormat(let tag):
                return "Release tag '\(tag)' does not match required format: ^v[0-9]+\\.[0-9]+\\.[0-9]+-build[0-9]+$"
            case .nonMonotonicBuild(let build, let min):
                return "Build number \(build) must be strictly greater than \(min) to maintain monotonic sequence."
            case .operatorApprovalMissing(let received):
                return "Operator release authorization missing or invalid. Received '\(received)', expected 'YES'."
            }
        }
    }

    public struct ValidatedReleaseTag: Equatable, Sendable {
        public let rawTag: String
        public let version: String // e.g. "1.0.0"
        public let major: Int
        public let minor: Int
        public let patch: Int
        public let buildNumber: Int
    }

    /// Validates that explicit human operator approval has been attested with the exact token "YES".
    public static func validateOperatorApproval(_ confirmation: String) throws {
        guard confirmation == "YES" else {
            throw ValidationError.operatorApprovalMissing(confirmation)
        }
    }

    /// Validates a release tag against strict syntax and monotonic build number requirements.
    /// - Parameters:
    ///   - tag: The candidate tag string (e.g. "v1.0.0-build4")
    ///   - minimumBuildNumber: The highest previously published release build (defaults to 3, allowing Build 4+)
    /// - Returns: ValidatedReleaseTag containing parsed components
    public static func validateReleaseTag(_ tag: String, minimumBuildNumber: Int = 3) throws -> ValidatedReleaseTag {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyTag
        }

        // Must not contain untrimmed whitespace or newlines
        guard tag == trimmed else {
            throw ValidationError.invalidFormat(tag)
        }

        // Strict regex match: prevents path traversal, command injection, and relaxed SemVer syntax
        guard let regex = try? NSRegularExpression(pattern: strictTagRegex),
              regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil else {
            throw ValidationError.invalidFormat(trimmed)
        }

        guard let parsed = AppVersion.parse(trimmed),
              let build = parsed.build else {
            throw ValidationError.invalidFormat(trimmed)
        }

        guard build > minimumBuildNumber else {
            throw ValidationError.nonMonotonicBuild(build, minimumRequired: minimumBuildNumber)
        }

        let versionString = "\(parsed.major).\(parsed.minor).\(parsed.patch)"
        return ValidatedReleaseTag(
            rawTag: trimmed,
            version: versionString,
            major: parsed.major,
            minor: parsed.minor,
            patch: parsed.patch,
            buildNumber: build
        )
    }
}
