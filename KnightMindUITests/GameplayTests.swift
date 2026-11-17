import XCTest

final class GameplayTests: XCTestCase {
    @MainActor
    func testPlayWithAutomaticCommentaryAndSettings() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["KNIGHTMIND_UI_TEST_SUITE"] = "KnightMindUITests.\(UUID().uuidString)"
        app.launchEnvironment["KNIGHTMIND_UI_TEST_OFFLINE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["KnightMind"].exists)
        XCTAssertFalse(app.buttons["2D"].exists, "Board configuration belongs in Settings")
        XCTAssertFalse(app.textFields["chess-chat-input"].exists)

        let board = app.descendants(matching: .any)["perspective-board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(board.frame.width, app.frame.width * 0.95)
        XCTAssertGreaterThan(board.frame.height, app.frame.height * 0.55)
        attachScreenshot("Full-size 3D board")
        // Tap the visible e2 pawn and the e4 square in the new camera framing.
        let aspect = board.frame.width / board.frame.height
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5535, dy: 0.5 + 0.1951 * aspect)).tap()
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5502, dy: 0.5 + 0.0223 * aspect)).tap()

        app.buttons["Game actions"].tap()
        app.buttons["Moves"].tap()
        let firstTurn = app.descendants(matching: .any)["turn-1"].firstMatch
        XCTAssertTrue(firstTurn.waitForExistence(timeout: 5))
        XCTAssertTrue(firstTurn.label.contains("e4"))
        XCTAssertFalse(firstTurn.label.contains("—"))
        app.buttons["Close"].tap()

        app.buttons["Settings"].tap()
        app.buttons["2D"].tap()
        app.buttons["Teach"].tap()
        app.buttons["Casual"].tap()
        XCTAssertTrue(app.staticTexts["A forgiving game while you learn."].exists)
        let speech = app.switches["Spoken commentary"]
        if !speech.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertEqual(speech.value as? String, "1", "A fresh game speaks automatically")
        attachScreenshot("All configuration in Settings")
        app.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["e4"].label.contains("White pawn"))
        let status = app.descendants(matching: .any)["turn-status"].firstMatch
        XCTAssertTrue(status.label.contains("Your move"))
        app.buttons["g1"].tap()
        XCTAssertTrue(app.buttons["f3"].label.contains("legal destination"))
        app.buttons["f3"].tap()
        XCTAssertTrue(app.buttons["f3"].label.contains("White knight"))

        // No conversation, hint button, or typed message triggers this lesson.
        let commentary = app.buttons["rook-commentary"]
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Speaking"),
                                                 object: commentary)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 15), .completed,
                       "Bundled KittenTTS speaks after Stockfish's reply while HTTP and HTTPS are blocked")
        XCTAssertFalse(commentary.label.contains("?"))
        attachScreenshot("Automatic coaching on the board")
        commentary.tap()
        let hint = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Stockfish suggests")
        ).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 12), "Teach mode offers a Stockfish reply automatically")
        XCTAssertEqual(app.textFields.count, 0, "Notes are a listening journal")
        attachScreenshot("Rook's quiet notes")

        app.buttons["Rules"].tap()
        app.buttons["En passant"].tap()
        let rule = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "as if it moved just one square")
        ).firstMatch
        XCTAssertTrue(rule.waitForExistence(timeout: 12))
        app.buttons["Close"].tap()
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["g1"].label.contains("White knight"))

        app.buttons["Settings"].tap()
        if !speech.isHittable { app.scrollViews.firstMatch.swipeUp() }
        speech.tap()
        XCTAssertEqual(speech.value as? String, "0")
        app.buttons["Close"].tap()
        XCTAssertNotEqual(commentary.value as? String, "Speaking")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["e4"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["e4"].label.contains("White pawn"))
        app.buttons["Settings"].tap()
        if !speech.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertEqual(speech.value as? String, "0", "An explicit mute survives relaunch")
        app.buttons["Close"].tap()
        attachScreenshot("Full-size overhead board")

        app.buttons["Game actions"].tap()
        app.buttons["New game"].tap()
        let startOver = app.alerts["Start a new game?"].buttons["New game"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 3))
        startOver.tap()
        XCTAssertTrue(app.buttons["e2"].label.contains("White pawn"))
    }

    @MainActor
    func testBoardAdaptsToLandscape() {
        let app = XCUIApplication()
        app.launchEnvironment["KNIGHTMIND_UI_TEST_SUITE"] = "KnightMindLayout.\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let board = app.descendants(matching: .any)["perspective-board"].firstMatch
        let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wide], timeout: 5), .completed)
        XCTAssertGreaterThan(board.frame.height, app.frame.height * 0.85)
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        XCTAssertTrue(app.buttons["rook-commentary"].isHittable)
        attachScreenshot("Board and calm controls in landscape")
        app.buttons["Settings"].tap()
        app.buttons["2D"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["a8"].isHittable)
        XCTAssertTrue(app.buttons["h1"].isHittable)
        app.buttons["e2"].tap()
        app.buttons["e4"].tap()
        XCTAssertTrue(app.buttons["e4"].label.contains("White pawn"))
        attachScreenshot("Overhead board in landscape")
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
