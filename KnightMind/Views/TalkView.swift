import SwiftUI

/// A listening journal. The game never waits for a message from the player.
struct TalkView: View {
    let match: Match

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Rook's notes")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(match.lines.filter { $0.speaker == .companion }) { line in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(line.text)
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(RoomColor.text)
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                                if let move = line.suggestion {
                                    Label(move, systemImage: "arrow.turn.down.right")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(RoomColor.brass)
                                        .accessibilityLabel("Stockfish suggests \(move)")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            Divider().overlay(RoomColor.rim)
                        }
                        if match.replying {
                            ProgressView("Preparing a note")
                                .font(.caption)
                                .tint(RoomColor.muted)
                                .foregroundStyle(RoomColor.muted)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(24)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: match.lines.last?.id, initial: true) { _, _ in
                    proxy.scrollTo("latest", anchor: .bottom)
                }
            }
            HStack(spacing: 20) {
                Button("Hint", systemImage: "lightbulb") { match.request(.hint) }
                    .disabled(match.game.position.turn != .white || match.game.outcome != .playing || match.replying)
                Button("Last move", systemImage: "arrow.turn.down.right") {
                    match.request(.explain)
                }
                .disabled(match.game.history.isEmpty || match.replying)
                Menu {
                    ForEach(ChessRule.allCases) { rule in
                        Button(rule.rawValue) { match.request(.rule(rule)) }
                    }
                } label: {
                    Label("Rules", systemImage: "book.closed")
                }
            }
            .font(.footnote)
            .foregroundStyle(RoomColor.accent)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(RoomColor.background)
    }
}
