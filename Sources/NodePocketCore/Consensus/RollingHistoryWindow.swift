import Foundation

/// Discrete rolling block history windows available for the Hashrate Tracker and MACD chart.
/// Enables operator-selectable analysis ranges: 30, 60, 120, 240, 480, and 960 blocks.
public enum RollingHistoryWindow: Int, CaseIterable, Identifiable, Codable, Sendable {
    case blocks30 = 30
    case blocks60 = 60
    case blocks120 = 120
    case blocks240 = 240
    case blocks480 = 480
    case blocks960 = 960

    public var id: Int { rawValue }

    public var displayName: String {
        "\(rawValue) Blocks"
    }

    public var shortName: String {
        "\(rawValue)B"
    }

    /// Default rolling window for standard operational monitoring.
    public static let defaultWindow: RollingHistoryWindow = .blocks30

    /// Maximum rolling window supported by the visualization.
    public static let maxBlocks: Int = 960

    /// Maximum in-memory block header / sample cache capacity (960 + 240 warm-up buffer).
    public static let maxCapacity: Int = 1200
}
