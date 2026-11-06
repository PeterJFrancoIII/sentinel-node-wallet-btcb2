import XCTest
@testable import NodePocketCore

final class HashrateTrackerTests: XCTestCase {
    func testHashrateWindowCalculation() {
        let tracker = HashrateTracker(windowSize: 5, maxTelemetryAgeSeconds: 300.0)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000" // Diff 1

        let baseTime: TimeInterval = 1700000000
        // Add 5 blocks each spaced exactly 600s apart
        for i in 0..<5 {
            tracker.addBlock(
                height: 100 + i,
                hash: "block_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }

        let report = tracker.generateReport(now: baseTime + (4 * 600) + 10) // 10s after last block
        XCTAssertEqual(report.sampleCount, 5)
        XCTAssertEqual(report.validIntervalCount, 4)
        XCTAssertFalse(report.isStale)
        XCTAssertFalse(report.hasTimestampAnomalies)
        XCTAssertEqual(report.difficulty, 1.0, accuracy: 0.0001)

        // Diff 1 expected hashes = 2^32. Interval = 600s. Rate = 2^32 / 600 H/s = ~7,158,278 H/s = ~0.007158 GH/s
        let expectedHps = pow(2.0, 32.0) / 600.0
        XCTAssertEqual(report.networkHashrateHps, expectedHps, accuracy: 1.0)
    }

    func testTimestampAnomalyHandling() {
        let tracker = HashrateTracker(windowSize: 5)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        let baseTime: TimeInterval = 1700000000
        tracker.addBlock(height: 1, hash: "b1", timestamp: baseTime, targetHex: targetHex)
        // Next block has equal or backward timestamp (anomaly)
        tracker.addBlock(height: 2, hash: "b2", timestamp: baseTime - 10, targetHex: targetHex)

        let report = tracker.generateReport(now: baseTime + 50)
        XCTAssertTrue(report.hasTimestampAnomalies)
        // Rate calculation must not crash or explode
        XCTAssertGreaterThanOrEqual(report.networkHashrateHps, 0.0)
    }

    func testStaleTelemetryFlag() {
        let tracker = HashrateTracker(windowSize: 5, maxTelemetryAgeSeconds: 300.0)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        let blockTime: TimeInterval = 1700000000
        tracker.addBlock(height: 1, hash: "b1", timestamp: blockTime, targetHex: targetHex)

        // Now is 400 seconds later (exceeds 300s limit)
        let report = tracker.generateReport(now: blockTime + 400.0)
        XCTAssertTrue(report.isStale)
        XCTAssertEqual(report.telemetryAgeSeconds, 400.0, accuracy: 0.1)
    }
}
