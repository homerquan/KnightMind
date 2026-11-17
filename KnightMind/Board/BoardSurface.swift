import ChessCore
import RealityKit
import SwiftUI

enum BoardMark: Equatable {
    case check, selection, target(capture: Bool), hint, recent

    var tint: Color {
        switch self {
        case .check: Color(rgb: 0xD85448)
        case .selection, .target: RoomColor.accent
        case .hint: Color(rgb: 0x8BE4BD)
        case .recent: Color(rgb: 0xF8CA74)
        }
    }
}

extension BoardState {
    func mark(at square: Square) -> BoardMark? {
        if square == selected { return .selection }
        if square == checked { return .check }
        if destinations.contains(square) { return .target(capture: position[square] != nil) }
        if square == hint?.from || square == hint?.to { return .hint }
        if square == recent?.from || square == recent?.to { return .recent }
        return nil
    }
}

struct BoardSurface: View {
    let state: BoardState
    let mode: BoardView
    let tap: (Square) -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        Group {
            if mode == .perspective && !voiceOver {
                PerspectiveBoard(state: state, tap: tap)
            } else {
                FlatBoard(state: state, tap: tap)
                    .padding(4)
            }
        }
    }
}

struct PiecePicture: View {
    let piece: Piece

    var body: some View {
        Image(piece.side.name + piece.kind.name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

private struct FlatBoard: View {
    private static let ranks = (0..<8).reversed().map { rank in
        (0..<8).compactMap { Square(file: $0, rank: rank) }
    }

    let state: BoardState
    let tap: (Square) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let cell = size / 9
            ZStack {
                Image("BoardFace")
                    .resizable()
                    .clipShape(.rect(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.55), radius: 16, y: 11)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(Self.ranks, id: \.first) { rank in
                        HStack(spacing: 0) {
                            ForEach(rank, id: \.self) { square in
                                Button { tap(square) } label: {
                                    ZStack {
                                        Rectangle().fill(.clear)
                                        if let mark = state.mark(at: square) {
                                            marker(mark, cell: cell)
                                        }
                                        if let piece = state.position[square] {
                                            PiecePicture(piece: piece)
                                                .padding(cell * 0.04)
                                        }
                                    }
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(square.name)
                                .accessibilityLabel(squareLabel(square))
                                .accessibilityAddTraits(state.selected == square ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chessboard")
    }

    @ViewBuilder
    private func marker(_ mark: BoardMark, cell: CGFloat) -> some View {
        switch mark {
        case .target(capture: false):
            Circle().fill(mark.tint.opacity(0.8))
                .frame(width: cell * 0.22, height: cell * 0.22)
                .shadow(color: .black.opacity(0.30), radius: 1)
        case .target(capture: true):
            Circle().strokeBorder(mark.tint.opacity(0.8), lineWidth: 2.5).padding(2)
        default:
            Rectangle().fill(mark.tint.opacity(mark == .recent ? 0.20 : 0.32))
                .overlay(Rectangle().strokeBorder(mark.tint.opacity(mark == .recent ? 0.65 : 1), lineWidth: 1.5))
        }
    }

    private func squareLabel(_ square: Square) -> String {
        let coordinate = "\(square.fileName) \(square.rank + 1)"
        if let piece = state.position[square] {
            return "\(coordinate), \(piece.side.name) \(piece.kind.rawValue)"
        }
        return state.destinations.contains(square) ? "\(coordinate), legal destination" : coordinate
    }
}

private struct PerspectiveBoard: View {
    let state: BoardState
    let tap: (Square) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: TableScene?
    @State private var failed = false

    var body: some View {
        GeometryReader { geometry in
            if failed {
                FlatBoard(state: state, tap: tap)
            } else {
                RealityView { content in
                    do {
                        let table = try TableScene()
                        table.fit(in: geometry.size)
                        content.camera = .virtual
                        content.entities.append(table.root)
                        content.cameraTarget = table.camera
                        table.update(state, animate: false)
                        scene = table
                    } catch {
                        failed = true
                    }
                } update: { _ in
                    scene?.fit(in: geometry.size)
                    scene?.update(state, animate: !reduceMotion)
                } placeholder: {
                    ProgressView().tint(RoomColor.accent)
                }
                .realityViewCameraControls(.none)
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                if let square = scene?.square(at: value.location, in: geometry.size, state: state) {
                                    tap(square)
                                }
                            })
                    }
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Three-dimensional chessboard")
                .accessibilityIdentifier("perspective-board")
            }
        }
    }
}
