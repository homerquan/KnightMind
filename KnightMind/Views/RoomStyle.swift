import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
}

enum RoomColor {
    static let background = Color(rgb: 0x171A14)
    static let surface = Color(rgb: 0x22261D)
    static let raised = Color(rgb: 0x2C3026)
    static let rim = Color(rgb: 0xECE2C4).opacity(0.14)
    static let text = Color(rgb: 0xF3EDDE)
    static let muted = Color(rgb: 0xB5B4A5)
    static let accent = Color(rgb: 0xDFE9A9)
    static let ink = Color(rgb: 0x222619)
    static let brass = Color(rgb: 0xD8B582)
}

struct RoomBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoomColor.background
                Image("Felt")
                    .resizable(resizingMode: .tile)
                RadialGradient(
                    colors: [Color(rgb: 0x414537).opacity(0.68), RoomColor.background.opacity(0.66), .black.opacity(0.45)],
                    center: UnitPoint(x: 0.48, y: 0.42),
                    startRadius: 25,
                    endRadius: max(geometry.size.height * 0.68, geometry.size.width * 0.6)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct RoomTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom("InstrumentSerif-Regular", size: 46, relativeTo: .largeTitle))
            .foregroundStyle(RoomColor.text)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ChoiceStrip<Choice: Hashable>: View {
    let options: [Choice]
    let selected: Choice
    let title: (Choice) -> String
    var symbol: ((Choice) -> String)?
    var compact = false
    let select: (Choice) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                Button {
                    select(option)
                } label: {
                    HStack(spacing: 5) {
                        if let symbol {
                            Image(systemName: symbol(option)).font(.system(size: 11, weight: .semibold))
                        }
                        Text(title(option)).lineLimit(1)
                    }
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(selected == option ? RoomColor.ink : RoomColor.muted)
                    .padding(.horizontal, compact ? 8 : 7)
                    .frame(maxWidth: compact ? nil : .infinity)
                    .frame(minHeight: compact ? 36 : 42)
                    .background {
                        if selected == option {
                            RoundedRectangle(cornerRadius: 8).fill(RoomColor.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoomColor.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RoomColor.rim, lineWidth: 1))
    }
}

struct IconControl: View {
    let symbol: String
    let label: String
    var color = RoomColor.muted
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(RoomColor.raised, in: .rect(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(RoomColor.rim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SheetHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center) {
            RoomTitle(text: title)
            Spacer(minLength: 12)
            IconControl(symbol: "xmark", label: "Close", size: 44) { dismiss() }
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
        .padding(.horizontal, 22)
    }
}
