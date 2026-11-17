public enum Side: String, Codable, Sendable {
    case white, black

    public var opponent: Side { self == .white ? .black : .white }
    public var name: String { rawValue.capitalizedWord }

    var pawnStep: Int { self == .white ? 1 : -1 }
    var homeRank: Int { self == .white ? 0 : 7 }
}

private extension String {
    var capitalizedWord: String { prefix(1).uppercased() + dropFirst() }
}

public enum PieceKind: String, CaseIterable, Codable, Sendable {
    case pawn, knight, bishop, rook, queen, king

    public static let promotions: [Self] = [.queen, .rook, .bishop, .knight]
    public var name: String { rawValue.capitalizedWord }

    var letter: String {
        switch self {
        case .pawn: ""
        case .knight: "N"
        default: String(name.prefix(1))
        }
    }
}

public struct Piece: Hashable, Codable, Sendable {
    public let side: Side
    public let kind: PieceKind

    public init(_ side: Side, _ kind: PieceKind) {
        self.side = side
        self.kind = kind
    }
}

public struct Square: Hashable, Codable, Sendable {
    let index: Int

    public static let all = (0..<64).map { Square(index: $0) }
    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }
    public var isLight: Bool { (file + rank) % 2 == 1 }
    public var fileName: String { String(UnicodeScalar(97 + file)!) }
    public var name: String { fileName + String(rank + 1) }

    init(index: Int) {
        self.index = index
    }

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.init(index: rank * 8 + file)
    }

    public init?(named name: String) {
        let characters = Array(name.utf8)
        guard characters.count == 2 else { return nil }
        self.init(file: Int(characters[0]) - 97, rank: Int(characters[1]) - 49)
    }

    func offset(file: Int, rank: Int) -> Square? {
        Square(file: self.file + file, rank: self.rank + rank)
    }
}

public struct Move: Hashable, Codable, Sendable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public var uci: String {
        from.name + to.name + (promotion?.letter.lowercased() ?? "")
    }
}

struct CastlingRights: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let all = Self(rawValue: 0b1111)

    static func right(for side: Side, kingside: Bool) -> Self {
        let sideOffset = side == .white ? 0 : 2
        return Self(rawValue: 1 << (sideOffset + (kingside ? 0 : 1)))
    }

    mutating func revoke(for side: Side) {
        subtract([Self.right(for: side, kingside: true), Self.right(for: side, kingside: false)])
    }

    mutating func revokeRook(at square: Square, side: Side) {
        guard square.rank == side.homeRank, square.file == 0 || square.file == 7 else { return }
        remove(Self.right(for: side, kingside: square.file == 7))
    }
}

public struct Position: Sendable {
    private static let knightSteps = [
        (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)
    ]
    private static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let straights = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let adjacent = diagonals + straights

    private(set) var board: [Piece?]
    public private(set) var turn: Side
    private(set) var castling: CastlingRights
    public private(set) var enPassant: Square?
    public private(set) var halfmoveClock: Int
    private var whiteKing: Square
    private var blackKing: Square

    public static let initial: Self = {
        let backRank: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        return Self(
            board: backRank.map { Piece(.white, $0) }
                + Array(repeating: Piece(.white, .pawn), count: 8)
                + Array(repeating: nil, count: 32)
                + Array(repeating: Piece(.black, .pawn), count: 8)
                + backRank.map { Piece(.black, $0) },
            turn: .white, castling: .all
        )
    }()

    init(board: [Piece?], turn: Side, castling: CastlingRights = [], enPassant: Square? = nil,
         halfmoveClock: Int = 0) {
        self.board = board
        self.turn = turn
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        whiteKing = Square(index: board.firstIndex(of: Piece(.white, .king))!)
        blackKing = Square(index: board.firstIndex(of: Piece(.black, .king))!)
    }

    public subscript(_ square: Square) -> Piece? { board[square.index] }

    public func kingSquare(for side: Side) -> Square { side == .white ? whiteKing : blackKing }

    public func isInCheck(_ side: Side) -> Bool {
        isAttacked(kingSquare(for: side), by: side.opponent)
    }

