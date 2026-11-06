#if os(iOS)
import Combine
import XCTest
@testable import SprintQA
@testable import SprintQACore

@MainActor
final class StyleTests: XCTestCase {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func rgba(_ c: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 255).rounded() }
    }

    func testSprintTokensFollowTheDevice() {
        let p = Palette(style: SprintQAStyle(), appearance: nil)
        XCTAssertNotEqual(rgba(p.uiColor(.background), light), rgba(p.uiColor(.background), dark))
    }

    func testCodeWinsOverTheProject() throws {
        let appearance = try JSONDecoder().decode(WidgetAppearance.self, from: Data(#"""
        {"theme":"auto","radius":{"sm":6,"md":10,"lg":14},"tokens":{"light":{"signal":"216 83% 52%"},"dark":{"signal":"216 83% 60%"}},
         "logoUrl":null,"bubble":{"icon":"bug","size":48,"side":"right","label":null},"hiddenRoutes":["Admin"],"copy":{"title":"Atlas"}}
        """#.utf8))
        let style = SprintQAStyle()
        XCTAssertEqual(Palette(style: style, appearance: appearance).radius.medium, 10)
        style.colors[.signal] = .systemPink
        style.radius = .init(small: 2, medium: 3, large: 4)
        style.title = "Report"
        let p = Palette(style: style, appearance: appearance)
        XCTAssertEqual(rgba(p.uiColor(.signal), light), rgba(.systemPink, light))
        XCTAssertEqual(p.radius.medium, 3)
        XCTAssertEqual(p.strings.own(.title), "Report")
        XCTAssertTrue(p.hidden(on: "Admin"))
    }

    func testDynamicColorsStayDynamic() {
        let style = SprintQAStyle()
        style.colors[.primary] = .sprintQA(light: .black, dark: .white)
        let p = Palette(style: style, appearance: nil)
        XCTAssertEqual(rgba(p.uiColor(.primary), light), [0, 0, 0, 255])
        XCTAssertEqual(rgba(p.uiColor(.primary), dark), [255, 255, 255, 255])
    }

    func testAccentFillsItsFamilyWithReadableText() {
        let style = SprintQAStyle()
        style.accent = UIColor(sprintQAHex: "#1F6FEB")
        let p = Palette(style: style, appearance: nil)
        XCTAssertEqual(rgba(p.uiColor(.ring), light), [31, 111, 235, 255])
        XCTAssertEqual(rgba(p.uiColor(.signalForeground), light), [255, 255, 255, 255])
        XCTAssertEqual(rgba(p.bubbleBackground, light), [31, 111, 235, 255])
        // The palette reads the live style: a later change shows up without rebuilding it.
        style.accent = UIColor(sprintQAHex: "#FFD60A")
        XCTAssertEqual(rgba(p.uiColor(.signalForeground), light), [0, 0, 0, 255])
        XCTAssertEqual(rgba(p.bubbleBackground, light), [255, 214, 10, 255])
    }

    func testHexParsing() {
        XCTAssertNotNil(UIColor(sprintQAHex: "#16E"))
        XCTAssertNotNil(UIColor(sprintQAHex: "1F6FEBCC"))
        XCTAssertNil(UIColor(sprintQAHex: "blue"))
    }

    func testBubbleIconDefaultsAndOverrides() {
        let style = SprintQAStyle()
        XCTAssertEqual(Palette(style: style, appearance: nil).bubbleIcon, .symbol("exclamationmark.bubble.fill"))
        style.bubble.icon = .url(URL(string: "https://example.com/logo.png")!)
        XCTAssertEqual(Palette(style: style, appearance: nil).bubbleIcon, .url(URL(string: "https://example.com/logo.png")!))
        style.bubble.size = 20
        XCTAssertEqual(Palette(style: style, appearance: nil).bubbleSize, 44)
    }

    func testChangesPublishSoOpenScreensRedraw() {
        let style = SprintQAStyle()
        var changes = 0
        let sub = style.objectWillChange.sink { changes += 1 }
        style.accent = .systemGreen
        style.bubble.label = "Feedback"
        XCTAssertEqual(changes, 2)
        sub.cancel()
    }
}
#endif
