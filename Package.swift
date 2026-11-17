// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
        .library(name: "StockfishBridge", targets: ["StockfishBridge"])
    ],
    targets: [
        .target(name: "ChessCore"),
        .target(
            name: "StockfishBridge",
            exclude: [
                "Vendor/Stockfish/.github",
                "Vendor/Stockfish/scripts",
                "Vendor/Stockfish/tests",
                "Vendor/Stockfish/src/main.cpp",
                "Vendor/Stockfish/src/universal",
                "Vendor/Stockfish/src/incbin/UNLICENCE",
                "Vendor/Stockfish/src/Makefile"
            ],
            sources: ["StockfishBridge.cpp", "Vendor/Stockfish/src"],
            cxxSettings: [
                .headerSearchPath("."),
                .define("NNUE_EMBEDDING_OFF"),
                .define("IS_64BIT"),
                .define("USE_POPCNT"),
                .define("NDEBUG"),
                .unsafeFlags(["-include", "StockfishBuildConfig.h", "-O3"])
            ]
        ),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore", "StockfishBridge"])
    ],
    cxxLanguageStandard: .cxx20
)
