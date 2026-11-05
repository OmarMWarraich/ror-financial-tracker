import XCTest

@MainActor
final class RealRailsSessionTests: XCTestCase {
    func testRealRailsPublicAndProtectedNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FINANCIAL_TRACKER_BASE_URL"] = "http://127.0.0.1:3000"
        app.launch()
        defer { app.terminate() }

        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20), "Protected root must redirect to Rails sign-in")
        XCTAssertTrue(app.webViews.buttons["Log in"].exists)
        print("RAILS_NATIVE_SMOKE: anonymous protected root reached Rails sign-in")

        app.webViews.links["Research policy lab"].firstMatch.tap()
        let demoHeading = app.webViews.staticTexts["Synthetic research policy lab"]
        XCTAssertTrue(demoHeading.waitForExistence(timeout: 15), "Public Rails demo must load")
        print("RAILS_NATIVE_SMOKE: public Rails research demo loaded")

        app.webViews.links["FinanceTracker"].firstMatch.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 15), "Protected root must redirect back to Rails sign-in")
        let password = app.webViews.secureTextFields.firstMatch
        XCTAssertTrue(password.exists)
        password.tap()
        password.typeText("NONSECRET_REDACTION_PROBE")
        print("RAILS_NATIVE_SMOKE: nonsecret input probe completed; no account or form submission")
    }
}
