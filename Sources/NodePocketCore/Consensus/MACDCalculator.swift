import Foundation

/// Individual point representing calculated MACD metrics for a block sample in the rolling history.
public struct MACDPoint: Codable, Identifiable, Sendable, Equatable {
    public var id: String { "\(height)" }
    public let height: Int
    public let timestamp: TimeInterval
    public let hashratePH: Double
    public let fastEMA: Double
    public let slowEMA: Double
    public let macd: Double
    public let signal: Double
    public let histogram: Double // macd - signal

    public init(
        height: Int,
        timestamp: TimeInterval,
        hashratePH: Double,
        fastEMA: Double,
        slowEMA: Double,
        macd: Double,
        signal: Double,
        histogram: Double
    ) {
        self.height = height
        self.timestamp = timestamp
        self.hashratePH = hashratePH
        self.fastEMA = fastEMA
        self.slowEMA = slowEMA
        self.macd = macd
        self.signal = signal
        self.histogram = histogram
    }
}

/// Momentum classification derived from MACD line, signal line, and histogram divergence.
public enum MACDTrendSignal: String, Codable, Sendable {
    case bullishExpanding = "Bullish Momentum (Expanding)"
    case bullishContracting = "Bullish Momentum (Contracting)"
    case bearishExpanding = "Bearish Divergence (Expanding)"
    case bearishContracting = "Bearish Divergence (Contracting)"
    case neutral = "Neutral / Stable"

    public var isBullish: Bool {
        self == .bullishExpanding || self == .bullishContracting
    }

    public var isBearish: Bool {
        self == .bearishExpanding || self == .bearishContracting
    }
}

/// Comprehensive report containing calculated MACD time-series and real-time telemetry.
public struct MACDReport: Sendable, Equatable {
    public let points: [MACDPoint]
    public let fastPeriod: Int
    public let slowPeriod: Int
    public let signalPeriod: Int
    public let currentMACD: Double
    public let currentSignal: Double
    public let currentHistogram: Double
    public let trend: MACDTrendSignal

    public var isPositiveDivergence: Bool {
        currentHistogram > 0
    }

    public init(
        points: [MACDPoint],
        fastPeriod: Int = 12,
        slowPeriod: Int = 30,
        signalPeriod: Int = 9,
        currentMACD: Double = 0.0,
        currentSignal: Double = 0.0,
        currentHistogram: Double = 0.0,
        trend: MACDTrendSignal = .neutral
    ) {
        self.points = points
        self.fastPeriod = fastPeriod
        self.slowPeriod = slowPeriod
        self.signalPeriod = signalPeriod
        self.currentMACD = currentMACD
        self.currentSignal = currentSignal
        self.currentHistogram = currentHistogram
        self.trend = trend
    }
}

/// Mathematical engine for computing Exponential Moving Average Convergence Divergence over hashrate series.
public enum MACDCalculator {
    /// Computes MACD points for a given hashrate history series.
    /// - Parameters:
    ///   - history: Contiguous or ordered series of hashrate history points.
    ///   - fastPeriod: Short-term EMA window (default: 12 blocks).
    ///   - slowPeriod: Long-term EMA window (default: 30 blocks for rolling window).
    ///   - signalPeriod: EMA window for the MACD signal line (default: 9 blocks).
    /// - Returns: Complete `MACDReport` with per-block metrics and momentum classification.
    public static func calculate(
        history: [HashrateHistoryPoint],
        fastPeriod: Int = 12,
        slowPeriod: Int = 30,
        signalPeriod: Int = 9
    ) -> MACDReport {
        guard !history.isEmpty else {
            return MACDReport(
                points: [],
                fastPeriod: fastPeriod,
                slowPeriod: slowPeriod,
                signalPeriod: signalPeriod,
                currentMACD: 0.0,
                currentSignal: 0.0,
                currentHistogram: 0.0,
                trend: .neutral
            )
        }

        let fastAlpha = 2.0 / Double(max(1, fastPeriod) + 1)
        let slowAlpha = 2.0 / Double(max(1, slowPeriod) + 1)
        let signalAlpha = 2.0 / Double(max(1, signalPeriod) + 1)

        var points: [MACDPoint] = []
        var runningFastEMA: Double = 0.0
        var runningSlowEMA: Double = 0.0
        var runningSignalEMA: Double = 0.0

        for (index, item) in history.enumerated() {
            let rate = item.hashratePH

            let fastEMA: Double
            let slowEMA: Double
            if index == 0 {
                fastEMA = rate
                slowEMA = rate
                runningFastEMA = rate
                runningSlowEMA = rate
            } else {
                fastEMA = (rate * fastAlpha) + (runningFastEMA * (1.0 - fastAlpha))
                slowEMA = (rate * slowAlpha) + (runningSlowEMA * (1.0 - slowAlpha))
                runningFastEMA = fastEMA
                runningSlowEMA = slowEMA
            }

            let macd = fastEMA - slowEMA

            let signal: Double
            if index == 0 {
                signal = macd
                runningSignalEMA = macd
            } else {
                signal = (macd * signalAlpha) + (runningSignalEMA * (1.0 - signalAlpha))
                runningSignalEMA = signal
            }

            let histogram = macd - signal

            points.append(MACDPoint(
                height: item.height,
                timestamp: item.timestamp,
                hashratePH: rate,
                fastEMA: fastEMA,
                slowEMA: slowEMA,
                macd: macd,
                signal: signal,
                histogram: histogram
            ))
        }

        guard let lastPoint = points.last else {
            return MACDReport(
                points: points,
                fastPeriod: fastPeriod,
                slowPeriod: slowPeriod,
                signalPeriod: signalPeriod,
                currentMACD: 0.0,
                currentSignal: 0.0,
                currentHistogram: 0.0,
                trend: .neutral
            )
        }

        let prevPoint = points.count >= 2 ? points[points.count - 2] : nil

        let trend: MACDTrendSignal
        if abs(lastPoint.histogram) < 1e-6 {
            trend = .neutral
        } else if lastPoint.histogram > 0 {
            if let prev = prevPoint, lastPoint.histogram >= prev.histogram {
                trend = .bullishExpanding
            } else {
                trend = .bullishContracting
            }
        } else {
            if let prev = prevPoint, lastPoint.histogram <= prev.histogram {
                trend = .bearishExpanding
            } else {
                trend = .bearishContracting
            }
        }

        return MACDReport(
            points: points,
            fastPeriod: fastPeriod,
            slowPeriod: slowPeriod,
            signalPeriod: signalPeriod,
            currentMACD: lastPoint.macd,
            currentSignal: lastPoint.signal,
            currentHistogram: lastPoint.histogram,
            trend: trend
        )
    }
}
