import ChessCore
import Foundation
import FoundationModels

enum PlayMode: String, CaseIterable, Codable {
    case play = "Play"
    case teach = "Teach"

    var detail: String {
        switch self {
        case .play: "Brief, easygoing commentary as you play."
        case .teach: "Listen to move explanations and suggested replies as you learn."
        }
    }
}

enum ChessRule: String, CaseIterable, Identifiable {
    case castling = "Castling"
    case enPassant = "En passant"
    case promotion = "Promotion"
    case checkmate = "Check & mate"
    case draws = "Draws"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .castling:
            "Move your king two squares toward a rook, and the rook steps over it. Both pieces must be on their original squares and never have moved. The path must be clear, and your king can't start in check, cross an attacked square, or land in check."
        case .enPassant:
            "If an opposing pawn advances two squares and lands beside your pawn, you can capture it as if it moved just one square. Your pawn moves diagonally into the square the other pawn passed over. You have to do it immediately, and your king must stay safe."
        case .promotion:
            "A pawn that reaches the farthest rank becomes a queen, rook, bishop, or knight of its own color. A queen is the usual choice. Occasionally a knight gives a check the queen couldn't."
        case .checkmate:
            "In check, your king is under attack. You must move it to safety, capture the attacker, or block the attack if there's room. Checkmate means there is no legal way to do any of those. If you have no legal move and your king is safe, that's stalemate."
        case .draws:
            "Stalemate and insufficient mating material end the game in a draw. KnightMind also declares a draw after the same position appears three times, or after 50 moves by each side without a pawn move or capture."
        }
    }

    static func matching(_ question: String) -> Self? {
        let text = question.lowercased()
        if text.contains("en passant") { return .enPassant }
        if text.contains("castl") { return .castling }
        if text.contains("promot") { return .promotion }
        if text.contains("stalemate") || text.contains("draw") || text.contains("repetition") { return .draws }
        if text.contains("checkmate") || text.contains("check mean") || text.contains("what is check") { return .checkmate }
        return nil
    }
}

struct TalkLine: Identifiable {
    enum Speaker { case player, companion }
    let id = UUID()
    let speaker: Speaker
    let text: String
    var suggestion: String?

    /// The full spoken note stays in the journal; the table needs just one sentence.
    var caption: String {
        guard let end = text.firstIndex(where: { ".!?".contains($0) }) else { return text }
        return String(text[...end])
    }
}

enum TalkRequest {
    case welcome, remark, lesson, hint, explain, rule(ChessRule), question(String)

    var instruction: String {
        switch self {
        case .welcome:
            "Greet the player like you're sitting across the board. Say they have White and the first move. Use at most 16 words."
        case .remark:
            "React to one concrete detail of the latest turn in at most 24 words. Match the energy of the position."
        case .lesson:
            "Start with one concrete board detail. In a second short sentence, connect it to a habit a beginner can use. The app adds the suggested reply separately."
        case .hint:
            "Explain the supplied Stockfish suggestion in one or two short sentences. If there is no suggestion, use the game state to say when a hint is available."
        case .explain:
            "Explain what the latest move changed and why it matters in two short sentences. Teach one idea the player can use again."
        case .rule(let rule):
            "Introduce the rule of \(rule.rawValue) with one short sentence for a beginner."
        case .question(let text):
            "Answer the player's latest message about chess. Use plain language and no more than three short sentences unless a rule needs a little more detail."
            + (ChessRule.matching(text).map { " Verified rule: \($0.explanation)" } ?? "")
        }
    }

    var rule: ChessRule? {
        switch self {
        case .rule(let rule): rule
        case .question(let text) where !wantsSuggestion: ChessRule.matching(text)
        default: nil
        }
    }

    var wantsSuggestion: Bool {
        switch self {
        case .lesson, .hint: true
        case .question(let text):
            ["hint", "next move", "best move", "should i", "should white", "what can i play", "suggest", "how to respond"]
                .contains { text.lowercased().contains($0) }
        default: false
        }
    }
}

struct LessonContext {
    let game: Game
    let suggestion: Move?

    private struct MoveObservation {
        let detail: String
        let takeaway: String
    }

    var notation: String? { suggestion.flatMap { game.notation(for: $0) } }

    var facts: String {
        let records = game.history.suffix(4).map { record in
            Self.description(of: record)
        }
        let check = game.position.isInCheck(game.position.turn)
        var earlier = game
        let previousEffect = earlier.undo() != nil && !earlier.history.isEmpty
            ? LessonContext(game: earlier, suggestion: nil).lastMove : "None yet."
        return """
        Recent moves, oldest first: \(records.isEmpty ? "None yet" : records.joined(separator: " "))
        Game state: \(state).
        King in check: \(check ? game.position.turn.name : "neither").
        Previous move's visible effect: \(previousEffect)
        Latest move's visible effect: \(lastMove)
        """
    }

