import XCTest

final class PairingButtonsTests: XCTestCase {
    @MainActor
    func testRememberAndForgetAreIndependentListActions() {
        let app = XCUIApplication()
        app.launch()
        let remember = app.buttons["pairing.remember"]
        let forget = app.buttons["pairing.forget"]
        XCTAssertTrue(remember.waitForExistence(timeout: 10))
        XCTAssertTrue(forget.exists)
        // Remove any pairing left by a prior simulator run. Never connect/capture.
        forget.tap()
        defer {
            app.terminate()
            app.launch()
            let cleanup = app.buttons["pairing.forget"]
            if cleanup.waitForExistence(timeout: 5), cleanup.isHittable { cleanup.tap() }
            app.terminate()
        }
        let link = "covoo://pair?host=127.0.0.1&port=43110&fp=\(String(repeating: "01", count: 32))&token=\(String(repeating: "02", count: 32))"
        let field = app.secureTextFields["pairing.link"]
        field.tap()
        field.typeText(link + "\n")
        remember.tap()
        // If tapping Remember also fires Forget, nothing survives app restart.
        app.terminate()
        app.launch()
        let status = app.staticTexts["receiver.status"]
        for _ in 0..<4 where !status.exists { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Saved pairing loaded."), status.label)
        app.swipeDown()
        app.buttons["pairing.forget"].tap()
        app.terminate()
        app.launch()
        let finalStatus = app.staticTexts["receiver.status"]
        for _ in 0..<4 where !finalStatus.exists { app.swipeUp() }
        XCTAssertTrue(finalStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(finalStatus.label, "Disconnected")
    }
}
