import XCTest
@testable import SprintQACore

private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: repo.appendingPathComponent("Tests/SprintQACoreTests/Fixtures/\(name).json"))
}

final class ContractTests: XCTestCase {
    // Captured from a Sprint dev server, so the shapes are the server's own.
    func testDecodesConfig() throws {
        let c = try JSONDecoder().decode(WidgetConfig.self, from: fixture("config"))
        XCTAssertTrue(c.enabled)
        XCTAssertNil(c.projectId)
        XCTAssertNotNil(c.appearance?.bubble)
    }

    func testDecodesMeAndQueue() throws {
        let me = try JSONDecoder().decode(WidgetMe.self, from: fixture("me"))
        XCTAssertEqual(me.captureProfile, .standard)
        let q = try JSONDecoder().decode(QueueResponse.self, from: fixture("queue"))
        XCTAssertFalse(q.tasks.isEmpty)
    }

    func testReportLeavesUnsetFieldsOut() throws {
        let json = String(data: try JSONEncoder().encode(ReportInput(title: "Crash")), encoding: .utf8)!
        XCTAssertEqual(json, #"{"title":"Crash"}"#)
    }
}

final class SignInTests: XCTestCase {
    // Computed with Node's createHash("sha256").digest("base64url"), which is
    // Sprint's pkceChallengeFor.
    func testChallengeMatchesSprint() {
        XCTAssertEqual(PKCE(verifier: "dBjftJeZ4CVP-mJ92K9qPvgsoHHhD0QTkgqfvJzFELY").challenge, "gfzuyRVJQvw2A9Qoy59jbZT7wANGRORUVmnGvUZcN6Y")
    }

    func testFreshVerifiersAreUnique() {
        let a = PKCE(), b = PKCE()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertEqual(a.verifier.count, 43)
    }

    func testStartURLEscapesEveryValue() {
        let url = SignIn.startURL(origin: URL(string: "https://sprint.test")!, widgetKey: "pk_qa_a+b", redirect: "tapinn://sprint-qa", deviceId: "ios_1", challenge: "c")
        XCTAssertEqual(url.absoluteString, "https://sprint.test/api/widget/mobile-auth/start?key=pk_qa_a%2Bb&redirect=tapinn://sprint-qa&device=ios_1&challenge=c")
    }

    func testParsesTheRedirect() {
        XCTAssertEqual(SignIn.parse(URL(string: "tapinn://sprint-qa?code=abc%3D")!), .code("abc="))
        XCTAssertEqual(SignIn.parse(URL(string: "tapinn://sprint-qa?error=not_a_qa_member&code=x")!), .error("not_a_qa_member"))
        XCTAssertEqual(SignIn.parse(URL(string: "tapinn://sprint-qa")!), .error("no_code"))
    }

    func testMapsFailuresToText() {
        XCTAssertNil(SignIn.message(for: "cancelled"))
        XCTAssertEqual(SignIn.message(for: "widget_disabled"), .reportingOff)
        XCTAssertEqual(SignIn.message(for: "expired"), .signInIncomplete)
        XCTAssertEqual(SignIn.message(for: "anything"), .signInFailed)
    }
}

final class ConfigTests: XCTestCase {
    func testPatShape() {
        XCTAssertTrue(isPatShape("sprint_pat_" + String(repeating: "a", count: 32)))
        XCTAssertFalse(isPatShape("sprint_pat_short"))
        XCTAssertFalse(isPatShape(nil))
    }

