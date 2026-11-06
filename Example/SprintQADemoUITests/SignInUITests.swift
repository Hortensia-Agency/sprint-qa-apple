import XCTest

// Signs in through the real ASWebAuthenticationSession against a Sprint dev
// server, with the seeded password account. Needs, from the environment
// (TEST_RUNNER_ prefixed on the xcodebuild line): SPRINT_QA_KEY, SPRINT_EMAIL,
// SPRINT_PASSWORD; the key's project must list sprintqademo:// in its QA URLs.
final class SignInUITests: XCTestCase {
    func testSignInWithSprint() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["SPRINT_QA_KEY"], let email = env["SPRINT_EMAIL"], let password = env["SPRINT_PASSWORD"] else {
            throw XCTSkip("set SPRINT_QA_KEY, SPRINT_EMAIL and SPRINT_PASSWORD")
        }
        let app = XCUIApplication()
        app.launchEnvironment["SPRINT_QA_KEY"] = key
        app.launchArguments = ["-reset"]
        app.launch()
        XCTAssertEqual(app.staticTexts["status"].label, "Signed out")

        app.buttons["Sign in with Sprint"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let proceed = springboard.buttons["Continue"]
        if proceed.waitForExistence(timeout: 10) { proceed.tap() }

        let web = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let emailField = web.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 30), "Sprint's sign-in page didn't load")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = web.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        web.buttons["Sign in"].tap()

        let signedIn = app.staticTexts["Signed in"]
        XCTAssertTrue(signedIn.waitForExistence(timeout: 30), "status: \(app.staticTexts["status"].label)")
    }
}
