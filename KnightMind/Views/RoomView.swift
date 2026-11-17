import ChessCore
import SwiftUI

struct RoomView: View {
    private enum Sheet: String, Identifiable {
        case settings, moves, notes
        var id: String { rawValue }
    }

    let match: Match
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: Sheet?
    @State private var confirmNewGame = false
    @State private var showActions = false

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height * 1.15 {
                HStack(spacing: 0) {
                    board
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 12)
                        commentary
                        newGameButton
                        controls
                    }
                    .frame(width: typeSize.isAccessibilitySize ? 310 : 250)
                }
            } else {
                VStack(spacing: 0) {
                    header
                    board
                    commentary
                    newGameButton
                    controls
                }
            }
        }
        .background { RoomBackdrop() }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsView(match: match)
                case .moves: MovesView(game: match.game)
                case .notes: TalkView(match: match)
                }
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(RoomColor.background)
        }
        .alert("Start a new game?", isPresented: $confirmNewGame) {
            Button("New game", role: .destructive) { match.newGame() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current game's moves will be cleared.")
        }
        .confirmationDialog(
            "Promote your pawn",
            isPresented: Binding(get: { !match.promotion.isEmpty }, set: { if !$0 { match.dismissPromotion() } }),
            titleVisibility: .visible
        ) {
            ForEach(PieceKind.promotions, id: \.self) { kind in
                Button(kind.name) { match.promote(to: kind) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: match.selected)
        .sensoryFeedback(.impact(weight: .light), trigger: match.revision)
        .task { match.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { match.activate() }
            if phase == .background { match.suspend() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("KnightMind")
                .font(.custom("InstrumentSerif-Regular", size: 27, relativeTo: .title2))
                .foregroundStyle(RoomColor.text.opacity(0.85))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(RoomColor.muted)
        .buttonStyle(.plain)
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .padding(.top, 2)
    }

    private var board: some View {
        BoardSurface(state: match.boardState, mode: match.board, tap: match.tap)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
    }

    private var commentary: some View {
        Button { sheet = .notes } label: {
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: match.speaking ? "waveform" : "quote.opening")
                        .font(.system(size: 10, weight: .medium))
                    Text(match.preparingSpeech ? "Preparing voice…" : "Rook")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(RoomColor.brass.opacity(0.85))
                .accessibilityHidden(true)

                Text(match.lastLine.caption)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(RoomColor.text.opacity(0.90))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 3)
                    .frame(maxWidth: .infinity)
            }
            .frame(minHeight: typeSize.isAccessibilitySize ? 110 : 84, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
        .accessibilityLabel("Rook. \(match.lastLine.text)")
        .accessibilityHint("Opens commentary and chess lessons")
        .accessibilityIdentifier("rook-commentary")
        .accessibilityValue(match.speaking ? "Speaking" : match.replying || match.preparingSpeech ? "Preparing" : "Quiet")
    }

    @ViewBuilder
    private var newGameButton: some View {
        if match.game.outcome != .playing {
            Button(action: match.newGame) {
                Label("New game", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(RoomColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoomColor.accent, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
            .padding(.bottom, 8)
            .accessibilityIdentifier("new-game-after-result")
            .accessibilityHint("Starts a fresh game with you playing White")
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: match.undo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(match.game.history.isEmpty)
            .opacity(match.game.history.isEmpty ? 0.35 : 1)
            .accessibilityLabel("Undo")

            Spacer(minLength: 0)
            turnMarker
            Spacer(minLength: 0)

            Button { showActions = true } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Game actions")
            .confirmationDialog("Game actions", isPresented: $showActions, titleVisibility: .hidden) {
                Button("Moves") { sheet = .moves }
                Button("Rook's notes") { sheet = .notes }
                Button("New game") {
                    if match.game.history.isEmpty { match.newGame() } else { confirmNewGame = true }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(RoomColor.muted)
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var turnMarker: some View {
        if match.engineError {
            Button("Retry Stockfish", action: match.retry)
                .font(.caption.weight(.medium))
                .foregroundStyle(RoomColor.brass)
        } else {
            HStack(spacing: 7) {
                if match.thinking {
                    ProgressView().controlSize(.mini).tint(RoomColor.muted)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(match.game.position.turn == .white ? RoomColor.text : RoomColor.brass)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                Text(match.status)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-status")
            .accessibilityHint(match.resultDetail ?? "You play White")
        }
    }
}
