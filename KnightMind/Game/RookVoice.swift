import AVFAudio
import KittenTTS
import os

@MainActor
final class RookVoice: NSObject, AVAudioPlayerDelegate {
    enum State {
        case idle, preparing, speaking, unavailable
    }

    var onStateChange: ((State) -> Void)?

    private let logger = Logger(subsystem: "info.homerquan.knightmind", category: "RookVoice")
    private var engine: KittenTTS?
    private var loadingTask: Task<KittenTTS, Error>?
    private var preparationTask: Task<Void, Never>?
    private var synthesisTask: Task<Void, Never>?
    private var requestID = UUID()
    private var player: AVAudioPlayer?
    private var audioSessionActive = false

    /// Loads the bundled default voice before the first spoken note.
    func prepare() {
        guard engine == nil, preparationTask == nil else { return }
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer { preparationTask = nil }
            do {
                _ = try await loadEngine()
            } catch {
                logger.error("Voice preparation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func speak(_ text: String) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let ticket = requestID
        let previous = synthesisTask
        onStateChange?(.preparing)

        synthesisTask = Task { [weak self] in
            // SDK inference runs in a detached task. Drain it before starting another
            // request, and discard its output if the player moved or muted Rook.
            await previous?.value
            guard let self, !Task.isCancelled, requestID == ticket else { return }
            do {
                let engine = try await loadEngine()
                try Task.checkCancellation()
                let result = try await engine.generate(Self.spokenText(text))
                try Task.checkCancellation()
                guard requestID == ticket else { return }
                try play(result.wavData())
            } catch is CancellationError {
                // stop() already reset the UI and invalidated this request.
            } catch {
                guard !Task.isCancelled, requestID == ticket else { return }
                finish(successfully: false)
                logger.error("Speech failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        requestID = UUID()
        synthesisTask?.cancel()
        player?.stop()
        player = nil
        deactivateAudioSession()
        onStateChange?(.idle)
    }

    private func loadEngine() async throws -> KittenTTS {
        if let engine { return engine }
        if let loadingTask { return try await loadingTask.value }

        var config = try KittenTTSBundledAssets.configFromBundle(defaultVoice: .jasper)
        // Offset the model's voice-specific multiplier to synthesize speech at 1×.
        config.speed = 1.0 / config.model.speedPrior(for: config.defaultVoice)
        config.phonemizer = .custom(CommentaryPhonemizer(base: try config.phonemizer.resolve()))
        let task = Task { try await KittenTTS(config) }
        loadingTask = task
        do {
            let loaded = try await task.value
            engine = loaded
            loadingTask = nil
            return loaded
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private static func spokenText(_ text: String) -> String {
        // Separate the file and rank so the phonemizer reads e4 as "E four".
        text.replacing(/\b([a-hA-H])([1-8])\b/) { square in
            let file = square.1.uppercased()
            let letter = file == "A" ? "ay" : file
            return "\(letter) \(square.2)"
        }
    }

    private func play(_ audio: Data) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)
        audioSessionActive = true

        let player = try AVAudioPlayer(data: audio)
        player.delegate = self
        self.player = player
        guard player.prepareToPlay(), player.play() else {
            throw KittenTTSError.playbackFailed("Unable to start audio playback")
        }
        onStateChange?(.speaking)
    }

    private func finish(successfully: Bool) {
        player = nil
        deactivateAudioSession()
        onStateChange?(successfully ? .idle : .unavailable)
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionActive = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playbackEnded(player, successfully: flag)
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        playbackEnded(player, successfully: false)
    }

    private nonisolated func playbackEnded(_ player: AVAudioPlayer, successfully: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identifier else { return }
            finish(successfully: successfully)
        }
    }
}

/// Retains the punctuation tokens Nano uses for phrasing around the bundled English pronunciation data.
private struct CommentaryPhonemizer: KittenPhonemizerProtocol {
    let base: any KittenPhonemizerProtocol

    func downloadIfNeeded(
        to storageDirectory: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        try await base.downloadIfNeeded(to: storageDirectory, progressHandler: progressHandler)
    }

    func phonemize(_ text: String) -> String {
        text.matches(of: /([^,.!?;:—]+)([,.!?;:—]*)/).compactMap { clause in
            let phonemes = base.phonemize(String(clause.1))
            guard !phonemes.isEmpty else { return nil }
            return phonemes + clause.2.prefix(1)
        }.joined(separator: " ")
    }
}
