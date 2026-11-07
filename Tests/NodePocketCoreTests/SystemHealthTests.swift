import XCTest
@testable import NodePocketCore

final class SystemHealthTests: XCTestCase {
    func testSystemHealthMonitorProducesValidMetrics() {
        let tempDir = FileManager.default.temporaryDirectory
        let snapshot = SystemHealthMonitor.shared.checkHealth(dataDirectory: tempDir)

        XCTAssertGreaterThan(snapshot.freeDiskBytes, 0)
        XCTAssertGreaterThan(snapshot.freeDiskGB, 0.0)
        XCTAssertFalse(snapshot.thermalDescription.isEmpty)
    }

    func testSmoothedHashrateCalculation() {
        let tracker = HashrateTracker(windowSize: 5)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"
        let baseTime: TimeInterval = 1700000000

        for i in 0..<15 {
            tracker.addBlock(
                height: 1000 + i,
                hash: "block_hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }

        let report = tracker.generateReport(now: baseTime + Double(14 * 600) + 10)
        XCTAssertEqual(report.sampleCount, 5) // Window size is 5
        XCTAssertGreaterThan(report.smoothedHashratePH, 0.0)
        XCTAssertEqual(report.averageBlockIntervalSeconds, 600.0, accuracy: 1.0)
        XCTAssertFalse(report.history.isEmpty)
        XCTAssertEqual(report.history.last?.height, 1014)
    }
}
