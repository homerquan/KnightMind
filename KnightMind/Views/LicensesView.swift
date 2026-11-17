import SwiftUI

struct LicensesView: View {
    private let documents = [
        (title: "GNU General Public License v3", resource: "Stockfish-LICENSE"),
        (title: "Apache License 2.0", resource: "Apache-2.0-LICENSE"),
        (title: "ONNX Runtime · MIT License", resource: "ONNXRuntime-LICENSE"),
        (title: "ONNX Runtime third-party notices", resource: "ONNXRuntime-ThirdPartyNotices"),
        (title: "Stockfish authors", resource: "Stockfish-AUTHORS"),
        (title: "Instrument Serif · Open Font License", resource: "InstrumentSerif-OFL")
    ]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Licenses")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(contents(of: "ThirdParty-NOTICES"))
                        .textSelection(.enabled)
                    ForEach(documents, id: \.resource) { document in
                        DisclosureGroup(document.title) {
                            Text(contents(of: document.resource))
                                .textSelection(.enabled)
                                .padding(.top, 12)
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(RoomColor.text)
                .lineSpacing(3)
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(RoomColor.background)
    }

    private func contents(of resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return text
    }
}
