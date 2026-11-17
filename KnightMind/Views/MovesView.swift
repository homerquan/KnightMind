import ChessCore
import SwiftUI

struct MovesView: View {
    let game: Game

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Moves")
            if game.history.isEmpty {
                ContentUnavailableView("No moves yet", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(RoomColor.muted)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        row(number: "", white: "White", black: "Black", header: true)
                        ForEach(0..<((game.history.count + 1) / 2), id: \.self) { index in
                            let halfmove = index * 2
                            let black = game.history.indices.contains(halfmove + 1) ? game.history[halfmove + 1].notation : "—"
                            row(number: String(index + 1), white: game.history[halfmove].notation, black: black)
                                .background(index.isMultiple(of: 2) ? RoomColor.surface : RoomColor.background,
                                            in: .rect(cornerRadius: 9))
                                .accessibilityIdentifier("turn-\(index + 1)")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(RoomColor.background)
    }

    private func row(number: String, white: String, black: String, header: Bool = false) -> some View {
        HStack {
            Text(number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(RoomColor.muted)
                .frame(width: 38, alignment: .leading)
            Text(white).frame(maxWidth: .infinity, alignment: .leading)
            Text(black).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .font(header ? .footnote.weight(.semibold) : .subheadline.monospaced())
        .foregroundStyle(header ? RoomColor.accent : RoomColor.text)
        .accessibilityElement(children: .combine)
    }
}
