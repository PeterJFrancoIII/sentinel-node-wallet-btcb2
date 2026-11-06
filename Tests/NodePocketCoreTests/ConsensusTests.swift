import XCTest
@testable import NodePocketCore

final class ConsensusTests: XCTestCase {
    func testTargetDecodingFromCompactBits() {
        // Standard diff1 nBits: 0x1d00ffff
        let bits: UInt32 = 0x1d00ffff
        guard let targetHex = TargetConverter.targetHexFromBits(bits) else {
            XCTFail("Failed to decode target from valid nBits")
            return
        }

        XCTAssertEqual(targetHex.count, 64)
        XCTAssertTrue(targetHex.hasPrefix("00000000ffff"))

        let diff = TargetConverter.difficultyFromTarget(targetHex: targetHex)
        XCTAssertEqual(diff, 1.0, accuracy: 0.0001)

        let expectedHashes = TargetConverter.expectedHashesFromTarget(targetHex: targetHex)
        XCTAssertEqual(expectedHashes, pow(2.0, 32.0), accuracy: 1.0)
    }

    func testTargetConverterNegativeBitsFails() {
        let negativeBits: UInt32 = 0x1d80ffff // sign bit set
        XCTAssertNil(TargetConverter.targetHexFromBits(negativeBits))
    }

    func testNominalHashrateCalculation() {
        let expectedHashes = 600.0 * 1e15 // Exactly 1 PH for 600s interval
        let ph = TargetConverter.nominalHashratePH(expectedHashes: expectedHashes, targetSeconds: 600.0)
        XCTAssertEqual(ph, 1.0, accuracy: 0.0001)
    }

    func testBTCB2NetworkDefaultsAndForkCheckpoint() {
        XCTAssertEqual(BTCB2Network.mainnet.defaultRPCPort, 8332)
        XCTAssertEqual(BTCB2Network.mainnet.defaultP2PPort, 8333)
        XCTAssertEqual(BTCB2Network.testnet4.defaultRPCPort, 48332)
        XCTAssertEqual(BTCB2Network.regtest.defaultRPCPort, 18443)

        XCTAssertTrue(BTCB2ConsensusValidator.validateTemplateRules(["segwit", "blake2b"]))
        XCTAssertFalse(BTCB2ConsensusValidator.validateTemplateRules(["segwit"]))
        XCTAssertFalse(BTCB2ConsensusValidator.validateTemplateRules(["blake2b"]))

        // Verify BIP-110 fork constants
        XCTAssertEqual(BTCB2ConsensusConstants.forkActivationHeight, 961640)
        XCTAssertEqual(BTCB2ConsensusConstants.forkActivationBlockHash, "0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb")
        XCTAssertTrue(BTCB2ConsensusValidator.validateForkCheckpoint(
            height: 961640,
            blockHash: "0000000000000050c1e5f69672f459293be14f46e5a494e7a8c8541396f18eeb"
        ))
        XCTAssertFalse(BTCB2ConsensusValidator.validateForkCheckpoint(
            height: 961640,
            blockHash: "0000000000000000000wronghash"
        ))
    }
}
