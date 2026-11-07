import XCTest
@testable import NodePocketCore

final class CoinbaseMaturityTests: XCTestCase {
    func testEpochClassificationAndConfirmations() {
        // 1. Pre-hard-fork era (< 973,440) -> 100 blocks
        XCTAssertEqual(CoinbaseMaturityCalculator.epoch(forOriginHeight: 973439), .standard100)
        XCTAssertEqual(CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: 973439), 100)

        // 2. Intermediate 45-day era (973,440 ..< 979,919) -> 6,480 blocks
        XCTAssertEqual(CoinbaseMaturityCalculator.epoch(forOriginHeight: 973440), .intermediate45Day)
        XCTAssertEqual(CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: 973440), 6480)
        XCTAssertEqual(CoinbaseMaturityCalculator.epoch(forOriginHeight: 979918), .intermediate45Day)
        XCTAssertEqual(CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: 979918), 6480)

        // 3. Deep 180-day era (>= 979,919) -> 25,920 blocks
        XCTAssertEqual(CoinbaseMaturityCalculator.epoch(forOriginHeight: 979919), .deep180Day)
        XCTAssertEqual(CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: 979919), 25920)

        // 4. Post-expiry era (MTP >= 2027-09-01 00:00 UTC) -> 100 blocks
        let postExpiryMTP = CoinbaseMaturityCalculator.expiryMTPTimestamp + 10
        XCTAssertEqual(CoinbaseMaturityCalculator.epoch(forOriginHeight: 1050000, originMTP: postExpiryMTP), .postExpiry100)
        XCTAssertEqual(CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: 1050000, originMTP: postExpiryMTP), 100)
    }

    func testImmutableCreationEpochInvariant() {
        // A reward minted during the 45-day era (e.g. height 975,000)
        let originHeight = 975000
        let reqConfs = CoinbaseMaturityCalculator.requiredConfirmations(forOriginHeight: originHeight)
        XCTAssertEqual(reqConfs, 6480)

        let matHeight = CoinbaseMaturityCalculator.maturityHeight(originHeight: originHeight)
        XCTAssertEqual(matHeight, 975000 + 6480)

        // Even when tip reaches deep era (height 990,000), required depth is still 6,480
        let currentTip = 980000
        XCTAssertEqual(CoinbaseMaturityCalculator.remainingBlocks(originHeight: originHeight, currentTipHeight: currentTip), (975000 + 6480) - 980000)
        XCTAssertFalse(CoinbaseMaturityCalculator.isMature(originHeight: originHeight, currentTipHeight: currentTip))

        // When tip reaches maturity height, it is mature
        XCTAssertTrue(CoinbaseMaturityCalculator.isMature(originHeight: originHeight, currentTipHeight: matHeight))
    }

    func testMaturityTimeRemainingEstimates() {
        // 6 blocks remaining at 600s/block -> ~1h
        let (display1h, lowConf1) = CoinbaseMaturityCalculator.estimatedTimeRemaining(remainingBlocks: 6, secondsPerBlock: 600.0)
        XCTAssertEqual(display1h, "~1h")
        XCTAssertTrue(lowConf1) // 600s nominal fallback is flagged low-confidence

        // 0 blocks remaining -> Mature
        let (matureDisplay, _) = CoinbaseMaturityCalculator.estimatedTimeRemaining(remainingBlocks: 0)
        XCTAssertEqual(matureDisplay, "Mature")

        // 144 blocks at 600s/block -> ~1d
        let (display1d, _) = CoinbaseMaturityCalculator.estimatedTimeRemaining(remainingBlocks: 144, secondsPerBlock: 600.0)
        XCTAssertEqual(display1d, "~1d")
    }
}
