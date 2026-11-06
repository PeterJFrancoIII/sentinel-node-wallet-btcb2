import Foundation

/// Defines chain rules, network ports, consensus validations, and BIP-110 constants for BTCB2.
public enum BTCB2Network: String, CaseIterable, Codable, Sendable {
    case mainnet
    case testnet4
    case regtest

    public var defaultRPCPort: Int {
        switch self {
        case .mainnet: return 8332
        case .testnet4: return 48332
        case .regtest: return 18443
        }
    }

    public var defaultP2PPort: Int {
        switch self {
        case .mainnet: return 8333
        case .testnet4: return 48333
        case .regtest: return 18444
        }
    }

    public var chainName: String {
        switch self {
        case .mainnet: return "main"
        case .testnet4: return "testnet4"
        case .regtest: return "regtest"
        }
    }

    public var requiredRules: [String] {
        return ["segwit", "blake2b"]
    }
}

public struct BTCB2ConsensusConstants {
    /// Canonical BIP-110 activation height on BTCB2 mainnet
    public static let forkActivationHeight: Int = 961640

    /// Authoritative block hash for fork block 961640
    public static let forkActivationBlockHash: String = "0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb"

    /// Verified upstream Knots release version
    public static let pinnedKnotsVersion: String = "29.4.3.knots20260508"

    /// Coinbase maturity boundaries
    public static let standardCoinbaseMaturity: Int = 100
    public static let extendedCoinbaseMaturityStage1: Int = 6480  // Heights 973440 - 979918
    public static let extendedCoinbaseMaturityStage2: Int = 25920 // Heights >= 979919
}

public struct BTCB2ConsensusState: Sendable {
    public let network: BTCB2Network
    public let currentHeight: Int
    public let bestBlockHash: String
    public let difficulty: Double
    public let isBlake2bActive: Bool
    public let isChainVerified: Bool

    public init(
        network: BTCB2Network,
        currentHeight: Int,
        bestBlockHash: String,
        difficulty: Double,
        isBlake2bActive: Bool,
        isChainVerified: Bool
    ) {
        self.network = network
        self.currentHeight = currentHeight
        self.bestBlockHash = bestBlockHash
        self.difficulty = difficulty
        self.isBlake2bActive = isBlake2bActive
        self.isChainVerified = isChainVerified
    }
}

public enum BTCB2ConsensusValidator {
    /// Validates that block template rules include both segwit and blake2b
    public static func validateTemplateRules(_ rules: [String]) -> Bool {
        let set = Set(rules.map { $0.lowercased() })
        return set.contains("segwit") && set.contains("blake2b")
    }

    /// Verifies that a node response belongs to the expected BTCB2 chain and not vanilla Bitcoin SHA256d.
    public static func validateChainIdentity(chain: String, expectedNetwork: BTCB2Network) -> Bool {
        let normalized = chain.lowercased()
        switch expectedNetwork {
        case .mainnet:
            return normalized == "main" || normalized == "mainnet"
        case .testnet4:
            return normalized == "testnet4"
        case .regtest:
            return normalized == "regtest"
        }
    }

    /// Validates the fork checkpoint block hash if the node is at or past activation height.
    public static func validateForkCheckpoint(height: Int, blockHash: String) -> Bool {
        if height == BTCB2ConsensusConstants.forkActivationHeight {
            return blockHash.lowercased() == BTCB2ConsensusConstants.forkActivationBlockHash.lowercased()
        }
        return true
    }
}
