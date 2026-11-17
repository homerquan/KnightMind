#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SFSession SFSession;

// networkPath is the absolute path to Stockfish's bundled default .nnue file.
SFSession* sf_session_create(const char* networkPath);
void sf_session_destroy(SFSession* session);

// All calls for a session use one serial queue. result has room for six bytes.
bool sf_session_search(SFSession* session, const char* moves, int skill,
                       int milliseconds, char result[6]);

#ifdef __cplusplus
}
#endif
