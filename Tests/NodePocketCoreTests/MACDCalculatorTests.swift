import XCTest
@testable import NodePocketCore

final class MACDCalculatorTests: XCTestCase {
    func testEmptyHistoryReturnsNeutralReport() {
        let report = MACDCalculator.calculate(history: [])
        XCTAssertTrue(report.points.isEmpty)
        XCTAssertEqual(report.currentMACD, 0.0)
        XCTAssertEqual(report.currentSignal, 0.0)
        XCTAssertEqual(report.currentHistogram, 0.0)
        XCTAssertEqual(report.trend, .neutral)
        XCTAssertFalse(report.isPositiveDivergence)
    }

    func testSinglePointHistory() {
        let history = [
            HashrateHistoryPoint(height: 100, timestamp: 1700000000, hashratePH: 42.0, difficulty: 1.0)
        ]
        let report = MACDCalculator.calculate(history: history, fastPeriod: 12, slowPeriod: 30, signalPeriod: 9)
        XCTAssertEqual(report.points.count, 1)
        let pt = report.points[0]
        XCTAssertEqual(pt.height, 100)
        XCTAssertEqual(pt.fastEMA, 42.0, accuracy: 0.001)
        XCTAssertEqual(pt.slowEMA, 42.0, accuracy: 0.001)
        XCTAssertEqual(pt.macd, 0.0, accuracy: 0.001)
        XCTAssertEqual(pt.signal, 0.0, accuracy: 0.001)
        XCTAssertEqual(pt.histogram, 0.0, accuracy: 0.001)
        XCTAssertEqual(report.trend, .neutral)
    }

    func testConstantHashrateFlatHistogram() {
        var history: [HashrateHistoryPoint] = []
        for i in 0..<30 {
            history.append(HashrateHistoryPoint(
                height: 1000 + i,
                timestamp: 1700000000 + Double(i * 600),
                hashratePH: 40.0,
                difficulty: 65000000.0
            ))
        }

        let report = MACDCalculator.calculate(history: history, fastPeriod: 12, slowPeriod: 30, signalPeriod: 9)
        XCTAssertEqual(report.points.count, 30)
        for pt in report.points {
            XCTAssertEqual(pt.fastEMA, 40.0, accuracy: 0.001)
            XCTAssertEqual(pt.slowEMA, 40.0, accuracy: 0.001)
            XCTAssertEqual(pt.macd, 0.0, accuracy: 0.001)
            XCTAssertEqual(pt.signal, 0.0, accuracy: 0.001)
            XCTAssertEqual(pt.histogram, 0.0, accuracy: 0.001)
        }
        XCTAssertEqual(report.trend, .neutral)
    }

    func testRisingHashrateBullishExpansion() {
        // Hashrate steadily increasing from 30 PH/s up to 60 PH/s across 30 blocks
        var history: [HashrateHistoryPoint] = []
        for i in 0..<30 {
            let rate = 30.0 + (Double(i) * 1.0)
            history.append(HashrateHistoryPoint(
                height: 5000 + i,
                timestamp: 1700000000 + Double(i * 600),
                hashratePH: rate,
                difficulty: 65000000.0
            ))
        }

        let report = MACDCalculator.calculate(history: history, fastPeriod: 12, slowPeriod: 30, signalPeriod: 9)
        XCTAssertEqual(report.points.count, 30)

        let last = report.points.last!
        // In a rising trend, Fast EMA must exceed Slow EMA
        XCTAssertGreaterThan(last.fastEMA, last.slowEMA)
        // MACD line (Fast - Slow) must be strictly positive
        XCTAssertGreaterThan(last.macd, 0.0)
        // Divergence histogram should be positive and classified as bullish
        XCTAssertGreaterThan(last.histogram, 0.0)
        XCTAssertTrue(report.trend.isBullish)
        XCTAssertTrue(report.isPositiveDivergence)
    }

    func testFallingHashrateBearishExpansion() {
        // Hashrate steadily dropping from 60 PH/s down to 30 PH/s across 30 blocks
        var history: [HashrateHistoryPoint] = []
        for i in 0..<30 {
            let rate = 60.0 - (Double(i) * 1.0)
            history.append(HashrateHistoryPoint(
                height: 5000 + i,
                timestamp: 1700000000 + Double(i * 600),
                hashratePH: rate,
                difficulty: 65000000.0
            ))
        }

        let report = MACDCalculator.calculate(history: history, fastPeriod: 12, slowPeriod: 30, signalPeriod: 9)
        XCTAssertEqual(report.points.count, 30)

        let last = report.points.last!
        // In a falling trend, Fast EMA must be below Slow EMA
        XCTAssertLessThan(last.fastEMA, last.slowEMA)
        // MACD line must be strictly negative
        XCTAssertLessThan(last.macd, 0.0)
        // Divergence histogram should be negative and classified as bearish
        XCTAssertLessThan(last.histogram, 0.0)
        XCTAssertTrue(report.trend.isBearish)
        XCTAssertFalse(report.isPositiveDivergence)
    }

    func testCustomPeriodsAndReportConvenience() {
        var history: [HashrateHistoryPoint] = []
        for i in 0..<30 {
            history.append(HashrateHistoryPoint(
                height: 100 + i,
                timestamp: 1700000000 + Double(i * 600),
                hashratePH: Double(40 + (i % 5)),
                difficulty: 100.0
            ))
        }

        let hashrateReport = HashrateReport(
            networkHashrateHps: 4e16,
            networkHashratePH: 40.0,
            nominalHashratePH: 40.0,
            difficulty: 100.0,
            sampleCount: 30,
            validIntervalCount: 29,
            totalWindowSeconds: 17400,
            telemetryAgeSeconds: 10,
            isStale: false,
            hasTimestampAnomalies: false,
            history: history
        )

        let defaultMACD = hashrateReport.macdReport
        XCTAssertEqual(defaultMACD.fastPeriod, 12)
        XCTAssertEqual(defaultMACD.slowPeriod, 30)
        XCTAssertEqual(defaultMACD.signalPeriod, 9)
        XCTAssertEqual(defaultMACD.points.count, 30)

        let customMACD = hashrateReport.macdReport(fast: 6, slow: 18, signal: 6)
        XCTAssertEqual(customMACD.fastPeriod, 6)
        XCTAssertEqual(customMACD.slowPeriod, 18)
        XCTAssertEqual(customMACD.signalPeriod, 6)
    }
}
