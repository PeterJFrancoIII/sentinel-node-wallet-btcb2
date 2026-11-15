import Foundation

public struct StorageBreakdownSnapshot: Sendable, Equatable {
    public let blocksBytes: Int64
    public let chainstateBytes: Int64
    public let indexesBytes: Int64
    public let walletsBytes: Int64
    public let totalDataDirBytes: Int64
    public let measuredAt: Date

    public init(
        blocksBytes: Int64,
        chainstateBytes: Int64,
        indexesBytes: Int64,
        walletsBytes: Int64,
        totalDataDirBytes: Int64,
        measuredAt: Date = Date()
    ) {
        self.blocksBytes = blocksBytes
        self.chainstateBytes = chainstateBytes
        self.indexesBytes = indexesBytes
        self.walletsBytes = walletsBytes
        self.totalDataDirBytes = totalDataDirBytes
        self.measuredAt = measuredAt
    }

    public var formattedBlocksSize: String {
        ByteCountFormatter.string(fromByteCount: blocksBytes, countStyle: .file)
    }

    public var formattedChainstateSize: String {
        ByteCountFormatter.string(fromByteCount: chainstateBytes, countStyle: .file)
    }

    public var formattedIndexesSize: String {
        ByteCountFormatter.string(fromByteCount: indexesBytes, countStyle: .file)
    }

    public var formattedWalletsSize: String {
        ByteCountFormatter.string(fromByteCount: walletsBytes, countStyle: .file)
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalDataDirBytes, countStyle: .file)
    }

    public static func measure(dataDirectory: URL, rpcSizeOnDisk: Int64? = nil) -> StorageBreakdownSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataDirectory.path) else {
            return StorageBreakdownSnapshot(
                blocksBytes: 0,
                chainstateBytes: 0,
                indexesBytes: 0,
                walletsBytes: 0,
                totalDataDirBytes: 0
            )
        }

        let blocksURL = dataDirectory.appendingPathComponent("blocks")
        let chainstateURL = dataDirectory.appendingPathComponent("chainstate")
        let indexesURL = dataDirectory.appendingPathComponent("indexes")
        let walletsURL = dataDirectory.appendingPathComponent("wallets")

        let measuredBlocks = directorySize(at: blocksURL)
        let effectiveBlocks = (rpcSizeOnDisk != nil && rpcSizeOnDisk! > 0) ? rpcSizeOnDisk! : measuredBlocks
        let measuredChainstate = directorySize(at: chainstateURL)
        let measuredIndexes = directorySize(at: indexesURL)
        let measuredWallets = directorySize(at: walletsURL)
        let measuredTotal = directorySize(at: dataDirectory)

        return StorageBreakdownSnapshot(
            blocksBytes: effectiveBlocks,
            chainstateBytes: measuredChainstate,
            indexesBytes: measuredIndexes,
            walletsBytes: measuredWallets,
            totalDataDirBytes: max(measuredTotal, effectiveBlocks + measuredChainstate),
            measuredAt: Date()
        )
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
