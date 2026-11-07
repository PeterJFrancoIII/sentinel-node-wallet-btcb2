import Foundation

public enum ETAState: Equatable, Sendable {
    case calibrating
    case estimating(seconds: Double)
    case stalled
    case waitingForPeers
    case synchronized

    public var statusText: String {
        switch self {
        case .calibrating: return "Calibrating..."
        case .estimating: return "Estimating"
        case .stalled: return "Stalled"
        case .waitingForPeers: return "Waiting for peers"
        case .synchronized: return "Synchronized"
        }
    }
}

public struct ETASample: Sendable {
    public let timestamp: TimeInterval
    public let progress: Double
    public let height: Int

    public init(timestamp: TimeInterval, progress: Double, height: Int) {
        self.timestamp = timestamp
        self.progress = progress
        self.height = height
    }
}

public final class AdaptiveETAEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [ETASample] = []
    public let maxSamples: Int
    public let warmupSeconds: TimeInterval
    public let stallThresholdSeconds: TimeInterval

    public init(
        maxSamples: Int = 120,
        warmupSeconds: TimeInterval = 30.0,
        stallThresholdSeconds: TimeInterval = 180.0
    ) {
        self.maxSamples = maxSamples
        self.warmupSeconds = warmupSeconds
        self.stallThresholdSeconds = stallThresholdSeconds
    }

    public func addSample(progress: Double, height: Int, now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        defer { lock.unlock() }

        // Ignore backwards progress
        if let last = samples.last, progress < last.progress {
            samples.removeAll()
        }

        samples.append(ETASample(timestamp: now, progress: progress, height: height))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }

    public func calculateETA(
        isIBD: Bool,
        peerCount: Int,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (state: ETAState, display: String) {
        lock.lock()
        defer { lock.unlock() }

        if !isIBD {
            return (.synchronized, "Synchronized")
        }

        if peerCount == 0 {
            return (.waitingForPeers, "Waiting for peers...")
        }

        guard let first = samples.first, let last = samples.last else {
            return (.calibrating, "Calibrating...")
        }

        let deltaProgress = last.progress - first.progress
        let deltaHeight = last.height - first.height

        // Check if stalled (no progress or no new updates past stall threshold)
        if (deltaProgress <= 1e-7 && deltaHeight <= 0 && (now - first.timestamp) > stallThresholdSeconds) ||
           (samples.count >= 3 && (now - last.timestamp) > stallThresholdSeconds) {
            return (.stalled, "Stalled")
        }

        let elapsed = last.timestamp - first.timestamp
        if elapsed < warmupSeconds || samples.count < 3 {
            return (.calibrating, "Calibrating...")
        }

        // Weighted progress rate per second
        let rate = deltaProgress / elapsed
        guard rate > 1e-8 else {
            return (.calibrating, "Calibrating...")
        }

        let remainingProgress = max(0.0, 1.0 - last.progress)
        let remainingSeconds = remainingProgress / rate

        let formatted = formatTimeRemaining(seconds: remainingSeconds)
        return (.estimating(seconds: remainingSeconds), formatted)
    }

    public static func format(seconds: Double) -> String {
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

    private func formatTimeRemaining(seconds: Double) -> String {
        AdaptiveETAEngine.format(seconds: seconds)
    }
}
