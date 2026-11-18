import XCTest

final class PairingButtonsTests: XCTestCase {
    @MainActor
    private func setRemember(_ toggle: XCUIElement, to enabled: Bool, app: XCUIApplication) {
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected {
            // SwiftUI exposes the labeled row as the switch element. Target
            // its trailing control instead of the center of the label.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let changed = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: toggle)], timeout: 5)
        let error = app.staticTexts["pairing.saveError"]
        XCTAssertEqual(result, .completed, error.exists ? error.label : app.debugDescription)
    }
    @MainActor
    func testScannerCanBeCancelledWithoutConnecting() {
        let app = XCUIApplication()
        app.launch()
        let scan = app.buttons["pairing.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect"].exists)
        app.terminate()
    }
    @MainActor
    func testRememberTogglePersistsAndRemovalKeepsCurrentLink() {
        let app = XCUIApplication()
        app.launch()
        let remember = app.switches["pairing.remember"]
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
        setRemember(remember, to: true, app: app)
        XCTAssertEqual(remember.value as? String, "1")
        // If tapping Remember also fires Forget, nothing survives app restart.
        app.terminate()
        app.launch()
        let restored = app.switches["pairing.remember"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, "1")
        let status = app.staticTexts["receiver.status"]
        for _ in 0..<4 where !status.exists { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Saved pairing loaded."), status.label)
        app.swipeDown()
        setRemember(restored, to: false, app: app)
        XCTAssertEqual(restored.value as? String, "0")
        XCTAssertFalse((app.secureTextFields["pairing.link"].value as? String ?? "").isEmpty)
        setRemember(restored, to: true, app: app)
        XCTAssertEqual(restored.value as? String, "1")
        app.buttons["pairing.forget"].tap()
        app.terminate()
        app.launch()
        let finalStatus = app.staticTexts["receiver.status"]
        for _ in 0..<4 where !finalStatus.exists { app.swipeUp() }
        XCTAssertTrue(finalStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(finalStatus.label, "Disconnected")
    }
}
