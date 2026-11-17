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

    func testHashrateSyncGatingAndReport() {
        let tracker = HashrateTracker(windowSize: 30)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        // Even if blocks are added, when isSyncing is true, report must indicate syncing with 0 hashrate
        for i in 0..<10 {
            tracker.addBlock(height: 100 + i, hash: "b_\(i)", timestamp: 1700000000 + Double(i * 10), targetHex: targetHex)
        }

        let report = tracker.generateReport(now: 1700000200, isSyncing: true)
        XCTAssertTrue(report.isSyncing)
        XCTAssertEqual(report.sampleCount, 0)
        XCTAssertEqual(report.networkHashrateHps, 0.0)
        XCTAssertEqual(report.networkHashratePH, 0.0)
    }

    func testConsensusOverride30And120() {
        let tracker = HashrateTracker(windowSize: 30)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        let baseTime: TimeInterval = 1700000000
        for i in 0..<31 {
            tracker.addBlock(height: 1000 + i, hash: "hash_\(i)", timestamp: baseTime + Double(i * 600), targetHex: targetHex)
        }

        // Knots consensus rate: e.g. 35.38 PH/s (3.538e16 H/s)
        let knots30Rate: Double = 3.538e16
        let knots120Rate: Double = 3.412e16

        let report = tracker.generateReport(
            now: baseTime + (30 * 600) + 5,
            override30Hps: knots30Rate,
            override120Hps: knots120Rate,
            isSyncing: false
        )

        XCTAssertFalse(report.isSyncing)
        XCTAssertEqual(report.sampleCount, 30)
        XCTAssertEqual(report.networkHashrateHps, knots30Rate, accuracy: 1.0)
        XCTAssertEqual(report.networkHashratePH, knots30Rate / 1e15, accuracy: 0.01)
        XCTAssertEqual(report.smoothedHashratePH, knots120Rate / 1e15, accuracy: 0.01)
    }

    func testRollingHistoryWindowProperties() {
        let expectedWindows: [RollingHistoryWindow] = [.blocks30, .blocks60, .blocks120, .blocks240, .blocks480, .blocks960]
        XCTAssertEqual(RollingHistoryWindow.allCases, expectedWindows)
        XCTAssertEqual(RollingHistoryWindow.defaultWindow, .blocks30)
        XCTAssertEqual(RollingHistoryWindow.maxBlocks, 960)
        XCTAssertEqual(RollingHistoryWindow.maxCapacity, 1200)

        for win in RollingHistoryWindow.allCases {
            XCTAssertEqual(win.displayName, "\(win.rawValue) Blocks")
            XCTAssertEqual(win.shortName, "\(win.rawValue)B")
            XCTAssertEqual(win.id, win.rawValue)
        }
    }

    func testMultiWindowHistorySlicingUpTo960() {
        let tracker = HashrateTracker(windowSize: 30, maxCapacity: 1200)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"
        let baseTime: TimeInterval = 1700000000
        let totalBlocks = 1000

        for i in 0..<totalBlocks {
            tracker.addBlock(
                height: 1000 + i,
                hash: "hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }

        let report = tracker.generateReport(now: baseTime + Double((totalBlocks - 1) * 600) + 10)
        let tipHeight = 1000 + totalBlocks - 1 // 1999

        for win in RollingHistoryWindow.allCases {
            let sliced = report.history(for: win)
            XCTAssertEqual(sliced.count, win.rawValue, "Window \(win.rawValue) should contain exactly \(win.rawValue) points")
            XCTAssertEqual(sliced.last?.height, tipHeight, "Window \(win.rawValue) last point must be chain tip")
            let expectedStartHeight = tipHeight - win.rawValue + 1
            XCTAssertEqual(sliced.first?.height, expectedStartHeight, "Window \(win.rawValue) first point must match window range")
        }
    }

    func testHistorySlicingWithInsufficientBlocks() {
        let tracker = HashrateTracker(windowSize: 30, maxCapacity: 1200)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"
        let baseTime: TimeInterval = 1700000000

        // Only 45 blocks available
        for i in 0..<45 {
            tracker.addBlock(
                height: 500 + i,
                hash: "hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }

        let report = tracker.generateReport(now: baseTime + (44 * 600) + 10)
        XCTAssertEqual(report.history(for: .blocks30).count, 30)

        // For windows >= 60, report must safely return all available history points without crashing
        let totalPoints = report.history.count
        XCTAssertEqual(report.history(for: .blocks60).count, totalPoints)
        XCTAssertEqual(report.history(for: .blocks120).count, totalPoints)
        XCTAssertEqual(report.history(for: .blocks240).count, totalPoints)
        XCTAssertEqual(report.history(for: .blocks480).count, totalPoints)
        XCTAssertEqual(report.history(for: .blocks960).count, totalPoints)
    }

    func testSeedBlocksIngestionAndMaxCapacityCap() {
        let tracker = HashrateTracker(windowSize: 30, maxCapacity: 1200)
        var headers: [BlockHeader] = []
        let baseTime: Int = 1700000000

        for i in 0..<1400 {
            let prev: String? = i > 0 ? "hash_\(i - 1)" : nil
            let header = BlockHeader(
                hash: "hash_\(i)",
                confirmations: 1,
                height: 1000 + i,
                time: baseTime + (i * 600),
                mediantime: baseTime + (i * 600),
                bits: "1d00ffff",
                difficulty: 1.0,
                chainwork: "00",
                previousblockhash: prev
            )
            headers.append(header)
        }

        tracker.seedBlocks(headers: headers)
        XCTAssertEqual(tracker.sampleCount, 1200, "Tracker sampleCount must be capped at maxCapacity (1200)")
        XCTAssertEqual(tracker.latestHeight, 1000 + 1399, "Latest height must reflect the latest seeded header")
    }

    func testReorgPruningAndBranchInvalidation() {
        let tracker = HashrateTracker(windowSize: 30, maxCapacity: 1200)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"
        let baseTime: TimeInterval = 1700000000

        for i in 0..<50 {
            tracker.addBlock(
                height: 100 + i,
                hash: "original_hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }
        XCTAssertEqual(tracker.latestHeight, 149)

        // Reorg: at height 140, a competing branch arrives with a different hash
        tracker.addBlock(
            height: 140,
            hash: "reorg_hash_140",
            timestamp: baseTime + Double(40 * 600) + 30,
            targetHex: targetHex
        )

        // Samples above 140 must have been pruned; latest height is now 140
        XCTAssertEqual(tracker.latestHeight, 140)

        // Append new branch blocks up to 143
        for i in 141...143 {
            tracker.addBlock(
                height: i,
                hash: "reorg_hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }
        XCTAssertEqual(tracker.latestHeight, 143)

        let report = tracker.generateReport(now: baseTime + (43 * 600) + 10)
        XCTAssertEqual(report.history.last?.height, 143)
        XCTAssertEqual(report.history.last?.hashratePH, report.networkHashratePH)
    }

    func testHeadlineRatesDecoupledFromHistoryWindow() {
        let tracker = HashrateTracker(windowSize: 30, maxCapacity: 1200)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"
        let baseTime: TimeInterval = 1700000000

        for i in 0..<500 {
            tracker.addBlock(
                height: 1000 + i,
                hash: "hash_\(i)",
                timestamp: baseTime + Double(i * 600),
                targetHex: targetHex
            )
        }

        let report = tracker.generateReport(now: baseTime + (499 * 600) + 10)

        // Canonical headline 30-block rate and smoothed 120-block rate
        let headlineRate = report.networkHashratePH
        let smoothedRate = report.smoothedHashratePH

        XCTAssertGreaterThan(headlineRate, 0.0)
        XCTAssertGreaterThan(smoothedRate, 0.0)

        // Requesting 30-block vs 960-block history slices does NOT change the report's headline rates
        let slice30 = report.history(for: .blocks30)
        let slice960 = report.history(for: .blocks960)

        XCTAssertEqual(slice30.count, 30)
        XCTAssertEqual(slice960.count, 499) // All available history points
        XCTAssertEqual(report.networkHashratePH, headlineRate)
        XCTAssertEqual(report.smoothedHashratePH, smoothedRate)
    }
}
