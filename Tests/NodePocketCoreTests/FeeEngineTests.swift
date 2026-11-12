import XCTest
@testable import NodePocketCore

final class FeeEngineTests: XCTestCase {
    func testIntegerSatoshiConversions() {
        // 1 BTC = 100,000,000 sats
        XCTAssertEqual(SatoshiMath.toSats(btc: 1.0), 100_000_000)
        XCTAssertEqual(SatoshiMath.toSats(btc: 0.00000001), 1)
        XCTAssertEqual(SatoshiMath.toSats(btc: 0.5), 50_000_000)
        XCTAssertEqual(SatoshiMath.toSats(btc: 0.0), 0)

        // Sats to BTC
        XCTAssertEqual(SatoshiMath.toBTC(sats: 100_000_000), 1.0)
        XCTAssertEqual(SatoshiMath.toBTC(sats: 1), 0.00000001)

        // BTC String Formatting (fixed-point 8 decimals to prevent scientific notation in RPC)
        XCTAssertEqual(SatoshiMath.toBTCString(sats: 1), "0.00000001")
        XCTAssertEqual(SatoshiMath.toBTCString(sats: 9_718), "0.00009718")
        XCTAssertEqual(SatoshiMath.toBTCString(sats: 10_000), "0.00010000")
        XCTAssertEqual(SatoshiMath.toBTCString(sats: 100_000_000), "1.00000000")
        XCTAssertEqual(SatoshiMath.toBTCString(btc: 0.00009718), "0.00009718")
        XCTAssertEqual(SatoshiMath.toBTCString(btc: 0.00000001), "0.00000001")
        XCTAssertFalse(SatoshiMath.toBTCString(btc: 0.00009718).contains("e"))

        // Formatting
        XCTAssertEqual(SatoshiMath.formatSats(100_000_000), "100,000,000")
        XCTAssertEqual(SatoshiMath.formatSats(12345), "12,345")
    }

    func testRateToSatPerVBConversion() {
        // 0.00001 BTC/kB * 100,000 = 1 sat/vB
        XCTAssertEqual(FeeEngine.rateToSatPerVB(btcPerKB: 0.00001), 1)
        // 0.00005 BTC/kB * 100,000 = 5 sat/vB
        XCTAssertEqual(FeeEngine.rateToSatPerVB(btcPerKB: 0.00005), 5)
        // 0 or negative clamps to 1
        XCTAssertEqual(FeeEngine.rateToSatPerVB(btcPerKB: 0.0), 1)
        XCTAssertEqual(FeeEngine.rateToSatPerVB(btcPerKB: -1.0), 1)
    }

    func testFeeRateReconciliationOrdering() {
        // Enforce Fast >= Normal >= Cheapest
        let reconciled = FeeEngine.reconcileRates(cheapest: 1, normal: 2, fast: 5, relayFloor: 1)
        XCTAssertEqual(reconciled.cheapest, 1)
        XCTAssertEqual(reconciled.normal, 2)
        XCTAssertEqual(reconciled.fast, 5)

        // Inverted rates get clamped upwards
        let inverted = FeeEngine.reconcileRates(cheapest: 5, normal: 3, fast: 2, relayFloor: 1)
        XCTAssertEqual(inverted.cheapest, 5)
        XCTAssertEqual(inverted.normal, 5)
        XCTAssertEqual(inverted.fast, 5)

        // Below relay floor gets elevated
        let floorElevated = FeeEngine.reconcileRates(cheapest: 1, normal: 1, fast: 2, relayFloor: 3)
        XCTAssertEqual(floorElevated.cheapest, 3)
        XCTAssertEqual(floorElevated.normal, 3)
        XCTAssertEqual(floorElevated.fast, 3)
    }

    func testFundedTxPreviewExpiration() {
        let t0 = Date()
        let preview = FundedTxPreview(
            destinationAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            amountSats: 50_000,
            feeSats: 282,
            satPerVB: 2,
            estimatedVSize: 141,
            createdAt: t0,
            validityWindowSeconds: 60.0
        )

        XCTAssertFalse(preview.isExpired)
        XCTAssertEqual(preview.totalDebitSats, 50_282)

        let expiredPreview = FundedTxPreview(
            destinationAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            amountSats: 50_000,
            feeSats: 282,
            satPerVB: 2,
            estimatedVSize: 141,
            createdAt: t0.addingTimeInterval(-100),
            validityWindowSeconds: 60.0
        )
        XCTAssertTrue(expiredPreview.isExpired)
    }

    func testComputeMempoolRateDistribution() {
        var mockMempool: [String: MempoolTxSummary] = [:]
        // Tx1: 140 vB, 140 sats = 1 sat/vB
        mockMempool["tx1"] = MempoolTxSummary(vsize: 140, fee: 0.00000140)
        // Tx2: 140 vB, 280 sats = 2 sat/vB
        mockMempool["tx2"] = MempoolTxSummary(vsize: 140, fee: 0.00000280)
        // Tx3: 140 vB, 700 sats = 5 sat/vB
        mockMempool["tx3"] = MempoolTxSummary(vsize: 140, fee: 0.00000700)
        // Tx4: 140 vB, 1400 sats = 10 sat/vB
        mockMempool["tx4"] = MempoolTxSummary(vsize: 140, fee: 0.00001400)

        let dist = FeeEngine.computeMempoolRateDistribution(from: mockMempool)
        XCTAssertNotNil(dist)
        if let d = dist {
            XCTAssertEqual(d.min, 1)
            XCTAssertEqual(d.p25, 2)
            XCTAssertEqual(d.median, 5)
            XCTAssertEqual(d.p75, 10)
        }

        // Empty mempool returns nil
        XCTAssertNil(FeeEngine.computeMempoolRateDistribution(from: [:]))
    }

    func testFeeQuoteMedianTxFeeSats() {
        let quote = FeeQuote(type: .normal, satPerVB: 2, targetBlocks: 6, estimatedMinutes: 60)
        // Default standard SegWit is 140 vB * 2 sat/vB = 280 sats
        XCTAssertEqual(quote.medianTxFeeSats, 280)

        let customMedianQuote = FeeQuote(type: .fast, satPerVB: 5, targetBlocks: 2, estimatedMinutes: 20, medianTxFeeSats: 850)
        XCTAssertEqual(customMedianQuote.medianTxFeeSats, 850)
    }
}
