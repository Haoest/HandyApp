import XCTest

final class HandyApp3UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    /// End-to-end: create an Appliance asset named "test appliance", add a $100 expense
    /// transaction to it, and add a "warranty expire" event dated one year from today.
    @MainActor
    func testCreateApplianceWithTransactionAndEvent() throws {
        let app = XCUIApplication()

        // Notification permission dialogs can appear the first time the app runs on a device;
        // auto-dismiss them so they don't block the flow below.
        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        app.tap() // gives the interruption monitor a chance to run

        // MARK: Start a new asset from the Assets tab.
        let assetsTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(assetsTab.waitForExistence(timeout: 5))
        assetsTab.tap()

        let newAssetButton = app.buttons["newAssetButton"]
        XCTAssertTrue(newAssetButton.waitForExistence(timeout: 5))
        newAssetButton.tap()

        let applianceButton = app.buttons["Appliance"]
        XCTAssertTrue(applianceButton.waitForExistence(timeout: 5))
        applianceButton.tap()

        // MARK: Fill out the "New Appliance" form — required Type, then Name.
        let typeField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(typeField.waitForExistence(timeout: 5))
        typeField.tap()
        typeField.typeText("Refrig")
        let refrigeratorSuggestion = app.staticTexts["Refrigerator"]
        XCTAssertTrue(refrigeratorSuggestion.waitForExistence(timeout: 5))
        refrigeratorSuggestion.tap()

        let nameField = app.textFields["Asset name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.clearAndTypeText("test appliance")

        app.navigationBars.buttons["Save"].tap()

        let detailNavBar = app.navigationBars["test appliance"]
        XCTAssertTrue(detailNavBar.waitForExistence(timeout: 5))

        // MARK: Add a $100 expense transaction.
        app.buttons["addMenuButton"].tap()
        app.buttons["Transaction"].tap()

        let descriptionField = app.textFields["Description"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5))
        descriptionField.tap()
        descriptionField.typeText("Test expense")

        let amountField = app.textFields["0.00"]
        amountField.tap()
        amountField.typeText("100")

        // Expense is already the default Type, but select it explicitly to be safe.
        let expenseSegment = app.segmentedControls.buttons["Expense"]
        if expenseSegment.exists { expenseSegment.tap() }

        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(detailNavBar.waitForExistence(timeout: 5))

        // MARK: Add a "warranty expire" event dated one year from today.
        app.buttons["addMenuButton"].tap()
        app.buttons["Event"].tap()

        let titleField = app.textFields["Event title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("warranty expire")

        let datePickerField = app.datePickers.firstMatch
        XCTAssertTrue(datePickerField.waitForExistence(timeout: 5))
        datePickerField.tap()

        let nextMonthButton = app.buttons["Next Month"]
        XCTAssertTrue(nextMonthButton.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            nextMonthButton.tap()
        }

        let targetDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        let targetDayLabel = formatter.string(from: targetDate)
        let dayButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", targetDayLabel)).firstMatch
        XCTAssertTrue(dayButton.waitForExistence(timeout: 5))
        dayButton.tap()

        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(detailNavBar.waitForExistence(timeout: 5))

        // MARK: Verify both entries landed on the asset.
        scrollToElement(app.staticTexts["warranty expire"], in: app)
        XCTAssertTrue(app.staticTexts["warranty expire"].exists)

        scrollToElement(app.staticTexts["Test expense"], in: app)
        XCTAssertTrue(app.staticTexts["Test expense"].exists)
    }

    /// Swipes the screen up until `element` exists (SwiftUI List rows off-screen aren't
    /// part of the accessibility tree until scrolled into view) or `maxSwipes` is reached.
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) {
        var attempts = 0
        while !element.exists, attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }
}

private extension XCUIElement {
    /// Replaces this text field's current contents with `text`. Assumes tapping places
    /// the caret at the end of the existing value, which holds for the short prefilled
    /// strings this test encounters.
    func clearAndTypeText(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            typeText(deleteString)
        }
        typeText(text)
    }
}