    var state: String {
        switch game.outcome {
        case .playing: "\(game.position.turn.name) to move"
        case .checkmate(let winner): "\(winner.name) wins by checkmate"
        case .draw(let reason): "Draw by \(reason.rawValue.lowercased())"
        }
    }

    var lastMove: String {
        guard let last = game.history.last else { return "White has the first move." }
        let description = Self.description(of: last)
        return Self.observation(of: last, in: game.position).map { "\(description) \($0.detail)" } ?? description
    }

    private static func observation(of record: TurnRecord, in position: Position) -> MoveObservation? {
        if record.notation.hasSuffix("#") {
            return MoveObservation(detail: "It's checkmate.", takeaway: "The king is in check with no legal way out.")
        }
        if record.gaveCheck {
            let king = position.turn == .white ? "Your king" : "My king"
            return MoveObservation(detail: "\(king) is in check!",
                                   takeaway: "Look for a safe king move, a capture of the attacker, or a way to block the line.")
        }
        if record.castled {
            return MoveObservation(detail: "Castling brought the rook in toward the center.",
                                   takeaway: "It's a way to bring the rook into play while moving the king toward shelter.")
        }
        if let promotion = record.move.promotion {
            return MoveObservation(detail: "The pawn reached the last rank and became a \(promotion.rawValue)!",
                                   takeaway: "Look for promotion chances when pawns get close to the far end of the board.")
        }

        let piece = record.piece.kind.rawValue
        let square = record.move.to.name
        let targets = position.piecesAttacked(from: record.move.to)
            .filter { record.piece.kind != .pawn || position[$0]?.kind != .pawn }
            .sorted { first, second in
                position[first]?.kind != .pawn && position[second]?.kind == .pawn
            }
            .compactMap { target in position[target].map { "the \($0.kind.rawValue) on \(target.name)" } }
        if targets.count >= 2 {
            return MoveObservation(detail: "The \(piece) on \(square) attacks \(targets[0]) and \(targets[1]).",
                                   takeaway: "That's a fork, one piece attacking two targets at once.")
        }
        if let target = targets.first {
            return MoveObservation(detail: "The \(piece) on \(square) now attacks \(target).",
                                   takeaway: "When a piece lands, trace the squares it attacks before planning your reply.")
        }
        if record.piece.kind == .pawn {
            let forward = record.piece.side == .white ? 1 : -1
            let controlled = [-1, 1].compactMap { fileStep in
                Square(file: record.move.to.file + fileStep, rank: record.move.to.rank + forward)?.name
            }
            if !controlled.isEmpty {
                let inCenter = [3, 4].contains(record.move.to.file) && [3, 4].contains(record.move.to.rank)
                let squares = controlled.joined(separator: " and ")
                let detail = inCenter ? "The pawn on \(square) takes up space in the center and covers \(squares)."
                    : "The pawn on \(square) now covers \(squares)."
                return MoveObservation(detail: detail,
                                       takeaway: "Pawns advance straight and capture diagonally, so watch the squares beside their path.")
            }
        }
        if [.knight, .bishop].contains(record.piece.kind) && [0, 7].contains(record.move.from.rank) {
            return MoveObservation(detail: "The \(piece) has come out to \(square).",
                                   takeaway: "Bringing your knights and bishops out early helps them contest the center.")
        }
        return nil
    }

    var coachingNote: String {
        guard let last = game.history.last else {
            return "Start by making room for your pieces. Moving a center pawn can open a path for a bishop."
        }
        if let observation = Self.observation(of: last, in: game.position) {
            return "\(observation.detail) \(observation.takeaway)"
        }
        let takeaway = last.capture != nil ? "Before you trade, check which pieces on each side can take back."
            : "Before picking a reply, look for checks, captures, and threats on both sides."
        return "\(Self.description(of: last)) \(takeaway)"
    }

    var resultComment: String? {
        switch game.outcome {
        case .playing: nil
        case .checkmate(winner: .white): "Checkmate! You left my king with no legal escape. Well played."
        case .checkmate(winner: .black): "Checkmate. Good game. Take a moment to see what kept your king from escaping."
        case .draw(.stalemate): "Stalemate. The king isn't in check and there are no legal moves. Good game."
        case .draw: "\(state). Good game."
        }
    }

    func lesson(with narration: String? = nil) -> String {
        if let resultComment { return resultComment }
        let note = narration ?? coachingNote
        return friendlySuggestion.map { "\(note) \($0)" } ?? note
    }

