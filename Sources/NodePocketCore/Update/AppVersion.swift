import Foundation

/// Semantic version representation with explicit integer build ordering for Sentinel Node Wallet.
/// Enforces numeric build comparison (e.g. build 3 < build 10) instead of lexicographical string sorting.
public struct AppVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let build: Int?
    public let rawString: String

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: String? = nil,
        build: Int? = nil,
        rawString: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
        if let raw = rawString, !raw.isEmpty {
            self.rawString = raw
        } else {
            var str = "\(major).\(minor).\(patch)"
            if let pre = prerelease, !pre.isEmpty {
                str += "-\(pre)"
            }
            if let b = build {
                str += " (build \(b))"
            }
            self.rawString = str
        }
    }

    public var isPrerelease: Bool {
        guard let pre = prerelease, !pre.isEmpty else { return false }
        return true
    }

    public var description: String {
        rawString
    }

    public var shortDescription: String {
        var str = "\(major).\(minor)"
        if patch > 0 || (prerelease != nil && !prerelease!.isEmpty) {
            str += ".\(patch)"
        }
        if let pre = prerelease, !pre.isEmpty {
            str += "-\(pre)"
        }
        if let b = build {
            str += " (\(b))"
        }
        return str
    }

    /// Strict semantic version comparison with integer build ordering.
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // SemVer: A version with a prerelease is lower priority than the same version without a prerelease.
        // e.g. 1.0.0-beta.1 < 1.0.0
        if lhs.isPrerelease && !rhs.isPrerelease {
            return true
        }
        if !lhs.isPrerelease && rhs.isPrerelease {
            return false
        }
        if let lp = lhs.prerelease, let rp = rhs.prerelease, lp != rp {
            return lp < rp
        }

        // Compare integer build numbers:
        let lb = lhs.build ?? 0
        let rb = rhs.build ?? 0
        return lb < rb
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease &&
               (lhs.build ?? 0) == (rhs.build ?? 0)
    }

    /// Parses version strings such as:
    /// - "v1.0.0-build3"
    /// - "1.0 (3)"
    /// - "1.0.0 (build 10)"
    /// - "v1.0.0-build10"
    /// - "1.2.0-beta.1-build4"
    /// - "1.0"
    /// - "29.4.3"
    public static func parse(_ string: String) -> AppVersion? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed
        if working.hasPrefix("v") || working.hasPrefix("V") {
            working.removeFirst()
        }

        var detectedBuild: Int? = nil

        // Check for parenthetical build format: "1.0 (3)" or "1.0.0 (build 3)"
        if let openParen = working.firstIndex(of: "("),
           let closeParen = working.lastIndex(of: ")"),
           openParen < closeParen {
            let inside = working[working.index(after: openParen)..<closeParen]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let buildToken = inside.replacingOccurrences(of: "build", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let b = Int(buildToken) {
                detectedBuild = b
            }
            working = String(working[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check for -buildX suffix: "1.0.0-build3" or "1.0.0-beta-build10"
        if detectedBuild == nil,
           let buildRange = working.range(of: "-build", options: [.caseInsensitive, .backwards]) {
            let buildPart = String(working[buildRange.upperBound...])
            if let b = Int(buildPart.trimmingCharacters(in: .whitespacesAndNewlines)) {
                detectedBuild = b
                working = String(working[..<buildRange.lowerBound])
            }
        }

        // Parse prerelease if separated by '-'
        var prereleaseString: String? = nil
        if let dashIdx = working.firstIndex(of: "-") {
            prereleaseString = String(working[working.index(after: dashIdx)...])
            working = String(working[..<dashIdx])
        }

        // Split remaining by dot
        let components = working.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else { return nil }

        let major = components[0]
        let minor = components.count > 1 ? components[1] : 0
        let patch = components.count > 2 ? components[2] : 0

        return AppVersion(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prereleaseString,
            build: detectedBuild,
            rawString: trimmed
        )
    }
}
