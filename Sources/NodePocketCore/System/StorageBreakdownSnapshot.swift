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

    /// Asynchronous nonblocking measurement executed on a detached background utility thread.
    public static func measureAsync(dataDirectory: URL, rpcSizeOnDisk: Int64? = nil) async -> StorageBreakdownSnapshot {
        await Task.detached(priority: .utility) {
            measure(dataDirectory: dataDirectory, rpcSizeOnDisk: rpcSizeOnDisk)
        }.value
    }

    /// Synchronous measurement safely bounded to prevent symlink traversal.
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

        // Refuse to follow symbolic link escaping the intended data directory
        if let rootValues = try? dataDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]),
           rootValues.isSymbolicLink == true {
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
        // Guard against symlink root
        if let rootValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           rootValues.isSymbolicLink == true {
            return 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            // Measure actual on-disk allocated bytes if available (APFS extent allocation), fallback to logical fileSize
            let allocSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(allocSize)
        }
        return total
    }
}
