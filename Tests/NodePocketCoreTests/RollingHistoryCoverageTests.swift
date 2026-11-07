import XCTest
@testable import NodePocketCore

/// Standalone deterministic tests: no full-history node, external APIs,
/// TestNet/RegTest, wallet creation or real funds are needed.
final class RollingHistoryCoverageTests: XCTestCase {
    private let day = 86_400.0
    private let gib: Int64 = 1_073_741_824
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(
        days: Double = 10,
        bytes: Int64? = 3 * 1_073_741_824,
        target: Int64? = 4 * 1_073_741_824,
        ibd: Bool = false
    ) -> RollingHistoryCoverage {
        RollingHistoryCoverage(
            firstRetainedHeight: 900_000,
            tipHeight: 902_000,
            firstRetainedTimestamp: now.timeIntervalSince1970 - days * day,
            tipTimestamp: now.timeIntervalSince1970,
            observedBlockUndoBytes: bytes,
            effectivePruneTargetBytes: target,
            initialBlockDownload: ibd,
            measuredAt: now
        )!
    }

    func testYearsMonthsWeeksDaysHoursAutoSwitch() {
        let format = RollingHistoryDurationFormatter.string(from:)
        XCTAssertEqual(format(732 * day), "2 years, 1 day")
        XCTAssertEqual(format(65 * day), "2 months, 4 days")
        XCTAssertEqual(format(17 * day), "2 weeks, 3 days")
        XCTAssertEqual(format(3 * day + 7 * 3600), "3 days, 7 hours")
        XCTAssertEqual(format(8 * 3600), "8 hours")
        XCTAssertEqual(format(600), "<1 hour")
        XCTAssertEqual(format(.nan), "Measuring…")
        XCTAssertEqual(format(-30), "Measuring…")
    }

    func testLiveRPCMeasurementsProduceActualCoverage() {
        let coverage = sample(days: 10)
        XCTAssertEqual(coverage.firstRetainedHeight, 900_000)
        XCTAssertEqual(coverage.tipHeight, 902_000)
        XCTAssertEqual(coverage.retainedBlockCount, 2_001)
        XCTAssertEqual(coverage.actualHistorySeconds, 10 * day, accuracy: 0.001)
        XCTAssertEqual(coverage.actualDisplay, "~1 week, 3 days")
        XCTAssertTrue(coverage.description.contains("at current chain tip"))
        XCTAssertTrue(coverage.isProjectionCalibrated)
    }

    func testChangingSelectedPruneLimitCalculatesInstantNewForecast() {
        let coverage = sample()
        let projected = coverage.projectedHistorySeconds(forPruneMiB: 2048)
        XCTAssertNotNil(projected)
        XCTAssertEqual(projected!, 10 * day * (2.0 / 3.0), accuracy: 1)
        XCTAssertEqual(coverage.projectedDisplay(forPruneMiB: 2048), "~6 days, 16 hours")
        let larger = coverage.projectedHistorySeconds(forPruneMiB: 4096)
        XCTAssertNotNil(larger)
        XCTAssertGreaterThan(larger!, projected!)
        // Changing a UI selection never changes measured ACTUAL coverage.
        XCTAssertEqual(coverage.actualHistorySeconds, 10 * day, accuracy: 0.001)
    }

    func testDuringIBDReportsActualButNotProjectedTipCoverage() {
        let coverage = sample(ibd: true)
        XCTAssertFalse(coverage.isProjectionCalibrated)
        XCTAssertEqual(coverage.actualDisplay, "~1 week, 3 days")
        XCTAssertTrue(coverage.description.contains("verified sync height"))
        XCTAssertTrue(coverage.projectedDisplay(forPruneMiB: 2048).contains("Calibrating"))
    }

    func testUnsettledOrMissingSizeDoesNotInventYearsOfCoverage() {
        XCTAssertFalse(sample(bytes: nil).isProjectionCalibrated)
        XCTAssertNil(sample(bytes: nil).projectedHistorySeconds(forPruneMiB: 2048))
        XCTAssertFalse(sample(bytes: 20 * gib).isProjectionCalibrated)
        XCTAssertFalse(sample(bytes: gib / 5).isProjectionCalibrated)
        XCTAssertFalse(sample(target: nil).isProjectionCalibrated)
        XCTAssertNil(sample().projectedHistorySeconds(forPruneMiB: 549))
    }

    func testInvalidBlockAgeAndFutureHeightAreRejected() {
        XCTAssertNil(RollingHistoryCoverage(
            firstRetainedHeight: 200,
            tipHeight: 100,
            firstRetainedTimestamp: now.timeIntervalSince1970 - day,
            tipTimestamp: now.timeIntervalSince1970,
            observedBlockUndoBytes: gib,
            effectivePruneTargetBytes: gib,
            initialBlockDownload: false
        ))
        XCTAssertNil(RollingHistoryCoverage(
            firstRetainedHeight: 100,
            tipHeight: 200,
            firstRetainedTimestamp: now.timeIntervalSince1970 + day,
            tipTimestamp: now.timeIntervalSince1970,
            observedBlockUndoBytes: gib,
            effectivePruneTargetBytes: gib,
            initialBlockDownload: false
        ))
    }

    func testMinimumHistoryWindowForSmallPruneSelection() {
        let coverage = sample(days: 20)
        let estimate = coverage.projectedHistorySeconds(forPruneMiB: 550)
        XCTAssertNotNil(estimate)
        let secondsPerBlock = coverage.actualHistorySeconds / 2_000.0
        XCTAssertGreaterThanOrEqual(estimate!, 288.0 * secondsPerBlock)
    }
}
