import ChessCore
import Foundation
import StockfishBridge
import os

enum Difficulty: String, CaseIterable, Codable {
    case casual = "Casual"
    case club = "Club"
    case expert = "Expert"

    var detail: String {
        switch self {
        case .casual: "A forgiving game while you learn."
        case .club: "A balanced game with a tactical challenge."
        case .expert: "Full Stockfish skill with a longer search."
        }
    }

    var search: (skill: Int32, milliseconds: Int32) {
        switch self {
        case .casual: (0, 240)
        case .club: (8, 440)
        case .expert: (20, 820)
        }
    }
}

/// The queue owns the native session. Stockfish's blocking wait stays off Swift's task executor.
final class Opponent: @unchecked Sendable {
    private let queue = DispatchQueue(label: "chessroom.stockfish", qos: .userInitiated)
    private var session: OpaquePointer?

    deinit {
        if let session { sf_session_destroy(session) }
    }

    func warmUp() {
        queue.async { [self] in _ = prepare() }
    }

    func move(in game: Game, difficulty: Difficulty, coaching: Bool = false) async -> Move? {
        let history = game.history.map(\.move.uci).joined(separator: " ")
        let configuration = coaching ? (skill: Int32(20), milliseconds: Int32(300)) : difficulty.search
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard !cancelled.withLock({ $0 }), let session = prepare() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    var output = [CChar](repeating: 0, count: 6)
                    guard sf_session_search(session, history, configuration.skill, configuration.milliseconds, &output),
                          !cancelled.withLock({ $0 }) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let notation = String(decoding: output.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
                    continuation.resume(returning: game.legalMoves.first { $0.uci == notation })
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    private func prepare() -> OpaquePointer? {
        if let session { return session }
        guard let url = Bundle.main.url(forResource: "nn-1a298aa575a0", withExtension: "nnue") else { return nil }
        session = url.withUnsafeFileSystemRepresentation { sf_session_create($0) }
        return session
    }
}
