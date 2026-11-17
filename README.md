# KnightMind

KnightMind is a native SwiftUI game for iPhone and iPad. Open `KnightMind.xcodeproj`, select the **KnightMind** scheme and an iOS simulator, and press Run. Use Xcode with the iOS 26 SDK or later. The app runs on iOS 18 and later. Apple Intelligence conversation requires iOS 26 or later and a compatible device with the on-device model available.

You play White. Tap a piece to see its legal destinations, then tap a square to move. The board fills the available width in portrait and adapts to landscape on iPhone and iPad. The 3D camera fits the whole tabletop to the available space. Settings contains the 3D/2D view, Casual/Club/Expert Stockfish difficulty, Play/Teach mode, and spoken commentary. Undo and a small game menu sit below the board. After checkmate or a draw, a visible **New game** button starts a fresh match in one tap. KnightMind saves the current game locally. It automatically declares draws at threefold repetition or after 50 moves by each side without a pawn move or capture.

Stockfish searches locally for Black's moves and for suggested replies. Rook welcomes the player and speaks automatically after the computer's move. Play mode gives a brief reaction. Teach mode connects a detail from the board to a practical chess habit and explains a verified Stockfish reply. The on-device Foundation Models framework uses built-in guidance on openings, tactics, king safety, and endgames to tell the lesson in Rook's voice. Local coaching also works on devices without Apple Intelligence. Moving a piece cancels outdated commentary, and leaving the app stops speech.

Spoken commentary is enabled for a new installation. Turn it off in Settings for a quiet game. Rook speaks with [KittenTTS by KittenML](https://github.com/KittenML/KittenTTS-swift), using Jasper's English voice and the Nano fp32 model at a fixed 1× speed. There are no voice, model, or speed settings. All model, voice, and pronunciation assets (about 60 MB) are included in the app, so speech works offline from the first launch with no post-install download. Preparing a voice never blocks the board, and canceled or outdated speech cannot start playing later. If voice setup fails, captions remain available and the next spoken note retries. A small caption shows the latest note. Tap it to read Rook's notes or choose an optional hint, move explanation, or rule. There is no chat composer or microphone, and the game never expects a spoken or typed reply.

Run the rules and Stockfish tests with `swift test` from this directory. Use **Product > Test** in Xcode on an iPhone or iPad simulator to verify gameplay, automatic spoken teaching, Settings, saved voice preferences, and portrait/landscape layout.

## App description

Settle into KnightMind for a game on a handcrafted wooden board that fills your screen. Play in 3D or switch to a clear top-down view in Settings. Pick your difficulty, then enjoy a relaxed match or listen to move explanations in Teach mode. Rook speaks as you play, with no need to answer. Its voice is included and works offline from your first game. Follow along in quiet captions or mute the voice in Settings. On supported devices, Apple Intelligence powers the conversation on device.

KnightMind is free software under the **GNU General Public License v3**. Computer moves and hints are powered by **Stockfish 19**, by the Stockfish developers. Rook's voice is powered by **KittenTTS**, by **KittenML**, with English pronunciation data from **eSpeak NG**. The KittenTTS SDK and Nano model use Apache 2.0; the pronunciation data uses GPL v3 or later. Full credits and license texts are available in Settings → About KnightMind → Open-source licenses.

## License and speech dependencies

KnightMind's own code is licensed under GPL-3.0-only; see [LICENSE](LICENSE). Third-party components retain their original licenses. [Bundled credits](KnightMind/Resources/ThirdParty-NOTICES.txt) identify the authors, licenses, and upstream source locations.

The Xcode project pins KittenTTS Swift SDK to revision `20cd4d8784c1bad348326955709892c8dfe7226b`. `Package.resolved` also locks ONNX Runtime. `VoiceData/kittentts` is copied into the app as a folder resource. It includes the default [Nano 0.8 fp32 model and voice embeddings](https://huggingface.co/KittenML/kitten-tts-nano-0.8-fp32/tree/e73cfb095bd949c786ccdcf3b8ab04eb36c47442) plus the GPLv3-or-later `en_rules` and `en_list` pronunciation source files from eSpeak NG revision `59eb19938f12e30881c81d86ce4a7de25414c9f4`. File checksums are recorded in [VoiceData/SHA256SUMS](VoiceData/SHA256SUMS). KittenTTS loads every asset directly from the bundle; a missing asset fails without attempting a network download. Speech uses only KittenTTS; playback uses AVAudioPlayer so stopping a note also discards any audio still being generated.

## Stockfish source

The Xcode project builds Stockfish 19 (tag `sf_19`) from `Sources/StockfishBridge/Vendor/Stockfish`. The integration adds a network-load check in `src/engine.h`, a C bridge, and Apple-target build configuration. The app bundle includes the upstream license and author list.

`EngineData/nn-1a298aa575a0.nnue` is the exact default evaluation network. Its SHA-256 is `1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2`. [Upstream network](https://tests.stockfishchess.org/api/nn/nn-1a298aa575a0.nnue)

The Stockfish project requires distributors to provide the corresponding source code and GPL license with binaries. This workspace contains the vendored source, integration changes, network, and build files. [Stockfish license and distribution terms](https://github.com/official-stockfish/Stockfish/tree/sf_19#terms-of-use)
