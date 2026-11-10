import Foundation

/// Satoshi conversion and arithmetic engine.
/// Authority: docs/WALLET_MANAGER_V7.md - Money arithmetic MUST be integer satoshis.
public struct SatoshiMath {
    public static let satsPerBTC: Int64 = 100_000_000

    public static func toSats(btc: Double) -> Int64 {
        guard !btc.isNaN && !btc.isInfinite && btc >= 0 else { return 0 }
        return Int64(round(btc * Double(satsPerBTC)))
    }

    public static func toBTC(sats: Int64) -> Double {
        Double(sats) / Double(satsPerBTC)
    }

    public static func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }
}

public enum FeePresetType: String, CaseIterable, Sendable {
    case cheapest = "Cheapest"
    case normal = "Normal"
    case fast = "Fast"
    case custom = "Custom"

    public var targetBlocks: Int {
        switch self {
        case .cheapest: return 24
        case .normal: return 6
        case .fast: return 2
        case .custom: return 0
        }
    }
}

public struct FeeQuote: Sendable, Equatable {
    public let type: FeePresetType
    public let satPerVB: Int
    public let targetBlocks: Int
    public let estimatedMinutes: Int
    public let isRelayFloor: Bool
    public let fetchedAt: Date
    public let expirySeconds: TimeInterval
    public let medianTxFeeSats: Int64

    public init(
        type: FeePresetType,
        satPerVB: Int,
        targetBlocks: Int,
        estimatedMinutes: Int,
        isRelayFloor: Bool = false,
        fetchedAt: Date = Date(),
        expirySeconds: TimeInterval = 60.0,
        medianTxFeeSats: Int64? = nil
    ) {
        self.type = type
        self.satPerVB = max(1, satPerVB)
        self.targetBlocks = targetBlocks
        self.estimatedMinutes = estimatedMinutes
        self.isRelayFloor = isRelayFloor
        self.fetchedAt = fetchedAt
        self.expirySeconds = expirySeconds
        self.medianTxFeeSats = medianTxFeeSats ?? Int64(max(1, satPerVB) * 140)
    }

    public var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > expirySeconds
    }
}

public struct FundedTxPreview: Sendable, Identifiable {
    public let id: UUID
    public let destinationAddress: String
    public let recipientName: String?
    public let amountSats: Int64
    public let feeSats: Int64
    public let satPerVB: Int
    public let estimatedVSize: Int
    public let changeSats: Int64
    public let selectedInputs: [String]
    public let createdAt: Date
    public let validityWindowSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        destinationAddress: String,
        recipientName: String? = nil,
        amountSats: Int64,
        feeSats: Int64,
        satPerVB: Int,
        estimatedVSize: Int,
        changeSats: Int64 = 0,
        selectedInputs: [String] = [],
        createdAt: Date = Date(),
        validityWindowSeconds: TimeInterval = 60.0
    ) {
        self.id = id
        self.destinationAddress = destinationAddress
        self.recipientName = recipientName
        self.amountSats = amountSats
        self.feeSats = feeSats
        self.satPerVB = satPerVB
        self.estimatedVSize = estimatedVSize
        self.changeSats = changeSats
        self.selectedInputs = selectedInputs
        self.createdAt = createdAt
        self.validityWindowSeconds = validityWindowSeconds
    }

    public var totalDebitSats: Int64 {
        amountSats + feeSats
    }

    public var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > validityWindowSeconds
    }
}

public struct FeeEngine: Sendable {
    /// Converts Bitcoin Knots rate (BTCB2/kB) to sat/vB: rate * 100,000.
    public static func rateToSatPerVB(btcPerKB: Double) -> Int {
        guard !btcPerKB.isNaN && !btcPerKB.isInfinite && btcPerKB > 0 else {
            return 1
        }
        let satPerVB = Int(ceil(btcPerKB * 100_000.0))
        return max(1, satPerVB)
    }

    /// Evaluates fee rates across the three standard presets ensuring Fast >= Normal >= Cheapest.
    public static func reconcileRates(cheapest: Int, normal: Int, fast: Int, relayFloor: Int = 1) -> (cheapest: Int, normal: Int, fast: Int) {
        let ch = max(relayFloor, cheapest)
        let norm = max(ch, normal)
        let fst = max(norm, fast)
        return (ch, norm, fst)
    }

    /// Evaluates live mempool transactions to determine fee percentiles (min, 25th, median, 75th).
    public static func computeMempoolRateDistribution(from mempool: [String: MempoolTxSummary]) -> (min: Int, p25: Int, median: Int, p75: Int)? {
        var rates: [Double] = []
        for (_, entry) in mempool {
            guard let vsize = entry.vsize, vsize > 0 else { continue }
            let feeBTC = entry.effectiveFeeBTC
            let feeSats = round(feeBTC * 100_000_000.0)
            let satPerVB = feeSats / Double(vsize)
            if satPerVB > 0 {
                rates.append(satPerVB)
            }
        }
        guard !rates.isEmpty else { return nil }
        rates.sort()
        let count = rates.count
        let minRate = max(1, Int(ceil(rates[0])))
        let p25Rate = max(minRate, Int(ceil(rates[count / 4])))
        let medianRate = max(p25Rate, Int(ceil(rates[count / 2])))
        let p75Rate = max(medianRate, Int(ceil(rates[(3 * count) / 4])))
        return (minRate, p25Rate, medianRate, p75Rate)
    }
}