    func testHiddenRoutes() {
        XCTAssertTrue(routeHidden("Checkout", ["Checkout"]))
        XCTAssertTrue(routeHidden("Settings/Billing", ["Settings/*"]))
        XCTAssertFalse(routeHidden("Checkout.v2", ["Checkout"]))
        XCTAssertFalse(routeHidden("a.b", ["a?b"]))
        XCTAssertFalse(routeHidden(nil, ["*"]))
    }
}

final class ThemeTests: XCTestCase {
    func testTokensMatchTheVendoredJSON() throws {
        let json = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: repo.appendingPathComponent("tokens.json")))
        XCTAssertEqual(Tokens.light, json["light"])
        XCTAssertEqual(Tokens.dark, json["dark"])
        XCTAssertEqual(Set(Tokens.light.keys), Set(Tokens.dark.keys))
    }

    func testEveryTokenParses() {
        for (name, value) in Tokens.light.merging(Tokens.dark, uniquingKeysWith: { a, _ in a }) {
            XCTAssertNotNil(RGBA(hsl: value), name)
        }
    }

    func testHSLConversion() {
        XCTAssertEqual(RGBA(hsl: "0 0% 100%"), RGBA(r: 1, g: 1, b: 1))
        XCTAssertEqual(RGBA(hsl: "0 100% 50%"), RGBA(r: 1, g: 0, b: 0))
        XCTAssertEqual(RGBA(hsl: "0 0% 0% / 0.5")?.a, 0.5)
        XCTAssertNil(RGBA(hsl: "nonsense"))
    }

    func testProjectTokensWinAndAccentTheBubble() throws {
        let appearance = try JSONDecoder().decode(WidgetConfig.self, from: fixture("config")).appearance
        let plain = Theme(dark: false, appearance: nil)
        let own = Theme(dark: false, appearance: appearance)
        XCTAssertFalse(plain.accented)
        XCTAssertTrue(own.accented)
        XCTAssertEqual(own["signal"], RGBA(hsl: appearance!.tokens!.light["signal"]!))
        XCTAssertEqual(own["foreground"], plain["foreground"])
        XCTAssertEqual(own.radius.md, 10)
    }

    func testDarkFollowsTheProjectThenTheDevice() {
        XCTAssertTrue(Theme.isDark(mode: "auto", systemDark: true))
        XCTAssertFalse(Theme.isDark(mode: "light", systemDark: true))
        XCTAssertTrue(Theme.isDark(mode: "dark", systemDark: false))
    }
}

final class StringsTests: XCTestCase {
    func testEveryKeyHasADefaultWithoutDashes() {
        for key in StringKey.allCases {
            let s = StringKey.defaults[key]
            XCTAssertNotNil(s, key.rawValue)
            for dash in ["—", "–", " - ", "--"] {
                XCTAssertFalse(s?.contains(dash) ?? false, "\(key.rawValue) uses a dash")
            }
        }
    }

    func testHostThenProjectThenEnglish() {
        let copy = WidgetAppearance.Copy(title: "Atlas", intro: nil, submit: "Send it", thanks: nil)
        let t = Strings(host: ["thanks": "Merci"], copy: copy)
        XCTAssertEqual(t(.thanks), "Merci")
        XCTAssertEqual(t(.submit), "Send it")
        XCTAssertEqual(t(.cancel), "Cancel")
        XCTAssertEqual(t.own(.title), "Atlas")
        XCTAssertNil(t.own(.intro))
    }

    func testFillsSlots() {
        XCTAssertEqual(Strings()(.verifiedCount, ["state": "In review", "count": 1]), "In review, 1 verified")
        XCTAssertEqual(Strings()(.stop, [:]), "Stop {time}")
    }
}

final class StoreTests: XCTestCase {
    func testTokenAndDeviceIdPersist() {
        let defaults = UserDefaults(suiteName: "sprint-qa-tests-\(UUID())")!
        let s = WidgetStorage(secrets: MemoryStore(), defaults: defaults)
        XCTAssertNil(s.pat)
        s.pat = "sprint_pat_x"
        XCTAssertEqual(s.pat, "sprint_pat_x")
        XCTAssertEqual(s.deviceId, s.deviceId)
        XCTAssertTrue(s.deviceId.hasPrefix("ios_"))
        s.bubblePosition = (12, 340)
        XCTAssertEqual(s.bubblePosition?.y, 340)
        s.hidden = true
        XCTAssertTrue(s.hidden)
    }

    func testKeychainRoundTrip() {
        let k = KeychainStore(service: "com.hortensia.sprint-qa.tests")
        k.set("probe", "value")
        XCTAssertEqual(k.get("probe"), "value")
        k.set("probe", nil)
        XCTAssertNil(k.get("probe"))
    }
}
