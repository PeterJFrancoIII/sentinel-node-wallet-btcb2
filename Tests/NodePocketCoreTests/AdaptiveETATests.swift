import XCTest
@testable import NodePocketCore

final class AdaptiveETATests: XCTestCase {
    func testTimeRemainingFormatting() {
        // Seconds (< 60s)
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 47), "~47s")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 1), "~1s")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 0), "~0s")

        // Minutes (< 60m)
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 18 * 60 + 42), "~18m 42s")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 5 * 60), "~5m")

        // Hours (< 24h)
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 5 * 3600 + 24 * 60), "~5h 24m")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 2 * 3600), "~2h")

        // Days (< 2w)
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 3 * 86400 + 7 * 3600), "~3d 7h")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 1 * 86400), "~1d")

        // Weeks (>= 2w)
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 14 * 86400 + 3 * 86400), "~2w 3d")
        XCTAssertEqual(AdaptiveETAEngine.format(seconds: 21 * 86400), "~3w")
    }

    func testEngineStateTransitions() {
        let engine = AdaptiveETAEngine(warmupSeconds: 10.0, stallThresholdSeconds: 30.0)

        // 1. Not in IBD -> Synchronized
        let syncResult = engine.calculateETA(isIBD: false, peerCount: 8)
        XCTAssertEqual(syncResult.state, .synchronized)
        XCTAssertEqual(syncResult.display, "Synchronized")

        // 2. In IBD, 0 peers -> Waiting for peers
        let peerResult = engine.calculateETA(isIBD: true, peerCount: 0)
        XCTAssertEqual(peerResult.state, .waitingForPeers)

        // 3. In IBD, with peers, no samples -> Calibrating
        let calResult = engine.calculateETA(isIBD: true, peerCount: 8)
        XCTAssertEqual(calResult.state, .calibrating)

        // 4. In IBD, add samples within warmup period -> Still Calibrating
        let t0: TimeInterval = 1000.0
        engine.addSample(progress: 0.01, height: 100000, now: t0)
        engine.addSample(progress: 0.02, height: 101000, now: t0 + 2.0)
        engine.addSample(progress: 0.03, height: 102000, now: t0 + 5.0)

        let warmupResult = engine.calculateETA(isIBD: true, peerCount: 8, now: t0 + 5.0)
        XCTAssertEqual(warmupResult.state, .calibrating)

        // 5. Add sample past warmup period -> Estimating
        engine.addSample(progress: 0.10, height: 110000, now: t0 + 20.0)
        let estResult = engine.calculateETA(isIBD: true, peerCount: 8, now: t0 + 20.0)
        if case .estimating(let secs) = estResult.state {
            XCTAssertTrue(secs > 0)
            XCTAssertTrue(estResult.display.starts(with: "~"))
        } else {
            XCTFail("Expected estimating state but got \(estResult.state)")
        }

        // 6. Stalled check
        engine.clear()
        engine.addSample(progress: 0.50, height: 500000, now: t0)
        engine.addSample(progress: 0.50, height: 500000, now: t0 + 2.0)
        engine.addSample(progress: 0.50, height: 500000, now: t0 + 5.0)
        let stalledResult = engine.calculateETA(isIBD: true, peerCount: 8, now: t0 + 200.0)
        XCTAssertEqual(stalledResult.state, .stalled)
        XCTAssertEqual(stalledResult.display, "Stalled")
    }
}