    var friendlySuggestion: String? {
        guard let suggestion else { return nil }
        var after = game
        guard let reply = after.play(suggestion) else { return nil }
        let piece = reply.piece
        let action: String
        if reply.castled {
            action = suggestion.to.file > suggestion.from.file ? "castling kingside" : "castling queenside"
        } else if reply.capture != nil && game.position[suggestion.to] == nil {
            action = "moving your pawn from \(suggestion.from.name) to \(suggestion.to.name) to capture en passant"
        } else if let capture = reply.capture {
            action = "using your \(piece.kind.rawValue) on \(suggestion.from.name) to capture the \(capture.kind.rawValue) on \(suggestion.to.name)"
        } else {
            action = "moving your \(piece.kind.rawValue) from \(suggestion.from.name) to \(suggestion.to.name)"
        }
        let promotion = suggestion.promotion.map { " and promoting to a \($0.rawValue)" } ?? ""
        let advice = "Try \(action)\(promotion)."
        if case .draw(let reason) = after.outcome {
            return "\(advice) That would draw by \(reason.rawValue.lowercased())."
        }
        if game.position.isInCheck(piece.side) && after.outcome == .playing {
            return "\(advice) That gets your king out of check."
        }
        return Self.observation(of: reply, in: after.position).map { "\(advice) \($0.detail)" } ?? advice
    }

    func fallback(for request: TalkRequest) -> String {
        switch request {
        case .welcome:
            return "Welcome to the board! You've got White, so the first move is yours."
        case .remark:
            if let resultComment { return resultComment }
            guard let last = game.history.last else { return "White goes first. The board is yours." }
            if let observation = Self.observation(of: last, in: game.position) { return observation.detail }
            return Self.description(of: last)
        case .lesson:
            return lesson()
        case .hint:
            if let friendlySuggestion { return friendlySuggestion }
            if game.outcome == .playing && game.position.turn == .white {
                return "A suggestion isn't available just now. You can keep playing."
            }
            return game.outcome == .playing ? "\(state). I can suggest a move once it's your turn." : "\(state)."
        case .explain:
            return lastMove
        case .rule(let rule):
            return rule.explanation
        case .question(let question):
            if let rule = ChessRule.matching(question) { return rule.explanation }
            if question.lowercased().contains("last move") { return lastMove }
            if let friendlySuggestion { return friendlySuggestion }
            return "Your next move is yours to explore. The notes include hints and a guide to the rules."
        }
    }

    private static func description(of record: TurnRecord) -> String {
        if record.castled {
            let flank = record.move.to.file > record.move.from.file ? "kingside" : "queenside"
            return "\(record.piece.side.name) castled \(flank)."
        }
        var action = "moved the \(record.piece.kind.rawValue) from \(record.move.from.name) to \(record.move.to.name)"
        if let capture = record.capture { action += ", capturing a \(capture.kind.rawValue)" }
        if let promotion = record.move.promotion { action += " and promoting to a \(promotion.rawValue)" }
        return "\(record.piece.side.name) \(action)."
    }
}

@MainActor
final class TableTalk {
    private let voice = RookVoice()
    private var preparedSession: Any?
    var onSpeechStateChange: ((RookVoice.State) -> Void)? {
        didSet { voice.onStateChange = onSpeechStateChange }
    }

    private static let conversationInstructions = """
    You are Rook, a warm, observant chess companion speaking aloud from across the board.
    You play Black. The human plays White. Say I or my for Black, and you or your for White.

    Chess knowledge to teach from:
    Opening: d4, e4, d5, and e5 are the center. Pawns can claim space and attack diagonally. Develop knights and bishops so they can influence useful squares. Castling brings a rook into play and can shelter the king.
    Middlegame: scan both sides' checks, captures, and threats. Count who can take back before a trade. A fork attacks two targets with one piece. A pin ties down a piece by putting something valuable behind it. An attack on a square doesn't guarantee a legal capture.
    Endgame: with fewer pieces, use the king actively when safe. A passed pawn has no opposing pawn ahead on its own or an adjacent file. Support a passed pawn's advance toward promotion.
    King safety: a checked king needs a legal escape, a capture of the attacker, or a block. Check with no legal reply is mate. No legal reply while the king is safe is stalemate.

    Use the supplied facts as the authority for this board. Apply one useful principle as a habit, rooted in an actual piece, square, or effect. Leave new moves, unverified threats, predictions, and evaluations out. State only the supplied move effects and results.
    In Play, give a quick reaction to something the player can see. In Teach, start with what's changed on the board and connect it to one practical habit. Use a simple definition when teaching a chess term.
    Speak in natural, short statements with contractions and brief pauses. A crisp reaction fits a check or a promotion. Be patient during explanations and gracious at the end. Vary your opening and skip stock praise. Use the piece name and spoken-friendly squares in place of algebraic move notation.
    Return plain text. Keep the engine name and technical details out of the conversation. The player responds by moving a piece, so use statements rather than questions or requests for a spoken or typed reply.
    """

