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

    func testMACDNumericalContinuityAcrossAllSixWindows() {
        // Build 1100 points of fluctuating hashrate history
        var history: [HashrateHistoryPoint] = []
        let baseTime: TimeInterval = 1700000000

        for i in 0..<1100 {
            // Non-trivial fluctuating pattern: 40 + 15 * sin(i / 15) + (i % 7)
            let rate = 40.0 + (15.0 * sin(Double(i) / 15.0)) + Double(i % 7)
            history.append(HashrateHistoryPoint(
                height: 1000 + i,
                timestamp: baseTime + Double(i * 600),
                hashratePH: rate,
                difficulty: 80000000.0
            ))
        }

        let report = HashrateReport(
            networkHashrateHps: 5e16,
            networkHashratePH: 50.0,
            smoothedHashratePH: 48.0,
            nominalHashratePH: 50.0,
            difficulty: 80000000.0,
            sampleCount: 30,
            validIntervalCount: 29,
            totalWindowSeconds: 17400,
            telemetryAgeSeconds: 10,
            isStale: false,
            hasTimestampAnomalies: false,
            history: history
        )

        // Baseline 30-block MACD
        let report30 = report.macdReport(window: .blocks30, fast: 12, slow: 30, signal: 9)
        XCTAssertEqual(report30.points.count, 30)

        // Verify across all six rolling windows: tip indicator values must be mathematically identical
        for win in RollingHistoryWindow.allCases {
            let winReport = report.macdReport(window: win, fast: 12, slow: 30, signal: 9)
            XCTAssertEqual(winReport.points.count, win.rawValue, "Window \(win.rawValue) should have \(win.rawValue) points")

            // Indicator metrics at tip
            XCTAssertEqual(winReport.currentMACD, report30.currentMACD, accuracy: 1e-9,
                           "Tip MACD must be identical across window \(win.rawValue)")
            XCTAssertEqual(winReport.currentSignal, report30.currentSignal, accuracy: 1e-9,
                           "Tip Signal must be identical across window \(win.rawValue)")
            XCTAssertEqual(winReport.currentHistogram, report30.currentHistogram, accuracy: 1e-9,
                           "Tip Histogram must be identical across window \(win.rawValue)")
            XCTAssertEqual(winReport.trend, report30.trend,
                           "Trend classification must be identical across window \(win.rawValue)")

            // Last point in the points array
            let lastPt = winReport.points.last!
            let lastPt30 = report30.points.last!
            XCTAssertEqual(lastPt.height, lastPt30.height)
            XCTAssertEqual(lastPt.macd, lastPt30.macd, accuracy: 1e-9)
            XCTAssertEqual(lastPt.signal, lastPt30.signal, accuracy: 1e-9)
            XCTAssertEqual(lastPt.histogram, lastPt30.histogram, accuracy: 1e-9)
            XCTAssertEqual(lastPt.fastEMA, lastPt30.fastEMA, accuracy: 1e-9)
            XCTAssertEqual(lastPt.slowEMA, lastPt30.slowEMA, accuracy: 1e-9)
        }
    }

    func testMACDExecutionPerformanceUnder10ms() {
        var history: [HashrateHistoryPoint] = []
        let baseTime: TimeInterval = 1700000000

        for i in 0..<1200 {
            let rate = 45.0 + (10.0 * cos(Double(i) / 20.0))
            history.append(HashrateHistoryPoint(
                height: 1000 + i,
                timestamp: baseTime + Double(i * 600),
                hashratePH: rate,
                difficulty: 85000000.0
            ))
        }

        let start = CFAbsoluteTimeGetCurrent()
        let report = MACDCalculator.calculate(history: history, fastPeriod: 12, slowPeriod: 30, signalPeriod: 9)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0 // milliseconds

        XCTAssertEqual(report.points.count, 1200)
        XCTAssertLessThan(elapsed, 10.0, "1200-point MACD calculation should complete in <10ms; actual: \(elapsed)ms")
    }

    func testMACDInsufficiencyPreservesAvailablePoints() {
        var history: [HashrateHistoryPoint] = []
        for i in 0..<20 {
            history.append(HashrateHistoryPoint(
                height: 100 + i,
                timestamp: 1700000000 + Double(i * 600),
                hashratePH: 42.0,
                difficulty: 100.0
            ))
        }

        let report = HashrateReport(
            networkHashrateHps: 4e16,
            networkHashratePH: 40.0,
            nominalHashratePH: 40.0,
            difficulty: 100.0,
            sampleCount: 20,
            validIntervalCount: 19,
            totalWindowSeconds: 11400,
            telemetryAgeSeconds: 10,
            isStale: false,
            hasTimestampAnomalies: false,
            history: history
        )

        // For window of 960 with only 20 points, should return all 20 points safely
        let macd960 = report.macdReport(window: .blocks960, fast: 12, slow: 30, signal: 9)
        XCTAssertEqual(macd960.points.count, 20)
        XCTAssertEqual(macd960.points.last?.height, 119)
    }
}
