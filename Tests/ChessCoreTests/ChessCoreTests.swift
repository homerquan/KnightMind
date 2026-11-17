import Foundation
import Testing
import StockfishBridge
@testable import ChessCore

private func square(_ name: String) -> Square { Square(named: name)! }

@discardableResult
private func play(_ notation: String, in game: inout Game) throws -> TurnRecord {
    let move = try #require(game.legalMoves.first { $0.uci == notation })
    let record = game.play(move)
    return try #require(record)
}

private func position(_ pieces: [(String, Piece)], castling: CastlingRights = [], enPassant: String? = nil) -> Position {
    var board = [Piece?](repeating: nil, count: 64)
    for (name, piece) in pieces { board[square(name).index] = piece }
    return Position(board: board, turn: .white, castling: castling, enPassant: enPassant.map(square))
}

@Test func initialMoveTree() {
    func count(_ position: Position, depth: Int) -> Int {
        if depth == 0 { return 1 }
        return position.legalMoves().reduce(0) { $0 + count(position.applying($1), depth: depth - 1) }
    }
    #expect(count(.initial, depth: 3) == 8_902)
}

@Test func castlingMovesTheRookAndRejectsAnAttackedCrossing() throws {
    var game = Game()
    for move in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"] {
        try play(move, in: &game)
    }
    #expect(try play("e1g1", in: &game).notation == "O-O")
    #expect(game.position[square("f1")] == Piece(.white, .rook))
    #expect(game.position[square("h1")] == nil)

    let crossing = position([
        ("e1", Piece(.white, .king)), ("h1", Piece(.white, .rook)),
        ("h8", Piece(.black, .king)), ("a6", Piece(.black, .bishop))
    ], castling: .right(for: .white, kingside: true))
    #expect(!crossing.isInCheck(.white))
    #expect(!crossing.legalMoves().contains { $0.uci == "e1g1" })
}

@Test func enPassantAndKingSafety() throws {
    var game = Game()
    for move in ["e2e4", "a7a5", "e4e5", "d7d5"] {
        try play(move, in: &game)
    }
    let capture = try play("e5d6", in: &game)
    #expect(capture.notation == "exd6")
    #expect(capture.capture == Piece(.black, .pawn))
    #expect(game.position[square("d5")] == nil)

    let pinned = position([
        ("e1", Piece(.white, .king)), ("e5", Piece(.white, .pawn)),
        ("h8", Piece(.black, .king)), ("e8", Piece(.black, .rook)), ("d5", Piece(.black, .pawn))
    ], enPassant: "d6")
    #expect(!pinned.legalMoves().contains { $0.uci == "e5d6" })
}

@Test func promotionOffersUnderpromotionAndUpdatesOutcome() throws {
    var game = Game(position: position([
        ("e1", Piece(.white, .king)), ("a7", Piece(.white, .pawn)), ("h7", Piece(.black, .king))
    ]))
    let options = game.legalMoves.filter { $0.from == square("a7") }.compactMap(\.promotion)
    #expect(Set(options) == Set(PieceKind.promotions))
    #expect(try play("a7a8n", in: &game).notation == "a8=N")
    #expect(game.position[square("a8")] == Piece(.white, .knight))
    #expect(game.outcome == .draw(.insufficientMaterial))
}

@Test func mateRepetitionAndReplay() throws {
    var mate = Game()
    for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { try play(move, in: &mate) }
    #expect(mate.history.last?.notation == "Qh4#")
    #expect(mate.outcome == .checkmate(winner: .black))

    var game = Game()
    for _ in 0..<2 {
        for move in ["g1f3", "g8f6", "f3g1", "f6g8"] { try play(move, in: &game) }
    }
    #expect(game.outcome == .draw(.repetition))
    let replay = try #require(Game(replaying: game.history.map(\.move)))
    #expect(replay.history == game.history)
    #expect(replay.outcome == game.outcome)
    game.undo()
    #expect(game.outcome == .playing)
    try play("f6g8", in: &game)
    #expect(game.outcome == .draw(.repetition))
}

@Test func stockfishUsesTheBundledNetworkAndReturnsLegalMoves() throws {
    let project = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let network = project.appending(path: "EngineData/nn-1a298aa575a0.nnue")
    let session = try #require(network.withUnsafeFileSystemRepresentation { sf_session_create($0) })
    defer { sf_session_destroy(session) }

    var game = Game()
    for move in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"] {
        try play(move, in: &game)
    }
    let history = game.history.map(\.move.uci).joined(separator: " ")
    for skill: Int32 in [0, 8, 20] {
        var output = [CChar](repeating: 0, count: 6)
        #expect(sf_session_search(session, history, skill, 75, &output))
        let move = String(decoding: output.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
        #expect(game.legalMoves.contains { $0.uci == move })
    }
}
