import XCTest
@testable import NodePocketCore

final class SystemHealthTests: XCTestCase {
    func testSystemHealthMonitorProducesValidMetrics() {
        let rootDir = URL(fileURLWithPath: NSHomeDirectory())
        let snapshot = SystemHealthMonitor.shared.checkHealth(dataDirectory: rootDir)

        XCTAssertGreaterThan(snapshot.freeDiskBytes, 0, "Valid host filesystem must report strictly positive free bytes")
        XCTAssertGreaterThan(snapshot.freeDiskGB, 0.0)
        XCTAssertFalse(snapshot.isDiskSpaceUnknown)
        XCTAssertFalse(snapshot.thermalDescription.isEmpty)
    }

    func testSystemHealthMonitorUnavailablePathReturnsUnknown() {
        let unavailableDir = URL(fileURLWithPath: "/dev/null/non_existent_mount_\(UUID().uuidString)")
        let snapshot = SystemHealthMonitor.shared.checkHealth(dataDirectory: unavailableDir)

        XCTAssertEqual(snapshot.freeDiskBytes, -1)
        XCTAssertTrue(snapshot.isDiskSpaceUnknown)
        XCTAssertEqual(snapshot.freeDiskGB, -1.0)
        XCTAssertFalse(snapshot.isDiskSpaceLow)
        XCTAssertEqual(snapshot.diskCapacityDescription, "Unknown disk capacity")
    }

    func testSystemHealthSnapshotZeroFreeDiskSpaceIsLowAndNotUnknown() {
        let snapshot = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: 0,
            powerState: .charging,
            isLowPowerMode: false
        )

        XCTAssertFalse(snapshot.isDiskSpaceUnknown)
        XCTAssertEqual(snapshot.freeDiskBytes, 0)
        XCTAssertEqual(snapshot.freeDiskGB, 0.0)
        XCTAssertTrue(snapshot.isDiskSpaceLow)
        XCTAssertTrue(snapshot.isDiskSpaceCritical)
        XCTAssertEqual(snapshot.diskCapacityDescription, "0 B available (Critical: full)")
    }

    func testSystemHealthSnapshotNegativeFreeDiskSpaceIsUnknown() {
        let snapshot = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: -1,
            powerState: .charging,
            isLowPowerMode: false
        )

        XCTAssertTrue(snapshot.isDiskSpaceUnknown)
        XCTAssertEqual(snapshot.freeDiskBytes, -1)
        XCTAssertEqual(snapshot.freeDiskGB, -1.0)
        XCTAssertFalse(snapshot.isDiskSpaceLow)
        XCTAssertFalse(snapshot.isDiskSpaceCritical)
        XCTAssertEqual(snapshot.diskCapacityDescription, "Unknown disk capacity")
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
