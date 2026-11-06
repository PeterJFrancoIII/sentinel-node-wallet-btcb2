import SwiftUI
import NodePocketCore

public struct ConsoleView: View {
    @EnvironmentObject var state: AppState

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Node Event Console")
                        .font(.title2)
                        .bold()
                    Text("Live stdout/stderr stream from local Bitcoin Knots process.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Copy All") {
                    let fullText = state.logs.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    state.logs.removeAll()
                }
                .buttonStyle(.bordered)
            }
            .padding([.top, .horizontal])

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(state.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: state.logs.count) { _ in
                    if let lastIndex = state.logs.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            .padding([.bottom, .horizontal])
        }
    }
}