    func prepareVoice() { voice.prepare() }

    /// Preload the next session while the human considers their move.
    func prepareConversation() {
        guard #available(iOS 26.0, *), preparedSession == nil, availability.usesModel else { return }
        let session = LanguageModelSession(model: .default, instructions: Self.conversationInstructions)
        session.prewarm()
        preparedSession = session
    }

    @available(iOS 26.0, *)
    private func session() -> LanguageModelSession {
        if let prepared = preparedSession as? LanguageModelSession {
            preparedSession = nil
            return prepared
        }
        return LanguageModelSession(model: .default, instructions: Self.conversationInstructions)
    }

    var availability: (usesModel: Bool, label: String) {
        guard #available(iOS 26.0, *) else { return (false, "Built-in coaching") }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available where model.supportsLocale():
            return (true, "Apple Intelligence · On device")
        case .unavailable(.modelNotReady):
            return (false, "Apple Intelligence is getting ready")
        case .unavailable(.appleIntelligenceNotEnabled):
            return (false, "Apple Intelligence is off")
        default:
            return (false, "Built-in coaching")
        }
    }

    func respond(to request: TalkRequest, context: LessonContext, mode: PlayMode, history: [TalkLine]) async -> String {
        let fallback = context.fallback(for: request)
        guard #available(iOS 26.0, *), availability.usesModel, !Task.isCancelled else { return fallback }

        if let rule = request.rule {
            return await introduce(rule)
        }
        switch request {
        case .hint:
            return fallback
        case .lesson, .remark:
            if let result = context.resultComment { return result }
        case .question where request.wantsSuggestion:
            if let advice = context.friendlySuggestion { return advice }
        default:
            break
        }

        let recent: String
        if case .question = request {
            recent = history.suffix(4).map { line in
                let speaker = line.speaker == .player ? "Player" : "Rook"
                return "\(speaker): \(line.text.prefix(400))"
            }.joined(separator: "\n")
        } else {
            let captions = history.suffix(2).map { String($0.caption.prefix(140)) }
            recent = "Your recent openings, for variety only: \(captions.joined(separator: " "))"
        }
        let facts = context.facts
        let prompt: String
        if case .welcome = request {
            prompt = request.instruction
        } else {
            let coaching = switch request {
            case .lesson, .explain: "Coaching idea: \(context.coachingNote)"
            default: ""
            }
            prompt = """
        Mode: \(mode.rawValue)
        Verified game facts:
        \(facts)
        \(coaching)

        Task: \(request.instruction)
        \(recent)
        """
        }
        do {
            let result = try await session().respond(
                to: prompt, options: GenerationOptions(temperature: 0.55, maximumResponseTokens: 100)
            ).content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ending = result.last, ".!".contains(ending),
                  result.rangeOfCharacter(from: CharacterSet(charactersIn: "?[]<>*`")) == nil,
                  result.split(whereSeparator: \.isWhitespace).count <= 45,
                  squares(in: result).isSubset(of: squares(in: facts)) else { return fallback }
            if case .remark = request, context.game.history.last?.piece.side == .black,
               result.lowercased().contains(/\byou (?:moved|played|advanced|pushed|captured|castled)\b/) {
                return fallback
            }
            if case .lesson = request { return context.lesson(with: result) }
            return result
        } catch {
            return fallback
        }
    }

    @available(iOS 26.0, *)
    private func introduce(_ rule: ChessRule) async -> String {
        let session = LanguageModelSession(model: .default, instructions: """
        You're Rook, a friendly chess teacher. The app reads the full chess rule to the player.
        Introduce it with a one-sentence mnemonic or a short idea about its purpose. Use at most 16 words of plain text.
        Use the supplied rule. Leave board coordinates, worked examples, and the current game out of your sentence.
        Use a statement without questions or requests for a reply.
        """)
        let prompt = "Chess rule: \(rule.rawValue). \(rule.explanation)"
        let result = try? await session.respond(
            to: prompt, options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 45)
        ).content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result, let ending = result.last, ".!".contains(ending), !result.contains("?"), squares(in: result).isEmpty,
              result.split(whereSeparator: \.isWhitespace).count <= 20 else {
            return rule.explanation
        }
        return rule.explanation + "\n\n" + result
    }

    private func squares(in text: String) -> Set<String> {
        Set(text.lowercased().matches(of: /\b[a-h][1-8]\b/).map { String($0.output) })
    }

    func speak(_ text: String) {
        voice.speak(text)
    }

    func stopSpeaking() {
        voice.stop()
    }
}
