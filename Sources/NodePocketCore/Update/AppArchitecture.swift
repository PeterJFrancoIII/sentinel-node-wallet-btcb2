import Foundation

/// Supported macOS CPU architectures for Sentinel Node Wallet binary packages.
/// Enforces strict architecture matching to ensure Apple Silicon arm64 Macs do not
/// inadvertently download or execute x86_64 binaries (and vice-versa).
public enum AppArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"
    case universal = "universal"
    case unknown = "unknown"

    /// Current host machine architecture.
    public static var current: AppArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    public var displayName: String {
        switch self {
        case .arm64:
            return "Apple Silicon (arm64)"
        case .x86_64:
            return "macOS Intel (x86_64)"
        case .universal:
            return "Universal Binary (arm64 + x86_64)"
        case .unknown:
            return "Unknown Architecture"
        }
    }

    /// Evaluates if an asset's architecture is compatible with the specified host.
    /// Strict safety rules:
    /// - arm64 host: Accepts arm64 or universal. Strictly rejects x86_64.
    /// - x86_64 host: Accepts x86_64 or universal. Strictly rejects arm64.
    public func isCompatible(with host: AppArchitecture = .current) -> Bool {
        if self == .universal || host == .universal {
            return true
        }
        if self == .unknown || host == .unknown {
            return false
        }
        return self == host
    }

    /// Resolves architecture token from release asset names or XML attributes.
    public static func detect(from string: String) -> AppArchitecture {
        let lower = string.lowercased()
        if lower.contains("universal") {
            return .universal
        }
        if lower.contains("arm64") || lower.contains("aarch64") || lower.contains("apple-silicon") {
            return .arm64
        }
        if lower.contains("x86_64") || lower.contains("x86-64") || lower.contains("x64") || lower.contains("intel") {
            return .x86_64
        }
        return .unknown
    }
}
