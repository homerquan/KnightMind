public enum DrawReason: String, Sendable {
    case stalemate = "Stalemate"
    case repetition = "Threefold repetition"
    case fiftyMoveRule = "Fifty-move rule"
    case insufficientMaterial = "Insufficient material"
}

public enum Outcome: Equatable, Sendable {
    case playing
    case checkmate(winner: Side)
    case draw(DrawReason)
}

public struct TurnRecord: Equatable, Sendable {
    public let move: Move
    public let piece: Piece
    public let capture: Piece?
    public let notation: String
    public let gaveCheck: Bool
    public let castled: Bool
}

public struct Game: Sendable {
    private struct PositionKey: Hashable, Sendable {
        let board: [Piece?]
        let turn: Side
        let castling: CastlingRights
        let enPassant: Square?

        init(position: Position, moves: [Move]) {
            board = position.board
            turn = position.turn
            castling = position.castling
            if let target = position.enPassant,
               moves.contains(where: {
                   $0.to == target && $0.from.file != target.file && position[$0.from]?.kind == .pawn
               }) {
                enPassant = target
            } else {
                enPassant = nil
            }
        }
    }

    public private(set) var position: Position
    public private(set) var legalMoves: [Move]
    public private(set) var outcome: Outcome
    public private(set) var history: [TurnRecord] = []
    private var previous: [Position] = []
    private var repetitions: [PositionKey: Int]

    public init() { self.init(position: .initial) }

    init(position: Position) {
        self.position = position
        legalMoves = position.legalMoves()
        repetitions = [PositionKey(position: position, moves: legalMoves): 1]
        outcome = Self.outcome(in: position, moves: legalMoves, repetitions: 1)
    }

    public init?(replaying moves: [Move]) {
        self.init()
        for move in moves {
            guard play(move) != nil else { return nil }
        }
    }

    public func notation(for move: Move) -> String? {
        guard legalMoves.contains(move) else { return nil }
        let next = position.applying(move)
        let check = next.isInCheck(next.turn)
        return notation(for: move, check: check, mate: check && next.legalMoves().isEmpty)
    }

    @discardableResult
    public mutating func play(_ move: Move) -> TurnRecord? {
        guard outcome == .playing, legalMoves.contains(move), let piece = position[move.from] else { return nil }
        let next = position.applying(move)
        let moves = next.legalMoves()
        let check = next.isInCheck(next.turn)
        let record = TurnRecord(
            move: move, piece: piece, capture: position.capturedPiece(by: move),
            notation: notation(for: move, check: check, mate: moves.isEmpty),
            gaveCheck: check, castled: position.isCastle(move)
        )
        previous.append(position)
        history.append(record)
        position = next
        legalMoves = moves
        let count = repetitions[PositionKey(position: next, moves: moves), default: 0] + 1
        repetitions[PositionKey(position: next, moves: moves)] = count
        outcome = Self.outcome(in: next, moves: moves, repetitions: count)
        return record
    }

    @discardableResult
    public mutating func undo() -> TurnRecord? {
        guard let lastPosition = previous.popLast() else { return nil }
        let key = PositionKey(position: position, moves: legalMoves)
        let count = repetitions[key, default: 1]
        repetitions[key] = count > 1 ? count - 1 : nil
        position = lastPosition
        legalMoves = position.legalMoves()
        outcome = Self.outcome(in: position, moves: legalMoves,
                               repetitions: repetitions[PositionKey(position: position, moves: legalMoves), default: 1])
        return history.popLast()
    }

    private static func outcome(in position: Position, moves: [Move], repetitions: Int) -> Outcome {
        if moves.isEmpty {
            return position.isInCheck(position.turn) ? .checkmate(winner: position.turn.opponent) : .draw(.stalemate)
        }
        if position.hasInsufficientMaterial { return .draw(.insufficientMaterial) }
        if position.halfmoveClock >= 100 { return .draw(.fiftyMoveRule) }
        if repetitions >= 3 { return .draw(.repetition) }
        return .playing
    }

    private func notation(for move: Move, check: Bool, mate: Bool) -> String {
        let suffix = check ? (mate ? "#" : "+") : ""
        if position.isCastle(move) {
            return (move.to.file > move.from.file ? "O-O" : "O-O-O") + suffix
        }
        let piece = position[move.from]!
        let isCapture = position.capturedPiece(by: move) != nil
        var prefix = piece.kind.letter
        if piece.kind == .pawn {
            if isCapture { prefix = move.from.fileName }
        } else {
            let rivals = legalMoves.filter {
                $0.to == move.to && $0.from != move.from && position[$0.from] == piece
            }
            if !rivals.isEmpty {
                let sharesFile = rivals.contains { $0.from.file == move.from.file }
                let sharesRank = rivals.contains { $0.from.rank == move.from.rank }
                if !sharesFile || sharesRank { prefix += move.from.fileName }
                if sharesFile { prefix += String(move.from.rank + 1) }
            }
        }
        let promotion = move.promotion.map { "=" + $0.letter } ?? ""
        return prefix + (isCapture ? "x" : "") + move.to.name + promotion + suffix
    }
}
