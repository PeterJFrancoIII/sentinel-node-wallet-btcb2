import Foundation

public struct BlockSample: Sendable {
    public let height: Int
    public let hash: String
    public let timestamp: TimeInterval
    public let targetHex: String
    public let difficulty: Double
    public let expectedHashes: Double
    public let dtRaw: TimeInterval?
    public let isValidDt: Bool

    public init(
        height: Int,
        hash: String,
        timestamp: TimeInterval,
        targetHex: String,
        previousTimestamp: TimeInterval? = nil
    ) {
        self.height = height
        self.hash = hash
        self.timestamp = timestamp
        self.targetHex = targetHex
        self.difficulty = TargetConverter.difficultyFromTarget(targetHex: targetHex)
        self.expectedHashes = TargetConverter.expectedHashesFromTarget(targetHex: targetHex)

        if let prev = previousTimestamp {
            let dt = timestamp - prev
            self.dtRaw = dt
            // Strictly positive intervals only for rate calculation
            self.isValidDt = (dt > 0)
        } else {
            self.dtRaw = nil
            self.isValidDt = false
        }
    }
}

public struct HashrateHistoryPoint: Codable, Identifiable, Sendable {
    public var id: String { "\(height)_\(timestamp)" }
    public let height: Int
    public let timestamp: TimeInterval
    public let hashratePH: Double
    public let difficulty: Double

    public init(height: Int, timestamp: TimeInterval, hashratePH: Double, difficulty: Double) {
        self.height = height
        self.timestamp = timestamp
        self.hashratePH = hashratePH
        self.difficulty = difficulty
    }
}

public struct HashrateReport: Sendable {
    public let networkHashrateHps: Double
    public let networkHashratePH: Double
    public let smoothedHashratePH: Double
    public let nominalHashratePH: Double
    public let difficulty: Double
    public let averageBlockIntervalSeconds: Double
    public let sampleCount: Int
    public let validIntervalCount: Int
    public let totalWindowSeconds: TimeInterval
    public let telemetryAgeSeconds: TimeInterval
    public let isStale: Bool
    public let hasTimestampAnomalies: Bool
    public let history: [HashrateHistoryPoint]

    public init(
        networkHashrateHps: Double,
        networkHashratePH: Double,
        smoothedHashratePH: Double = 0.0,
        nominalHashratePH: Double,
        difficulty: Double,
        averageBlockIntervalSeconds: Double = 600.0,
        sampleCount: Int,
        validIntervalCount: Int,
        totalWindowSeconds: TimeInterval,
        telemetryAgeSeconds: TimeInterval,
        isStale: Bool,
        hasTimestampAnomalies: Bool,
        history: [HashrateHistoryPoint] = []
    ) {
        self.networkHashrateHps = networkHashrateHps
        self.networkHashratePH = networkHashratePH
        self.smoothedHashratePH = smoothedHashratePH > 0 ? smoothedHashratePH : networkHashratePH
        self.nominalHashratePH = nominalHashratePH
        self.difficulty = difficulty
        self.averageBlockIntervalSeconds = averageBlockIntervalSeconds
        self.sampleCount = sampleCount
        self.validIntervalCount = validIntervalCount
        self.totalWindowSeconds = totalWindowSeconds
        self.telemetryAgeSeconds = telemetryAgeSeconds
        self.isStale = isStale
        self.hasTimestampAnomalies = hasTimestampAnomalies
        self.history = history
    }

    public var displayHashrate: String {
        formatRate(networkHashratePH)
    }

    public var displaySmoothedHashrate: String {
        formatRate(smoothedHashratePH)
    }

    private func formatRate(_ ph: Double) -> String {
        if ph >= 1000.0 {
            return String(format: "%.2f EH/s", ph / 1000.0)
        } else if ph >= 1.0 {
            return String(format: "%.2f PH/s", ph)
        } else if ph >= 0.001 {
            return String(format: "%.2f TH/s", ph * 1000.0)
        } else {
            return String(format: "%.2f GH/s", ph * 1_000_000.0)
        }
    }
}

