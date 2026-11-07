import Foundation

/// Canonical consensus coinbase maturity rules for BTCB2 BLAKE2b MainNet.
/// Specification authority: docs/WALLET_MANAGER_V7.md
public enum CoinbaseEpoch: String, Sendable, CaseIterable {
    /// Initial post-fork era (< 973,440): Standard 100-block maturity (~16.7h)
    case standard100
    /// Intermediate short-epoch era (973,440 ..< 979,919): 6,480 blocks (~45 days)
    case intermediate45Day
    /// Long-era deep maturity (>= 979,919 until 2027-09-01 MTP expiry): 25,920 blocks (~180 days)
    case deep180Day
    /// Post-expiry era (MTP >= 2027-09-01 00:00 UTC): Standard 100-block maturity for newly minted rewards
    case postExpiry100
}

public struct CoinbaseMaturityCalculator: Sendable {
    /// Activation height of the 6,480-block (~45-day) maturity epoch
    public static let intermediateEpochStartHeight: Int = 973440
    /// Activation height of the 25,920-block (~180-day) maturity epoch
    public static let deepEpochStartHeight: Int = 979919
    /// Median Time Past (MTP) expiry timestamp: 2027-09-01 00:00:00 UTC (1,820,016,000 Unix seconds)
    public static let expiryMTPTimestamp: Int64 = 1820016000

    /// Evaluates the consensus epoch for a coinbase reward based on its origin block height and MTP.
    /// Invariant: Once minted, a reward's maturity requirement is immutable and fixed to its creation epoch.
    public static func epoch(forOriginHeight height: Int, originMTP: Int64? = nil) -> CoinbaseEpoch {
        if let mtp = originMTP, mtp >= expiryMTPTimestamp {
            return .postExpiry100
        }
        if height < intermediateEpochStartHeight {
            return .standard100
        } else if height < deepEpochStartHeight {
            return .intermediate45Day
        } else {
            return .deep180Day
        }
    }

    /// Returns the required block confirmation depth for a coinbase reward.
    public static func requiredConfirmations(forOriginHeight height: Int, originMTP: Int64? = nil) -> Int {
        switch epoch(forOriginHeight: height, originMTP: originMTP) {
        case .standard100, .postExpiry100:
            return 100
        case .intermediate45Day:
            return 6480
        case .deep180Day:
            return 25920
        }
    }

    /// Returns the exact block height at which a coinbase reward becomes spendable.
    public static func maturityHeight(originHeight: Int, originMTP: Int64? = nil) -> Int {
        originHeight + requiredConfirmations(forOriginHeight: originHeight, originMTP: originMTP)
    }

    /// Determines if a coinbase reward is fully mature given the current tip height.
    public static func isMature(originHeight: Int, currentTipHeight: Int, originMTP: Int64? = nil) -> Bool {
        currentTipHeight >= maturityHeight(originHeight: originHeight, originMTP: originMTP)
    }

    /// Returns the number of blocks remaining until maturity.
    public static func remainingBlocks(originHeight: Int, currentTipHeight: Int, originMTP: Int64? = nil) -> Int {
        let matHeight = maturityHeight(originHeight: originHeight, originMTP: originMTP)
        return max(0, matHeight - currentTipHeight)
    }

    /// Estimates time remaining in auto-scaled units based on rolling block intervals.
    public static func estimatedTimeRemaining(
        remainingBlocks: Int,
        secondsPerBlock: Double = 600.0,
        isIBD: Bool = false
    ) -> (display: String, isLowConfidence: Bool) {
        if remainingBlocks <= 0 {
            return ("Mature", false)
        }

        let isLowConfidence = isIBD || secondsPerBlock <= 0 || abs(secondsPerBlock - 600.0) < 0.001
        let safeInterval = (secondsPerBlock > 0) ? secondsPerBlock : 600.0
        let totalSeconds = Double(remainingBlocks) * safeInterval

        let formatted = formatDuration(seconds: totalSeconds)
        return (formatted, isLowConfidence)
    }

    public static func formatDuration(seconds: Double) -> String {
        guard seconds > 0 else { return "~0s" }

        let secs = Int(seconds)
        let minutes = secs / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7

        if weeks >= 2 {
            let remDays = days % 7
            return remDays > 0 ? "~\(weeks)w \(remDays)d" : "~\(weeks)w"
        } else if days >= 1 {
            let remHours = hours % 24
            return remHours > 0 ? "~\(days)d \(remHours)h" : "~\(days)d"
        } else if hours >= 1 {
            let remMins = minutes % 60
            return remMins > 0 ? "~\(hours)h \(remMins)m" : "~\(hours)h"
        } else if minutes >= 1 {
            let remSecs = secs % 60
            return remSecs > 0 ? "~\(minutes)m \(remSecs)s" : "~\(minutes)m"
        } else {
            return "~\(max(1, secs))s"
        }
    }
}
