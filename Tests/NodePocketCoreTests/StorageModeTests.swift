import XCTest
@testable import NodePocketCore

final class StorageModeTests: XCTestCase {
    func testCompactPruningDefaultsAndValidation() throws {
        // New installations default to 2 GiB while retaining a 550 MiB minimum
        let defaultMode = StorageMode.compact(pruneMB: StorageMode.defaultPruneMB)
        XCTAssertTrue(defaultMode.isPruned)
        XCTAssertFalse(defaultMode.isArchival)
        XCTAssertEqual(defaultMode.pruneMB, 2048)

        // 550 MiB is valid
        let mode550 = try StorageMode.validateCompactPrune(mb: 550)
        XCTAssertEqual(mode550.pruneMB, 550)

        // Custom >= 550 MiB is valid
        let mode2048 = try StorageMode.validateCompactPrune(mb: 2048)
        XCTAssertEqual(mode2048.pruneMB, 2048)

        // Rejection of < 550 MiB (e.g. 549, 0, 100)
        XCTAssertThrowsError(try StorageMode.validateCompactPrune(mb: 549)) { error in
            guard let sError = error as? StorageValidationError,
                  case .belowMinimumPruneSize(let mb) = sError else {
                XCTFail("Expected belowMinimumPruneSize but got \(error)")
                return
            }
            XCTAssertEqual(mb, 549)
        }

        XCTAssertThrowsError(try StorageMode.validateCompactPrune(mb: 0))
        XCTAssertThrowsError(try StorageMode.validateCompactPrune(mb: 250))
    }

    func testArchivalModeGatingAndExternalRequirement() throws {
        // Internal drive archival attempt must be prohibited
        XCTAssertThrowsError(try StorageMode.validateInternalArchival(freeGB: 53.4)) { error in
            guard let sError = error as? StorageValidationError,
                  case .internalDriveArchivalProhibited(let freeGB) = sError else {
                XCTFail("Expected internalDriveArchivalProhibited but got \(error)")
                return
            }
            XCTAssertEqual(freeGB, 53.4, accuracy: 0.1)
        }

        let dummyExternalURL = URL(fileURLWithPath: "/Volumes/ExternalSSD/BitcoinArchival")

        // Insufficient external drive space (< 1 TB) must throw
        XCTAssertThrowsError(try StorageMode.validateArchival(externalURL: dummyExternalURL, availableGB: 750.0)) { error in
            guard let sError = error as? StorageValidationError,
                  case .externalDriveInsufficientSpace(let req, let avail) = sError else {
                XCTFail("Expected externalDriveInsufficientSpace but got \(error)")
                return
            }
            XCTAssertEqual(req, 1000.0)
            XCTAssertEqual(avail, 750.0)
        }

        // Sufficient external drive space (>= 1 TB) succeeds
        let validArchival = try StorageMode.validateArchival(externalURL: dummyExternalURL, availableGB: 1500.0)
        XCTAssertFalse(validArchival.isPruned)
        XCTAssertTrue(validArchival.isArchival)
        XCTAssertEqual(validArchival.pruneMB, 0)
    }
}
