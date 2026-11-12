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

    func testTransactionMaturityInfoForBIP110AndStandardTransactions() {
        // 1. Coinbase mined in Stage 1 era (origin 975,000, with 287 confirmations)
        let txStage1 = TransactionRecord(
            address: "bc1qg00et9gfqcsjdaxvk7tew33fjhmm9tcma3vj4k",
            category: "generate",
            amount: 0.0001,
            confirmations: 287,
            blockheight: 975000,
            txid: "tx_stage1_mock",
            time: 1794279471
        )
        let mat1 = CoinbaseMaturityCalculator.maturityInfo(for: txStage1)
        XCTAssertTrue(mat1.isCoinbase)
        XCTAssertFalse(mat1.isSpendable)
        XCTAssertEqual(mat1.requiredConfirmations, 6480)
        XCTAssertEqual(mat1.remainingBlocks, 6480 - 287)
        XCTAssertTrue(mat1.remainingTimeFormatted.contains("d"))
        XCTAssertEqual(mat1.lockupDescription, "BIP-110 Stage 1 (6,480 blocks / ~45d)")

        // 2. Coinbase mined in Stage 2 era (origin 980,000, with 25,920 confirmations -> fully mature)
        let txStage2Mature = TransactionRecord(
            address: "bc1qg00et9gfqcsjdaxvk7tew33fjhmm9tcma3vj4k",
            category: "generate",
            amount: 0.0001,
            confirmations: 25920,
            blockheight: 980000,
            txid: "tx_stage2_mock",
            time: 1794279471
        )
        let mat2 = CoinbaseMaturityCalculator.maturityInfo(for: txStage2Mature)
        XCTAssertTrue(mat2.isCoinbase)
        XCTAssertTrue(mat2.isSpendable)
        XCTAssertEqual(mat2.remainingBlocks, 0)
        XCTAssertEqual(mat2.remainingTimeFormatted, "Unlocked & Spendable")
        XCTAssertEqual(mat2.lockupDescription, "BIP-110 Stage 2 (25,920 blocks / ~180d)")

        // 3. Standard receive with 0 confirmations -> pending
        let txPendingReceive = TransactionRecord(
            address: "bc1qg00et9gfqcsjdaxvk7tew33fjhmm9tcma3vj4k",
            category: "receive",
            amount: 0.05,
            confirmations: 0,
            blockheight: nil,
            txid: "tx_pending_mock",
            time: 1794279471
        )
        let mat3 = CoinbaseMaturityCalculator.maturityInfo(for: txPendingReceive)
        XCTAssertFalse(mat3.isCoinbase)
        XCTAssertFalse(mat3.isSpendable)
        XCTAssertEqual(mat3.remainingBlocks, 1)

        // 4. Standard receive with 6 confirmations -> spendable
        let txConfirmedReceive = TransactionRecord(
            address: "bc1qg00et9gfqcsjdaxvk7tew33fjhmm9tcma3vj4k",
            category: "receive",
            amount: 0.05,
            confirmations: 6,
            blockheight: 981500,
            txid: "tx_confirmed_mock",
            time: 1794279471
        )
        let mat4 = CoinbaseMaturityCalculator.maturityInfo(for: txConfirmedReceive)
        XCTAssertFalse(mat4.isCoinbase)
        XCTAssertTrue(mat4.isSpendable)
        XCTAssertEqual(mat4.remainingBlocks, 0)
    }
}
