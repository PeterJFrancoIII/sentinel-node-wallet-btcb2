import SwiftUI
import NodePocketCore

public enum MACDPresetOption: String, CaseIterable, Identifiable {
    case thirtyBlock = "30-Block Trend (12, 30, 9)"
    case classic = "Standard (12, 26, 9)"
    case fast = "Fast (6, 18, 6)"

    public var id: String { rawValue }

    public var fast: Int {
        switch self {
        case .thirtyBlock: return 12
        case .classic: return 12
        case .fast: return 6
        }
    }

    public var slow: Int {
        switch self {
        case .thirtyBlock: return 30
        case .classic: return 26
        case .fast: return 18
        }
    }

    public var signal: Int {
        switch self {
        case .thirtyBlock: return 9
        case .classic: return 9
        case .fast: return 6
        }
    }
}

public struct NetworkView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedPreset: MACDPresetOption = .thirtyBlock
    @State private var hoveredIndex: Int? = nil

    private var isSyncing: Bool {
        (state.blockchainInfo?.initialblockdownload ?? false) || (state.hashrateReport?.isSyncing ?? false)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network & Hashrate Tracker")
                        .font(.system(size: 26, weight: .bold))
                    Text("100% locally calculated from consensus block headers • Zero external/paid APIs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Main Hashrate Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated BLAKE2b Network Hashrate (30-Block Trend)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if isSyncing {
                                Text("Syncing Node...")
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text("Network hashrate tracking begins once the node is fully synchronized • Awaiting block tip")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else {
                                Text(state.hashrateReport?.displayHashrate ?? "Calculating...")
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                            }
                        }
                        Spacer()
                        freshnessBadge
                    }

                    Divider()

                    HStack(spacing: 24) {
                        statPill(label: "Smoothed Rate (120-Block)", value: isSyncing ? "--" : (state.hashrateReport?.displaySmoothedHashrate ?? "--"))
                        statPill(label: "Difficulty", value: String(format: "%.4f", state.hashrateReport?.difficulty ?? 0.0))
                        statPill(label: "Avg Block Interval", value: isSyncing ? "--" : String(format: "%.1fs", state.hashrateReport?.averageBlockIntervalSeconds ?? 600.0))
                        statPill(label: "Sampled Blocks", value: isSyncing ? "0 / 30 (Syncing)" : "\(state.hashrateReport?.sampleCount ?? 0)")
                        statPill(label: "Telemetry Age", value: isSyncing ? "--" : String(format: "%.0fs", state.hashrateReport?.telemetryAgeSeconds ?? 0.0))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Rolling Hashrate Dot Plot & 30-Block MACD Indicator
                rollingHashrateDotPlotAndMACDCard

                // Peer Topology & Capacity Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.purple)
                        Text("P2P Network Topology & Peer Capacity")
                            .font(.headline)
                        Spacer()
                        let conns = state.networkInfo?.connections ?? 0
                        let liveCap = state.nodeManager.verifiedRunningMaxConnections.map(String.init) ?? "unverified"
                        Text("\(conns) / \(liveCap) Running Cap")
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    }

                    HStack(spacing: 24) {
                        statPill(label: "Total Connected", value: "\(state.networkInfo?.connections ?? 0)")
                        statPill(label: "Outbound Peers", value: "\(state.networkInfo?.connections_out ?? 0)")
                        statPill(label: "Inbound Peers", value: "\(state.networkInfo?.connections_in ?? 0)")
                        statPill(label: "Configured Cap", value: "\(state.nodeManager.config.profile.maxConnections)")
                        statPill(label: "Running Cap", value: state.nodeManager.verifiedRunningMaxConnections.map(String.init) ?? "unverified")
                    }

                    Text("Maximum peers is a cap, not a target. Ultra Power enforces 4 peers even if a higher value is configured. App-owned daemons report their launched cap; an adopted daemon may have unknown command-line overrides. Outbound connections are normally limited by peer-selection policy. Inbound peers additionally require listening enabled and firewall/router reachability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // BIP-110 Mathematical & Consensus Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "function")
                            .foregroundColor(.orange)
                        Text("BIP-110 Proof-of-Work & 30-Block MACD Momentum Model")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Consensus Hashrate Sampling: Derived from cumulative expected proof-of-work divided by valid elapsed block intervals over rolling windows: H = Σ(2²⁵⁶ / (Target + 1)) / Σ(Δt). Miner timestamp anomalies (Δt ≤ 0) are excluded from the rate denominator to guarantee mathematical stability.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("2. 30-Block MACD Momentum Indicator: Evaluates hashrate trend velocity using an Exponential Moving Average Convergence Divergence model: MACD = EMA_fast(H) - EMA_slow(H), with a 9-block signal line and divergence histogram = MACD - Signal. Positive divergence indicates accelerating network hashrate and miner capital commitment; negative divergence highlights hash migration prior to nominal 2016-block difficulty readjustments.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if state.hashrateReport?.hasTimestampAnomalies == true {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Timestamp anomaly detected in recent block headers; invalid intervals excluded from rate.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
            }
            .padding(24)
        }
    }

    // MARK: - Rolling Hashrate Dot Plot & MACD Card

    private var rollingHashrateDotPlotAndMACDCard: some View {
        let history = state.hashrateReport?.history ?? []
        let macdReport = state.hashrateReport?.macdReport(
            fast: selectedPreset.fast,
            slow: selectedPreset.slow,
            signal: selectedPreset.signal
        ) ?? MACDReport(points: [])

        return VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.dots.scatter")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("Rolling Hashrate History (30-Block Dot Plot)")
                        .font(.headline)
                    Text("30-Block MACD Indicator")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                        .foregroundColor(.cyan)
                }

                Spacer()

                // Parameter Preset Picker
                Picker("MACD Window", selection: $selectedPreset) {
                    ForEach(MACDPresetOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 380)
            }

            if !history.isEmpty && !macdReport.points.isEmpty {
                // Live/Selected Telemetry Strip
                telemetryStrip(points: macdReport.points, report: macdReport)

                // The Dot Plot (Upper Pane)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hashrate Dot Plot (PH/s)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 12) {
                            legendPill(color: .cyan, label: "Sample Dot")
                            legendPill(color: Color(red: 0.2, green: 0.85, blue: 1.0), label: "Fast EMA (\(selectedPreset.fast))")
                            legendPill(color: Color(red: 0.8, green: 0.4, blue: 1.0), label: "Slow EMA (\(selectedPreset.slow))")
                        }
                    }

                    dotPlotView(points: macdReport.points)
                        .frame(height: 150)
                }

                Divider()

                // The 30-Block MACD Sub-Pane (Lower Pane)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("30-Block Moving Average Convergence Divergence")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 12) {
                            legendPill(color: .green, label: "+ Divergence")
                            legendPill(color: .red, label: "- Divergence")
                            legendPill(color: Color(red: 0.2, green: 0.85, blue: 1.0), label: "MACD Line")
                            legendPill(color: Color(red: 1.0, green: 0.6, blue: 0.2), label: "Signal Line (\(selectedPreset.signal))")
                        }
                    }

                    macdSubChartView(points: macdReport.points)
                        .frame(height: 95)
                }

                // X-Axis Sub-Labels & Scrub Hint
                HStack {
                    Text("Earlier Blocks (t-29)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Hover or drag across dots to scrub block metrics")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                    Text("Latest Block Tip (t=0)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(isSyncing
                             ? "Node is synchronizing block headers. Dot plot and 30-block MACD activate once sync completes."
                             : "Gathering 30 contiguous block samples from local Knots daemon...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 36)
                    Spacer()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }

    // MARK: - Telemetry Strip

    private func telemetryStrip(points: [MACDPoint], report: MACDReport) -> some View {
        let activeIndex = hoveredIndex.flatMap { (0..<points.count).contains($0) ? $0 : nil } ?? (points.count - 1)
        let pt = points[activeIndex]
        let isTip = (activeIndex == points.count - 1)

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(isTip ? "Latest Tip Block" : "Inspected Block")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if isTip {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                }
                Text("#\(pt.height)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Sampled Rate")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f PH/s", pt.hashratePH))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Fast EMA (\(report.fastPeriod))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f PH/s", pt.fastEMA))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 1.0))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Slow EMA (\(report.slowPeriod))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f PH/s", pt.slowEMA))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.8, green: 0.4, blue: 1.0))
            }

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("MACD")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%+.2f PH/s", pt.macd))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 1.0))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Signal (\(report.signalPeriod))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%+.2f PH/s", pt.signal))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Divergence")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%+.2f PH/s", pt.histogram))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(pt.histogram >= 0 ? .green : .red)
            }

            Spacer()

            // Trend Signal Badge
            HStack(spacing: 5) {
                Image(systemName: report.trend.isBullish ? "arrow.up.right" : (report.trend.isBearish ? "arrow.down.right" : "equal"))
                    .font(.system(size: 10, weight: .bold))
                Text(report.trend.rawValue)
                    .font(.caption2)
                    .bold()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(report.trend.isBullish ? Color.green.opacity(0.18) : (report.trend.isBearish ? Color.red.opacity(0.18) : Color.secondary.opacity(0.15))))
            .foregroundColor(report.trend.isBullish ? .green : (report.trend.isBearish ? .red : .secondary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - Dot Plot View (Upper Pane)

    private func dotPlotView(points: [MACDPoint]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padL: CGFloat = 52.0
            let padR: CGFloat = 16.0
            let padT: CGFloat = 12.0
            let padB: CGFloat = 20.0
            let usableW = max(10, w - padL - padR)
            let usableH = max(10, h - padT - padB)
            let n = points.count

            let rates = points.map(\.hashratePH)
            let rawMin = min(rates.min() ?? 0.0, points.map(\.fastEMA).min() ?? 0.0, points.map(\.slowEMA).min() ?? 0.0)
            let rawMax = max(rates.max() ?? 1.0, points.map(\.fastEMA).max() ?? 1.0, points.map(\.slowEMA).max() ?? 1.0)
            let range = max(0.2, rawMax - rawMin)
            let yMin = max(0.0, rawMin - (range * 0.08))
            let yMax = rawMax + (range * 0.08)
            let effectiveRange = max(0.1, yMax - yMin)

            let xForIndex: (Int) -> CGFloat = { idx in
                if n <= 1 { return padL + (usableW / 2.0) }
                return padL + (CGFloat(idx) * (usableW / CGFloat(n - 1)))
            }

            let yForRate: (Double) -> CGFloat = { rate in
                let norm = (rate - yMin) / effectiveRange
                return padT + ((1.0 - CGFloat(norm)) * usableH)
            }

            ZStack(alignment: .topLeading) {
                // Horizontal Reference Gridlines & Y-Axis Labels
                ForEach(0..<4) { step in
                    let frac = Double(step) / 3.0
                    let val = yMin + ((1.0 - frac) * effectiveRange)
                    let yPos = padT + (CGFloat(frac) * usableH)

                    Path { path in
                        path.move(to: CGPoint(x: padL, y: yPos))
                        path.addLine(to: CGPoint(x: w - padR, y: yPos))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                    .foregroundColor(Color.secondary.opacity(0.25))

                    Text(String(format: "%.1f", val))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: padL - 8, alignment: .trailing)
                        .position(x: (padL - 8) / 2.0, y: yPos)
                }

                // Smooth Hashrate Line Underlay
                if n >= 2 {
                    // Soft Gradient Area Under Rate Path
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: padT + usableH))
                        for i in 0..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForRate(points[i].hashratePH)))
                        }
                        path.addLine(to: CGPoint(x: xForIndex(n - 1), y: padT + usableH))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.cyan.opacity(0.18), Color.cyan.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    // Hashrate Connecting Line
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: yForRate(points[0].hashratePH)))
                        for i in 1..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForRate(points[i].hashratePH)))
                        }
                    }
                    .stroke(Color.cyan.opacity(0.4), lineWidth: 1.5)

                    // Fast EMA Curve
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: yForRate(points[0].fastEMA)))
                        for i in 1..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForRate(points[i].fastEMA)))
                        }
                    }
                    .stroke(Color(red: 0.2, green: 0.85, blue: 1.0).opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))

                    // Slow EMA Curve
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: yForRate(points[0].slowEMA)))
                        for i in 1..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForRate(points[i].slowEMA)))
                        }
                    }
                    .stroke(Color(red: 0.8, green: 0.4, blue: 1.0).opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                }

                // Vertical Cursor Line when Scrubbing/Hovering
                if let hoverIdx = hoveredIndex, (0..<n).contains(hoverIdx) {
                    let cursorX = xForIndex(hoverIdx)
                    Path { path in
                        path.move(to: CGPoint(x: cursorX, y: padT))
                        path.addLine(to: CGPoint(x: cursorX, y: h))
                    }
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                }

                // Hashrate Sample Dots (The Dot Plot)
                ForEach(0..<n, id: \.self) { i in
                    let pt = points[i]
                    let cx = xForIndex(i)
                    let cy = yForRate(pt.hashratePH)
                    let isHovered = (i == hoveredIndex)
                    let isTip = (i == n - 1)

                    // Subtle drop line from dot to bottom axis
                    Path { path in
                        path.move(to: CGPoint(x: cx, y: cy + 4))
                        path.addLine(to: CGPoint(x: cx, y: padT + usableH))
                    }
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.8)

                    // Outer pulse ring for the live tip dot
                    if isTip && !isHovered {
                        Circle()
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 3.5)
                            .frame(width: 15, height: 15)
                            .position(x: cx, y: cy)
                    }

                    // Dot itself
                    Circle()
                        .fill(isHovered ? Color.white : (isTip ? Color.green : Color.cyan))
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: isHovered ? 2.0 : 1.2))
                        .shadow(color: Color.cyan.opacity(0.6), radius: isHovered ? 4 : 2)
                        .frame(width: isHovered ? 11 : (isTip ? 8.5 : 6.5),
                               height: isHovered ? 11 : (isTip ? 8.5 : 6.5))
                        .position(x: cx, y: cy)

                    // X-Axis Block Height Labels (Modulo 100 or Tip)
                    if (i % 5 == 0) || isTip || isHovered {
                        Text("\(pt.height % 100)")
                            .font(.system(size: 8, weight: isHovered ? .bold : .regular, design: .monospaced))
                            .foregroundColor(isHovered ? .white : .secondary)
                            .position(x: cx, y: padT + usableH + 10)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let relX = value.location.x - padL
                        if usableW > 0 && n > 1 {
                            let idx = Int(round((relX / usableW) * CGFloat(n - 1)))
                            hoveredIndex = min(max(0, idx), n - 1)
                        }
                    }
                    .onEnded { _ in
                        hoveredIndex = nil
                    }
            )
        }
    }

    // MARK: - 30-Block MACD Sub-Chart (Lower Pane)

    private func macdSubChartView(points: [MACDPoint]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padL: CGFloat = 52.0
            let padR: CGFloat = 16.0
            let padT: CGFloat = 8.0
            let padB: CGFloat = 8.0
            let usableW = max(10, w - padL - padR)
            let usableH = max(10, h - padT - padB)
            let zeroY = padT + (usableH / 2.0)
            let n = points.count

            let allVals = points.flatMap { [abs($0.histogram), abs($0.macd), abs($0.signal)] }
            let maxAbs = max(allVals.max() ?? 0.1, 0.02) * 1.2
            let halfH = usableH / 2.0

            let xForIndex: (Int) -> CGFloat = { idx in
                if n <= 1 { return padL + (usableW / 2.0) }
                return padL + (CGFloat(idx) * (usableW / CGFloat(n - 1)))
            }

            let yForVal: (Double) -> CGFloat = { val in
                let norm = val / maxAbs
                return zeroY - (CGFloat(norm) * halfH)
            }

            let barWidth: CGFloat = min(9.0, max(2.5, (usableW / CGFloat(max(1, n))) * 0.55))

            ZStack(alignment: .topLeading) {
                // Center Baseline (Zero Line)
                Path { path in
                    path.move(to: CGPoint(x: padL, y: zeroY))
                    path.addLine(to: CGPoint(x: w - padR, y: zeroY))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))

                // Zero Label on Left
                Text("0.00")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: padL - 8, alignment: .trailing)
                    .position(x: (padL - 8) / 2.0, y: zeroY)

                // Top Positive Limit Label
                Text(String(format: "+%.2f", maxAbs))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                    .frame(width: padL - 8, alignment: .trailing)
                    .position(x: (padL - 8) / 2.0, y: padT + 4)

                // Bottom Negative Limit Label
                Text(String(format: "-%.2f", maxAbs))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: padL - 8, alignment: .trailing)
                    .position(x: (padL - 8) / 2.0, y: h - padB - 4)

                // Vertical Cursor Line when Scrubbing
                if let hoverIdx = hoveredIndex, (0..<n).contains(hoverIdx) {
                    let cursorX = xForIndex(hoverIdx)
                    Path { path in
                        path.move(to: CGPoint(x: cursorX, y: 0))
                        path.addLine(to: CGPoint(x: cursorX, y: h))
                    }
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                }

                // MACD Divergence Histogram Bars
                ForEach(0..<n, id: \.self) { i in
                    let pt = points[i]
                    let cx = xForIndex(i)
                    let histY = yForVal(pt.histogram)
                    let isPositive = pt.histogram >= 0
                    let barTop = min(zeroY, histY)
                    let barHeight = max(1.5, abs(zeroY - histY))
                    let isHovered = (i == hoveredIndex)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPositive ? Color.green.opacity(isHovered ? 1.0 : 0.8) : Color.red.opacity(isHovered ? 1.0 : 0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(isHovered ? Color.white : Color.clear, lineWidth: 1.0)
                        )
                        .frame(width: isHovered ? barWidth + 2 : barWidth, height: barHeight)
                        .position(x: cx, y: barTop + (barHeight / 2.0))
                }

                // MACD Line (Cyan / Electric Blue)
                if n >= 2 {
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: yForVal(points[0].macd)))
                        for i in 1..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForVal(points[i].macd)))
                        }
                    }
                    .stroke(Color(red: 0.2, green: 0.85, blue: 1.0), lineWidth: 1.8)

                    // Signal Line (Orange / Amber)
                    Path { path in
                        path.move(to: CGPoint(x: xForIndex(0), y: yForVal(points[0].signal)))
                        for i in 1..<n {
                            path.addLine(to: CGPoint(x: xForIndex(i), y: yForVal(points[i].signal)))
                        }
                    }
                    .stroke(Color(red: 1.0, green: 0.6, blue: 0.2), lineWidth: 1.5)
                }

                // Point Dots along MACD and Signal Lines
                ForEach(0..<n, id: \.self) { i in
                    let pt = points[i]
                    let cx = xForIndex(i)
                    let macdY = yForVal(pt.macd)
                    let sigY = yForVal(pt.signal)
                    let isHovered = (i == hoveredIndex)

                    Circle()
                        .fill(Color(red: 0.2, green: 0.85, blue: 1.0))
                        .frame(width: isHovered ? 6 : 3.5, height: isHovered ? 6 : 3.5)
                        .position(x: cx, y: macdY)

                    Circle()
                        .fill(Color(red: 1.0, green: 0.6, blue: 0.2))
                        .frame(width: isHovered ? 6 : 3.5, height: isHovered ? 6 : 3.5)
                        .position(x: cx, y: sigY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let relX = value.location.x - padL
                        if usableW > 0 && n > 1 {
                            let idx = Int(round((relX / usableW) * CGFloat(n - 1)))
                            hoveredIndex = min(max(0, idx), n - 1)
                        }
                    }
                    .onEnded { _ in
                        hoveredIndex = nil
                    }
            )
        }
    }

    // MARK: - Helper UI Components

    private func legendPill(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var freshnessBadge: some View {
        if isSyncing {
            return HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("SYNCING")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
        }

        let isStale = state.hashrateReport?.isStale ?? true
        return HStack(spacing: 6) {
            Circle()
                .fill(isStale ? Color.yellow : Color.green)
                .frame(width: 8, height: 8)
            Text(isStale ? "STALE" : "LIVE")
                .font(.caption)
                .bold()
                .foregroundColor(isStale ? .yellow : .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill((isStale ? Color.yellow : Color.green).opacity(0.15)))
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
    }
}
