import ChessCore
import Foundation
import Observation

enum BoardView: String, Codable {
    case perspective = "3D"
    case overhead = "2D"
}

struct BoardState {
    let position: Position
    let recent: Move?
    let selected: Square?
    let destinations: Set<Square>
    let checked: Square?
    let hint: Move?
    let revision: Int
}

@MainActor
@Observable
final class Match {
    private struct Save: Codable {
        var moves: [Move] = []
        var level: Difficulty = .club
        var mode: PlayMode = .play
        var board: BoardView = .perspective
        var speech: Bool = true
    }

    private static let saveKey = "chessroom.match.v1"
    private static let opening = TalkLine(
        speaker: .companion, text: "White goes first. The board is yours.", suggestion: nil
    )

    private let defaults: UserDefaults
    private let opponent = Opponent()
    private let companion = TableTalk()
    @ObservationIgnored private var computerTask: Task<Void, Never>?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var greeted = false
    @ObservationIgnored private var replyID = UUID()

    private(set) var game: Game
    private(set) var level: Difficulty
    private(set) var mode: PlayMode
    private(set) var board: BoardView
    private(set) var speech: Bool
    private(set) var selected: Square?
    private(set) var hint: Move?
    private(set) var revision = 0
    private(set) var promotion: [Move] = []
    private(set) var thinking = false
    private(set) var engineError = false
    private(set) var replying = false
    private(set) var voiceState = RookVoice.State.idle
    private(set) var lines = [Match.opening]
    private(set) var companionStatus = "Built-in coaching"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = defaults.data(forKey: Self.saveKey).flatMap { try? JSONDecoder().decode(Save.self, from: $0) } ?? Save()
        game = Game(replaying: loaded.moves) ?? Game()
        level = loaded.level
        mode = loaded.mode
        board = loaded.board
        speech = loaded.speech
        companion.onSpeechStateChange = { [weak self] state in self?.voiceState = state }
        if !game.history.isEmpty {
            lines = [TalkLine(speaker: .companion,
                              text: LessonContext(game: game, suggestion: nil).lastMove, suggestion: nil)]
        }
    }

    var boardState: BoardState {
        BoardState(
            position: game.position, recent: game.history.last?.move, selected: selected,
            destinations: Set(game.legalMoves.filter { $0.from == selected }.map(\.to)),
            checked: game.position.isInCheck(game.position.turn) ? game.position.kingSquare(for: game.position.turn) : nil,
            hint: hint, revision: revision
        )
    }

    var lastLine: TalkLine { lines.last { $0.speaker == .companion } ?? Self.opening }

    var speaking: Bool { voiceState == .speaking }
    var preparingSpeech: Bool { voiceState == .preparing }

    var voiceStatus: String? {
        switch voiceState {
        case .preparing: "Preparing Rook's voice…"
        case .unavailable: "Voice unavailable. Rook will try again on the next note."
        default: nil
        }
    }

    var status: String {
        switch game.outcome {
        case .playing where engineError: "Engine unavailable"
        case .playing where thinking: "Thinking"
        case .playing where game.position.turn == .white:
            game.position.isInCheck(.white) ? "You're in check" : "Your move"
        case .playing: "Computer's move"
        case .checkmate(let winner): winner == .white ? "You win" : "Checkmate"
        case .draw: "Draw"
        }
    }

    var resultDetail: String? {
        switch game.outcome {
        case .playing: nil
        case .checkmate(let winner): "\(winner.name) wins by checkmate"
        case .draw(let reason): reason.rawValue
        }
    }

    func activate() {
        companionStatus = companion.availability.label
        if speech { companion.prepareVoice() }
        companion.prepareConversation()
        opponent.warmUp()
        computerTurn()
        if !greeted {
            greeted = true
            if game.position.turn == .white {
                request(game.history.isEmpty ? .welcome : mode == .teach ? .lesson : .remark)
            }
        }
    }

    func suspend() {
        computerTask?.cancel()
        thinking = false
        cancelReply()
        companion.stopSpeaking()
    }

    func setLevel(_ value: Difficulty) {
        guard level != value else { return }
        level = value
        save()
        if game.position.turn == .black && game.outcome == .playing {
            computerTask?.cancel()
            thinking = false
            computerTurn()
        }
    }

    func setMode(_ value: PlayMode) {
        guard mode != value else { return }
        cancelReply()
        companion.stopSpeaking()
        hint = nil
        mode = value
        companion.prepareConversation()
        save()
        if mode == .teach && game.position.turn == .white {
            request(.lesson)
        }
    }

    func setBoard(_ value: BoardView) {
        board = value
        save()
    }

    func setSpeech(_ value: Bool) {
        speech = value
        if !value {
            companion.stopSpeaking()
        } else if !replying {
            companion.speak(lastLine.text)
        }
        save()
    }

    func tap(_ square: Square) {
        guard game.outcome == .playing, game.position.turn == .white, promotion.isEmpty else { return }
        if selected == square {
            selected = nil
        } else if game.position[square]?.side == .white {
            selected = square
            hint = nil
        } else if let selected {
            let moves = game.legalMoves.filter { $0.from == selected && $0.to == square }
            if moves.count > 1 {
                promotion = moves
            } else if let move = moves.first {
                play(move)
            } else {
                self.selected = nil
            }
        }
    }

    func promote(to kind: PieceKind) {
        guard let move = promotion.first(where: { $0.promotion == kind }) else { return }
        play(move)
    }

    func dismissPromotion() { promotion = [] }

    func newGame() {
        resetWork()
        game = Game()
        lines = [Self.opening]
        save()
        request(.welcome)
    }

    func undo() {
        guard !game.history.isEmpty else { return }
        resetWork()
        if game.undo()?.piece.side == .black { game.undo() }
        lines = [TalkLine(speaker: .companion, text: "We've taken back the last turn. Your move.", suggestion: nil)]
        save()
    }

    func retry() { computerTurn() }

    func request(_ kind: TalkRequest) {
        cancelReply()
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }

        let snapshot = game
        let currentRevision = revision
        let canSuggest = kind.wantsSuggestion && snapshot.outcome == .playing && snapshot.position.turn == .white
        let history = lines
        let mode = mode
        let ticket = replyID
        companionStatus = companion.availability.label
        replying = true
        replyTask = Task { [weak self, opponent, companion, level] in
            let suggestion = canSuggest ? await opponent.move(in: snapshot, difficulty: level, coaching: true) : nil
            guard !Task.isCancelled else { return }
            let context = LessonContext(game: snapshot, suggestion: suggestion)
            let result = await companion.respond(to: kind, context: context, mode: mode, history: history)
            guard !Task.isCancelled, let self, replyID == ticket, revision == currentRevision else { return }
            let showSuggestion = suggestion != nil
            if case .welcome = kind, game.history.isEmpty { lines.removeAll() }
            lines.append(TalkLine(speaker: .companion, text: result,
                                  suggestion: showSuggestion ? context.notation : nil))
            if showSuggestion { hint = suggestion }
            replying = false
            if speech { companion.speak(result) }
            companion.prepareConversation()
        }
    }

    private func play(_ move: Move) {
        guard let record = game.play(move) else { return }
        revision += 1
        selected = nil
        promotion = []
        hint = nil
        cancelReply()
        if record.piece.side == .white { companion.stopSpeaking() }
        save()

        if game.outcome != .playing {
            request(mode == .teach ? .lesson : .remark)
        } else if record.piece.side == .white {
            computerTurn()
        } else if mode == .teach {
            request(.lesson)
        } else {
            request(.remark)
        }
    }

    private func computerTurn() {
        guard !thinking, game.outcome == .playing, game.position.turn == .black else { return }
        engineError = false
        thinking = true
        let snapshot = game
        let ticket = revision
        computerTask = Task { [weak self, opponent, level] in
            let move = await opponent.move(in: snapshot, difficulty: level)
            guard !Task.isCancelled, let self, revision == ticket else { return }
            thinking = false
            if let move {
                play(move)
            } else {
                engineError = true
            }
        }
    }

    private func cancelReply() {
        replyTask?.cancel()
        replyID = UUID()
        replying = false
    }

    private func resetWork() {
        revision += 1
        computerTask?.cancel()
        cancelReply()
        companion.stopSpeaking()
        thinking = false
        engineError = false
        selected = nil
        hint = nil
        promotion = []
    }

    private func save() {
        let save = Save(moves: game.history.map(\.move), level: level, mode: mode, board: board, speech: speech)
        if let data = try? JSONEncoder().encode(save) { defaults.set(data, forKey: Self.saveKey) }
    }
}
