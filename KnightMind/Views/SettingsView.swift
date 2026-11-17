import SwiftUI

struct SettingsView: View {
    let match: Match
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    setting("Board view") {
                        ChoiceStrip(options: [BoardView.perspective, .overhead], selected: match.board,
                                    title: \.rawValue,
                                    symbol: { $0 == .perspective ? "cube" : "square.grid.2x2" },
                                    select: match.setBoard)
                        detail("One wooden board. View it in 3D or directly from above.")
                    }

                    setting("Game mode") {
                        ChoiceStrip(options: PlayMode.allCases, selected: match.mode,
                                    title: \.rawValue, select: match.setMode)
                        detail(match.mode.detail)
                    }

                    setting("Stockfish difficulty") {
                        ChoiceStrip(options: Difficulty.allCases, selected: match.level,
                                    title: \.rawValue, select: match.setLevel)
                        detail(match.level.detail)
                    }

                    setting("Rook") {
                        Toggle("Spoken commentary", isOn: Binding(get: { match.speech }, set: match.setSpeech))
                            .tint(Color(rgb: 0x6A7839))
                            .padding(13)
                            .background(RoomColor.surface, in: .rect(cornerRadius: 12))
                            .foregroundStyle(RoomColor.text)
                        detail("Rook speaks as you play. Just listen and make your next move.")
                        if let status = match.voiceStatus {
                            detail(status)
                        }
                        detail(match.companionStatus)
                    }

                    setting("About KnightMind") {
                        detail("Play chess on a wooden board in 3D or from above. Meet Rook, an on-device conversation partner and chess tutor.")
                        detail("KnightMind is free software under the GNU General Public License v3.")
                        detail("Rook's voice is powered by KittenTTS, by KittenML. The SDK and model use the Apache License 2.0; its eSpeak NG pronunciation data uses GPL v3 or later.")
                        Link(destination: URL(string: "https://github.com/KittenML/KittenTTS-swift")!) {
                            Label("KittenTTS project", systemImage: "arrow.up.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RoomColor.accent)
                        detail("Computer moves and hints are powered by Stockfish 19, by the Stockfish developers. Stockfish is free software under the GNU General Public License v3.")
                        Link(destination: URL(string: "https://github.com/official-stockfish/Stockfish/tree/sf_19")!) {
                            Label("Stockfish project", systemImage: "arrow.up.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RoomColor.accent)
                        .padding(.top, 3)
                        Button("Open-source licenses") { showLicenses = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RoomColor.accent)
                            .padding(.top, 3)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(RoomColor.background)
        .sheet(isPresented: $showLicenses) {
            LicensesView()
                .presentationDragIndicator(.visible)
                .presentationBackground(RoomColor.background)
        }
    }

    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .foregroundStyle(RoomColor.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(RoomColor.muted)
            .lineSpacing(3)
    }
}