    public func isAttacked(_ square: Square, by side: Side) -> Bool {
        for step in [-1, 1] {
            if let source = square.offset(file: step, rank: -side.pawnStep),
               self[source] == Piece(side, .pawn) { return true }
        }
        for (file, rank) in Self.knightSteps {
            if let source = square.offset(file: file, rank: rank),
               self[source] == Piece(side, .knight) { return true }
        }
        for (file, rank) in Self.adjacent {
            var source = square.offset(file: file, rank: rank)
            var first = true
            while let candidate = source {
                if let piece = self[candidate] {
                    if piece.side == side {
                        let slider: PieceKind = file == 0 || rank == 0 ? .rook : .bishop
                        if piece.kind == slider || piece.kind == .queen || (first && piece.kind == .king) {
                            return true
                        }
                    }
                    break
                }
                first = false
                source = candidate.offset(file: file, rank: rank)
            }
        }
        return false
    }

    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for square in Square.all {
            guard let piece = self[square], piece.side == turn else { continue }
            appendMoves(for: piece, at: square, to: &moves)
        }
        return moves.filter { !applying($0).isInCheck(turn) }
    }

    public func capturedPiece(by move: Move) -> Piece? {
        if let target = self[move.to] { return target }
        guard self[move.from]?.kind == .pawn, move.to == enPassant, move.from.file != move.to.file,
              let captured = Square(file: move.to.file, rank: move.from.rank) else { return nil }
        return self[captured]
    }

    public func isCastle(_ move: Move) -> Bool {
        self[move.from]?.kind == .king && abs(move.from.file - move.to.file) == 2
    }

    public func piecesAttacked(from square: Square) -> [Square] {
        guard let piece = self[square] else { return [] }
        var viewpoint = self
        viewpoint.turn = piece.side
        var moves: [Move] = []
        viewpoint.appendMoves(for: piece, at: square, to: &moves)
        return Square.all.filter { target in
            self[target]?.side == piece.side.opponent && moves.contains { $0.to == target }
        }
    }

    func applying(_ move: Move) -> Position {
        var next = self
        let piece = self[move.from]!
        let capture = capturedPiece(by: move)
        next.board[move.from.index] = nil
        if piece.kind == .pawn, capture != nil, self[move.to] == nil {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)!
            next.board[capturedSquare.index] = nil
        }
        next.board[move.to.index] = Piece(piece.side, move.promotion ?? piece.kind)
        if piece.kind == .king {
            if piece.side == .white { next.whiteKing = move.to } else { next.blackKing = move.to }
            next.castling.revoke(for: piece.side)
            if isCastle(move) {
                let kingside = move.to.file > move.from.file
                let rookFrom = Square(file: kingside ? 7 : 0, rank: move.from.rank)!
                let rookTo = Square(file: kingside ? 5 : 3, rank: move.from.rank)!
                next.board[rookTo.index] = next.board[rookFrom.index]
                next.board[rookFrom.index] = nil
            }
        }
        if piece.kind == .rook { next.castling.revokeRook(at: move.from, side: piece.side) }
        if let capture, capture.kind == .rook {
            next.castling.revokeRook(at: move.to, side: capture.side)
        }
        next.enPassant = nil
        if piece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassant = move.from.offset(file: 0, rank: piece.side.pawnStep)
        }
        next.halfmoveClock = piece.kind == .pawn || capture != nil ? 0 : halfmoveClock + 1
        next.turn = turn.opponent
        return next
    }

    var hasInsufficientMaterial: Bool {
        let material = Square.all.compactMap { square -> (PieceKind, Square)? in
            guard let piece = self[square], piece.kind != .king else { return nil }
            return (piece.kind, square)
        }
        guard let first = material.first else { return true }
        if material.count == 1 { return first.0 == .bishop || first.0 == .knight }
        return material.allSatisfy { kind, square in kind == .bishop && square.isLight == first.1.isLight }
    }

    private func appendMoves(for piece: Piece, at from: Square, to moves: inout [Move]) {
        switch piece.kind {
        case .pawn:
            appendPawnMoves(from: from, side: piece.side, to: &moves)
        case .knight:
            appendSteps(Self.knightSteps, from: from, to: &moves)
        case .bishop:
            appendRays(Self.diagonals, from: from, to: &moves)
        case .rook:
            appendRays(Self.straights, from: from, to: &moves)
        case .queen:
            appendRays(Self.adjacent, from: from, to: &moves)
        case .king:
            appendSteps(Self.adjacent, from: from, to: &moves)
            appendCastles(from: from, side: piece.side, to: &moves)
        }
    }

    private func appendSteps(_ steps: [(Int, Int)], from: Square, to moves: inout [Move]) {
        for (file, rank) in steps {
            guard let target = from.offset(file: file, rank: rank), self[target]?.side != turn else { continue }
            if self[target]?.kind != .king { moves.append(Move(from: from, to: target)) }
        }
    }

    private func appendRays(_ directions: [(Int, Int)], from: Square, to moves: inout [Move]) {
        for (file, rank) in directions {
            var next = from.offset(file: file, rank: rank)
            while let target = next {
                if let occupant = self[target] {
                    if occupant.side != turn && occupant.kind != .king {
                        moves.append(Move(from: from, to: target))
                    }
                    break
                }
                moves.append(Move(from: from, to: target))
                next = target.offset(file: file, rank: rank)
            }
        }
    }

    private func appendPawnMoves(from: Square, side: Side, to moves: inout [Move]) {
        func add(_ target: Square) {
            if target.rank == side.opponent.homeRank {
                for kind in PieceKind.promotions {
                    moves.append(Move(from: from, to: target, promotion: kind))
                }
            } else {
                moves.append(Move(from: from, to: target))
            }
        }

        let step = side.pawnStep
        if let one = from.offset(file: 0, rank: step), self[one] == nil {
            add(one)
            if from.rank == side.homeRank + step,
               let two = from.offset(file: 0, rank: step * 2), self[two] == nil {
                add(two)
            }
        }
        for file in [-1, 1] {
            guard let target = from.offset(file: file, rank: step) else { continue }
            if let occupant = self[target] {
                if occupant.side != side && occupant.kind != .king { add(target) }
            } else if target == enPassant,
                      let beside = from.offset(file: file, rank: 0),
                      self[beside] == Piece(side.opponent, .pawn) {
                add(target)
            }
        }
    }

    private func appendCastles(from: Square, side: Side, to moves: inout [Move]) {
        guard from.file == 4, from.rank == side.homeRank,
              !castling.isEmpty, !isInCheck(side) else { return }
        for kingside in [true, false] where castling.contains(.right(for: side, kingside: kingside)) {
            let rook = Square(file: kingside ? 7 : 0, rank: side.homeRank)!
            let between = kingside ? [5, 6] : [1, 2, 3]
            let middle = Square(file: kingside ? 5 : 3, rank: side.homeRank)!
            let destination = Square(file: kingside ? 6 : 2, rank: side.homeRank)!
            guard self[rook] == Piece(side, .rook),
                  between.allSatisfy({ self[Square(file: $0, rank: side.homeRank)!] == nil }),
                  !applying(Move(from: from, to: middle)).isInCheck(side) else { continue }
            moves.append(Move(from: from, to: destination))
        }
    }
}
