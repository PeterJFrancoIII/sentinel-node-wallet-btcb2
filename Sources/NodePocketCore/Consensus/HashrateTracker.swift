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

public struct HashrateReport: Sendable {
    public let networkHashrateHps: Double
    public let networkHashratePH: Double
    public let nominalHashratePH: Double
    public let difficulty: Double
    public let sampleCount: Int
    public let validIntervalCount: Int
    public let totalWindowSeconds: TimeInterval
    public let telemetryAgeSeconds: TimeInterval
    public let isStale: Bool
    public let hasTimestampAnomalies: Bool

    public var displayHashrate: String {
        if networkHashratePH >= 1000.0 {
            return String(format: "%.2f EH/s", networkHashratePH / 1000.0)
        } else if networkHashratePH >= 1.0 {
            return String(format: "%.2f PH/s", networkHashratePH)
        } else if networkHashratePH >= 0.001 {
            return String(format: "%.2f TH/s", networkHashratePH * 1000.0)
        } else {
            return String(format: "%.2f GH/s", networkHashratePH * 1_000_000.0)
        }
    }
}

public final class HashrateTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [BlockSample] = []
    public let windowSize: Int
    public let maxTelemetryAgeSeconds: TimeInterval

    public init(windowSize: Int = 30, maxTelemetryAgeSeconds: TimeInterval = 300.0) {
        self.windowSize = windowSize
        self.maxTelemetryAgeSeconds = maxTelemetryAgeSeconds
    }

    public func addBlock(height: Int, hash: String, timestamp: TimeInterval, targetHex: String) {
        lock.lock()
        defer { lock.unlock() }

        let previousTimestamp = samples.last?.timestamp
        let sample = BlockSample(
            height: height,
            hash: hash,
            timestamp: timestamp,
            targetHex: targetHex,
            previousTimestamp: previousTimestamp
        )

        samples.append(sample)
        if samples.count > windowSize * 2 {
            samples.removeFirst(samples.count - windowSize)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }

    public func generateReport(now: TimeInterval = Date().timeIntervalSince1970) -> HashrateReport {
        lock.lock()
        defer { lock.unlock() }

        guard let latest = samples.last else {
            return HashrateReport(
                networkHashrateHps: 0.0,
                networkHashratePH: 0.0,
                nominalHashratePH: 0.0,
                difficulty: 0.0,
                sampleCount: 0,
                validIntervalCount: 0,
                totalWindowSeconds: 0.0,
                telemetryAgeSeconds: 0.0,
                isStale: true,
                hasTimestampAnomalies: false
            )
        }

        let age = max(0.0, now - latest.timestamp)
        let isStale = (age > maxTelemetryAgeSeconds)
        let nominalPH = TargetConverter.nominalHashratePH(expectedHashes: latest.expectedHashes)

        // Take last `windowSize` samples
        let activeSamples = Array(samples.suffix(windowSize))
        var totalExpectedHashes = 0.0
        var totalValidSeconds = 0.0
        var validIntervals = 0
        var anomaliesDetected = false

        for sample in activeSamples {
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
            // Fall back to nominal single-block hashrate if no intervals available
            calculatedHps = latest.expectedHashes / 600.0
        }

        let networkPH = calculatedHps / 1e15

        return HashrateReport(
            networkHashrateHps: calculatedHps,
            networkHashratePH: networkPH,
            nominalHashratePH: nominalPH,
            difficulty: latest.difficulty,
            sampleCount: activeSamples.count,
            validIntervalCount: validIntervals,
            totalWindowSeconds: totalValidSeconds,
            telemetryAgeSeconds: age,
            isStale: isStale,
            hasTimestampAnomalies: anomaliesDetected
        )
    }
}
