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
}