public final class HashrateTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [BlockSample] = []
    private var historyPoints: [HashrateHistoryPoint] = []
    public let windowSize: Int
    public let maxTelemetryAgeSeconds: TimeInterval

    public init(windowSize: Int = 30, maxTelemetryAgeSeconds: TimeInterval = 300.0) {
        self.windowSize = windowSize
        self.maxTelemetryAgeSeconds = maxTelemetryAgeSeconds
    }

    public func addBlock(height: Int, hash: String, timestamp: TimeInterval, targetHex: String) {
        lock.lock()
        defer { lock.unlock() }

        // Deduplicate unchanged tip polling
        if let last = samples.last, last.hash == hash || last.height == height {
            return
        }

        // Handle reorgs: prune invalid branches
        if let last = samples.last, height <= last.height {
            samples.removeAll(where: { $0.height >= height })
        }

        let isContiguous = (samples.last == nil) || (height == (samples.last!.height + 1))
        let previousTimestamp = isContiguous ? samples.last?.timestamp : nil

        let sample = BlockSample(
            height: height,
            hash: hash,
            timestamp: timestamp,
            targetHex: targetHex,
            previousTimestamp: previousTimestamp
        )

        samples.append(sample)
        if samples.count > windowSize * 4 {
            samples.removeFirst(samples.count - (windowSize * 2))
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        historyPoints.removeAll()
    }

    public func generateReport(now: TimeInterval = Date().timeIntervalSince1970) -> HashrateReport {
        lock.lock()
        defer { lock.unlock() }

        guard let latest = samples.last else {
            return HashrateReport(
                networkHashrateHps: 0.0,
                networkHashratePH: 0.0,
                smoothedHashratePH: 0.0,
                nominalHashratePH: 0.0,
                difficulty: 0.0,
                averageBlockIntervalSeconds: 600.0,
                sampleCount: 0,
                validIntervalCount: 0,
                totalWindowSeconds: 0.0,
                telemetryAgeSeconds: 0.0,
                isStale: true,
                hasTimestampAnomalies: false,
                history: []
            )
        }

        let age = max(0.0, now - latest.timestamp)
        let isStale = (age > maxTelemetryAgeSeconds)
        let nominalPH = TargetConverter.nominalHashratePH(expectedHashes: latest.expectedHashes)

        // Short trend (last windowSize samples, e.g. 30 blocks)
        let shortSamples = Array(samples.suffix(windowSize))
        var totalExpectedHashes = 0.0
        var totalValidSeconds = 0.0
        var validIntervals = 0
        var anomaliesDetected = false

        for sample in shortSamples {
            if let dt = sample.dtRaw {
                if dt <= 0 {
                    anomaliesDetected = true
                } else {
                    totalExpectedHashes += sample.expectedHashes
                    totalValidSeconds += dt
                    validIntervals += 1
                }
            }
        }

        let calculatedHps: Double
        if validIntervals > 0 && totalValidSeconds > 0 {
            calculatedHps = totalExpectedHashes / totalValidSeconds
        } else {
            calculatedHps = latest.expectedHashes / 600.0
        }

        let networkPH = calculatedHps / 1e15

        // Smoothed trend (up to 4x windowSize samples, e.g. 120 blocks)
        let longSamples = Array(samples.suffix(windowSize * 4))
        var longExpectedHashes = 0.0
        var longValidSeconds = 0.0
        var longIntervals = 0

        for sample in longSamples {
            if let dt = sample.dtRaw, dt > 0 {
                longExpectedHashes += sample.expectedHashes
                longValidSeconds += dt
                longIntervals += 1
            }
        }

        let smoothedHps = (longIntervals > 0 && longValidSeconds > 0) ? (longExpectedHashes / longValidSeconds) : calculatedHps
        let smoothedPH = smoothedHps / 1e15

        let avgInterval = validIntervals > 0 ? (totalValidSeconds / Double(validIntervals)) : 600.0

        // Append to history points (max 30 points)
        if historyPoints.last?.height != latest.height {
            historyPoints.append(HashrateHistoryPoint(
                height: latest.height,
                timestamp: latest.timestamp,
                hashratePH: networkPH,
                difficulty: latest.difficulty
            ))
            if historyPoints.count > 30 {
                historyPoints.removeFirst(historyPoints.count - 30)
            }
        }

        return HashrateReport(
            networkHashrateHps: calculatedHps,
            networkHashratePH: networkPH,
            smoothedHashratePH: smoothedPH,
            nominalHashratePH: nominalPH,
            difficulty: latest.difficulty,
            averageBlockIntervalSeconds: avgInterval,
            sampleCount: shortSamples.count,
            validIntervalCount: validIntervals,
            totalWindowSeconds: totalValidSeconds,
            telemetryAgeSeconds: age,
            isStale: isStale,
            hasTimestampAnomalies: anomaliesDetected,
            history: historyPoints
        )
    }
}
