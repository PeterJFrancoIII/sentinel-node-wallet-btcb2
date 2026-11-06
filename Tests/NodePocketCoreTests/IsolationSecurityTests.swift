import XCTest
@testable import NodePocketCore

final class IsolationSecurityTests: XCTestCase {
    func testForbiddenIsolationTermsDetected() {
        let cleanText = "NODE Pocket BTCB2 standalone application with local RPC."
        let cleanResult = SecurityAuditor.auditContent(cleanText)
        XCTAssertTrue(cleanResult.isPassed)
        XCTAssertTrue(cleanResult.violations.isEmpty)

        let contaminatedText = "Connecting to Sentinel Pool or Sentinel Mining backend."
        let badResult = SecurityAuditor.auditContent(contaminatedText)
        XCTAssertFalse(badResult.isPassed)
        XCTAssertEqual(badResult.violations.count, 2)
    }

    func testSecretScanningDetectsUnencryptedPrivateKeys() {
        let textWithKey = "export BITCOIN_KEY=5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF"
        let result = SecurityAuditor.auditContent(textWithKey)
        XCTAssertFalse(result.isPassed)
        XCTAssertTrue(result.violations.contains(where: { $0.contains("WIF private key") }))
    }

    func testRPCHostEnforcement() {
        XCTAssertTrue(SecurityAuditor.auditRPCHost("127.0.0.1"))
        XCTAssertTrue(SecurityAuditor.auditRPCHost("localhost"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("0.0.0.0"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("192.168.1.50"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("remote.server.io"))
    }
}
