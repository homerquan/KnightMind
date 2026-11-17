#include "StockfishBridge.h"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <memory>
#include <sstream>

#include "Vendor/Stockfish/src/attacks.h"
#include "Vendor/Stockfish/src/engine.h"
#include "Vendor/Stockfish/src/misc.h"
#include "Vendor/Stockfish/src/tune.h"
#include "Vendor/Stockfish/src/uci.h"

struct SFSession {
    explicit SFSession(const std::filesystem::path& path) : engine(path) {}

    std::string bestMove;
    Stockfish::Engine engine;
};

SFSession* sf_session_create(const char* networkPath) {
    if (!networkPath) return nullptr;

    static const bool initialized = [] {
        Stockfish::Attacks::init();
        Stockfish::Position::init();
        return true;
    }();
    (void) initialized;

    try {
        auto session = std::make_unique<SFSession>(std::filesystem::path(networkPath));
        if (!session->engine.has_loaded_default_network()) return nullptr;

        auto& engine = session->engine;
        Stockfish::Tune::init(engine.get_options());
        engine.set_on_start([] {});
        engine.set_on_iter([](const auto&) {});
        engine.set_on_update_no_moves([](const auto&) {});
        engine.set_on_update_full([](const auto&) {});
        engine.set_on_verify_network([](std::string_view) {});
        engine.set_on_bestmove([state = session.get()](std::string_view move, std::string_view) {
            state->bestMove = move;
        });
        return session.release();
    } catch (...) {
        return nullptr;
    }
}

void sf_session_destroy(SFSession* session) {
    delete session;
}

bool sf_session_search(SFSession* session, const char* moves, int skill,
                       int milliseconds, char result[6]) {
    if (!session || !result || !moves || milliseconds < 1) return false;
    result[0] = '\0';

    try {
        std::istringstream notation(moves);
        std::vector<std::string> history;
        for (std::string move; notation >> move;) history.push_back(std::move(move));

        auto& engine = session->engine;
        if (engine.set_position(Stockfish::StartFEN, history)) return false;
        session->bestMove.clear();

        std::istringstream option("name Skill Level value " + std::to_string(std::clamp(skill, 0, 20)));
        engine.get_options().setoption(option);
        Stockfish::Search::LimitsType limit;
        limit.movetime = milliseconds;
        limit.startTime = Stockfish::now();
        engine.go(limit);
        engine.wait_for_search_finished();

        const auto& best = session->bestMove;
        if (best.size() != 4 && best.size() != 5) return false;
        std::memcpy(result, best.c_str(), best.size() + 1);
        return true;
    } catch (...) {
        return false;
    }
}
