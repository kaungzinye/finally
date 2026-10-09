import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchOpensProviderChooser() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose where your tasks live."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["connect-notion-provider"].exists)
        XCTAssertTrue(app.buttons["connect-server-provider"].exists)
        app.buttons["connect-server-provider"].tap()
        XCTAssertTrue(app.navigationBars["Connect Server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["server-connect-action"].exists)
    }

    func testDailyFocusLaunchOpensEveryTabAndTaskCreator() {
        let app = XCUIApplication()
        app.launchArguments = ["-daily-focus-demo"]
        app.launch()

        XCTAssertTrue(app.buttons["daily-focus-confirm"].waitForExistence(timeout: 15))
        for (tab, title) in [("Upcoming", "Upcoming"), ("Board", "Board"), ("Browse", "Browse"), ("Today", "Daily Focus")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Add a task"].exists)
        }
        app.buttons["Add a task"].tap()
        XCTAssertTrue(app.textFields["Add a task..."].waitForExistence(timeout: 5))
    }
}
