import SwiftUI

@main
struct KnightMindApp: App {
    @State private var match: Match

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KNIGHTMIND_UI_TEST_OFFLINE"] == "1" {
            URLProtocol.registerClass(OfflineUITestProtocol.self)
        }
        if let suite = ProcessInfo.processInfo.environment["KNIGHTMIND_UI_TEST_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            _match = State(initialValue: Match(defaults: defaults))
            return
        }
        #endif
        _match = State(initialValue: Match())
    }

    var body: some Scene {
        WindowGroup {
            RoomView(match: match)
                .preferredColorScheme(.dark)
                .tint(RoomColor.accent)
        }
    }
}

#if DEBUG
/// Lets the speech UI test verify first-launch playback without network access.
private final class OfflineUITestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
