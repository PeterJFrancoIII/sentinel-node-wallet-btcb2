import XCTest
@testable import NodePocketCore

final class StorageBreakdownSnapshotTests: XCTestCase {
    func testFormattingAndCalculations() {
        let snapshot = StorageBreakdownSnapshot(
            blocksBytes: 550 * 1024 * 1024,
            chainstateBytes: 18 * 1024 * 1024 * 1024,
            indexesBytes: 4096,
            walletsBytes: 65536,
            totalDataDirBytes: 19 * 1024 * 1024 * 1024
        )

        XCTAssertFalse(snapshot.formattedBlocksSize.isEmpty)
        XCTAssertFalse(snapshot.formattedChainstateSize.isEmpty)
        XCTAssertFalse(snapshot.formattedTotalSize.isEmpty)
        XCTAssertEqual(snapshot.blocksBytes, 550 * 1024 * 1024)
        XCTAssertEqual(snapshot.chainstateBytes, 18 * 1024 * 1024 * 1024)
    }

    func testMeasureNonExistentDirectoryReturnsZero() {
        let nonExistent = URL(fileURLWithPath: "/tmp/non_existent_dir_\(UUID().uuidString)")
        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: nonExistent)

        XCTAssertEqual(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateBytes, 0)
        XCTAssertEqual(snapshot.totalDataDirBytes, 0)
    }

    func testMeasureMockDataDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)

        let sampleData = Data(repeating: 0x42, count: 1024 * 1024) // 1 MB
        try sampleData.write(to: blocksDir.appendingPathComponent("blk00000.dat"))
        try sampleData.write(to: chainstateDir.appendingPathComponent("000001.ldb"))

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertGreaterThanOrEqual(snapshot.blocksBytes, 1024 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.chainstateBytes, 1024 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.totalDataDirBytes, 2 * 1024 * 1024)
    }
}
