import XCTest

@MainActor
final class PublicFixtureNavigationTests: XCTestCase {
    func testNativeNavigationAndBackWithPublicFixtures() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FINANCIAL_TRACKER_BASE_URL"] = "http://127.0.0.1:3301"
        app.launch()

        let researchLink = app.webViews.links["Open sandbox fixture"]
        XCTAssertTrue(researchLink.waitForExistence(timeout: 20), "Public research fixture must load")
        XCTAssertTrue(app.navigationBars["Research fixture"].exists)

        app.webViews.links["Blocked external fixture"].tap()
        XCTAssertTrue(researchLink.exists, "External navigation must remain blocked")

        researchLink.tap()
        let sandboxNavigationBar = app.navigationBars["Sandbox fixture"]
        XCTAssertTrue(sandboxNavigationBar.waitForExistence(timeout: 10), "Sandbox must be a native navigation screen")
        XCTAssertTrue(app.webViews.staticTexts["Public synthetic sandbox fixture. No accounts exist."].exists)

        sandboxNavigationBar.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(researchLink.waitForExistence(timeout: 10), "Native back must return to the research fixture")
        XCTAssertTrue(app.navigationBars["Research fixture"].exists)
        app.terminate()
    }
}
