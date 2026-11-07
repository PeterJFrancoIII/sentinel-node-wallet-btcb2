import Foundation

/// A read-only window of historical BTCB2 blocks that the locally validating
/// pruned node reports as retained. This is NOT financial insurance, a promise
/// of reorg recovery, or a full-chain archive.
public struct RollingHistoryCoverage: Sendable {
    public let firstRetainedHeight: Int
    public let tipHeight: Int
    public let firstRetainedTime: Date
    public let tipTime: Date
    public let observedBlockUndoBytes: Int64?
    public let effectivePruneTargetBytes: Int64?
    public let initialBlockDownload: Bool
    public let measuredAt: Date

    public init?(
        firstRetainedHeight: Int,
        tipHeight: Int,
        firstRetainedTimestamp: TimeInterval,
        tipTimestamp: TimeInterval,
        observedBlockUndoBytes: Int64?,
        effectivePruneTargetBytes: Int64?,
        initialBlockDownload: Bool,
        measuredAt: Date = Date()
    ) {
        guard firstRetainedHeight > 0, tipHeight > firstRetainedHeight,
              firstRetainedTimestamp.isFinite, tipTimestamp.isFinite,
              firstRetainedTimestamp > 0, tipTimestamp > firstRetainedTimestamp,
              tipTimestamp - firstRetainedTimestamp < 100 * 366 * 86_400 else {
            return nil
        }
        self.firstRetainedHeight = firstRetainedHeight
        self.tipHeight = tipHeight
        self.firstRetainedTime = Date(timeIntervalSince1970: firstRetainedTimestamp)
        self.tipTime = Date(timeIntervalSince1970: tipTimestamp)
        self.observedBlockUndoBytes = observedBlockUndoBytes
        self.effectivePruneTargetBytes = effectivePruneTargetBytes
        self.initialBlockDownload = initialBlockDownload
        self.measuredAt = measuredAt
    }

    public var retainedBlockCount: Int { tipHeight - firstRetainedHeight + 1 }
    public var actualHistorySeconds: TimeInterval {
        tipTime.timeIntervalSince(firstRetainedTime)
    }
    public var actualDisplay: String {
        "~" + RollingHistoryDurationFormatter.string(from: actualHistorySeconds)
    }

    /// Forecast is intentionally NOT available during IBD: historic blocks
    /// currently being processed may have very different byte-density from
    /// BTCB2 blocks at the real network tip.
    public var isProjectionCalibrated: Bool {
        guard !initialBlockDownload, firstRetainedHeight > 0,
              let bytes = observedBlockUndoBytes, bytes > 0,
              let target = effectivePruneTargetBytes, target >= 550 * 1_048_576,
              actualHistorySeconds >= 3600,
              retainedBlockCount >= 288 else { return false }
        let ratio = Double(bytes) / Double(target)
        // Pruning works at block-file granularity. Large deviation means the
        // node may be transitioning targets or not yet at its steady retention.
        return ratio >= 0.45 && ratio <= 2.0
    }

    public func projectedHistorySeconds(forPruneMiB targetMiB: Int) -> TimeInterval? {
        guard isProjectionCalibrated, targetMiB >= 550,
              targetMiB <= 1_048_576,
              let bytes = observedBlockUndoBytes, bytes > 0 else { return nil }
        let wantedBytes = Double(targetMiB) * 1_048_576
        let estimated = actualHistorySeconds * wantedBytes / Double(bytes)
        // Keep the minimum 288 recent blocks: network timestamps are estimates,
        // not a calendar promise. This protects against misleading tiny windows.
        let secondsPerBlock = actualHistorySeconds / Double(tipHeight - firstRetainedHeight)
        let floorSeconds = 288.0 * max(60, min(3600, secondsPerBlock))
        let result = max(estimated, floorSeconds)
        guard result.isFinite && result > 0 else { return nil }
        return result
    }

    public func projectedDisplay(forPruneMiB targetMiB: Int) -> String {
        guard let seconds = projectedHistorySeconds(forPruneMiB: targetMiB) else {
            return "Calibrating — forecast available after sync"
        }
        return "~" + RollingHistoryDurationFormatter.string(from: seconds)
    }

    public var description: String {
        let context = initialBlockDownload ? "at current verified sync height" : "at current chain tip"
        return "\(actualDisplay) retained \(context) • \(retainedBlockCount) blocks"
    }
}

/// Approximate calendar durations. Month/year units use average Gregorian
/// lengths because a rolling forecast is measured in elapsed seconds, not an
/// exact future appointment. Display no more than two significant units.
public enum RollingHistoryDurationFormatter {
    public static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Measuring…" }
        if seconds < 3600 { return "<1 hour" }
        if seconds > 100 * 366 * 86_400 { return ">100 years" }
        let units: [(seconds: Double, singular: String, plural: String)] = [
            (365.2425 * 86_400, "year", "years"),
            (30.436875 * 86_400, "month", "months"),
            (7 * 86_400, "week", "weeks"),
            (86_400, "day", "days"),
            (3600, "hour", "hours")
        ]
        var remaining = seconds
        var parts: [String] = []
        for unit in units {
            let count = Int(remaining / unit.seconds)
            guard count > 0 else { continue }
            parts.append("\(count) \(count == 1 ? unit.singular : unit.plural)")
            remaining -= Double(count) * unit.seconds
            if parts.count == 2 { break }
        }
        return parts.isEmpty ? "<1 hour" : parts.joined(separator: ", ")
    }
}
