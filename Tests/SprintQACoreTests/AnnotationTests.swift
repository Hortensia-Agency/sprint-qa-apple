import CoreGraphics
import XCTest
@testable import SprintQACore

final class AnnotationTests: XCTestCase {
    private let red = Mark.colors[0]

    func testPaletteMatchesTheWebWidget() {
        XCTAssertEqual(Mark.colors.count, 9)
        XCTAssertEqual(Mark.colors.first, RGBA(hex: "#ef4444"))
        XCTAssertEqual(Mark.colors.last, RGBA(hex: "#111827"))
    }

    func testRectIsTheSameWhicheverWayTheDragWent() {
        let a = CGPoint(x: 40, y: 90), b = CGPoint(x: 10, y: 20)
        XCTAssertEqual(AreaSelection.rect(a, b), CGRect(x: 10, y: 20, width: 30, height: 70))
        XCTAssertEqual(AreaSelection.rect(b, a), AreaSelection.rect(a, b))
    }

    func testSmallSelectionsAreNotUsable() {
        XCTAssertFalse(AreaSelection.isUsable(CGRect(x: 0, y: 0, width: 12, height: 200)))
        XCTAssertTrue(AreaSelection.isUsable(CGRect(x: 0, y: 0, width: 13, height: 13)))
    }

    func testCropScalesFromViewToImageAndStaysInside() {
        let crop = AreaSelection.crop(
            CGRect(x: 100, y: 200, width: 400, height: 50),
            view: CGSize(width: 390, height: 844),
            image: CGSize(width: 780, height: 1688)
        )
        XCTAssertEqual(crop, CGRect(x: 200, y: 400, width: 580, height: 100))
    }

    func testPartialCrop() {
        let image = CGSize(width: 390, height: 844)
        XCTAssertFalse(AreaSelection.isPartial(CGRect(origin: .zero, size: image), of: image))
        XCTAssertTrue(AreaSelection.isPartial(CGRect(x: 0, y: 1, width: 390, height: 843), of: image))
    }

    func testTrivialMarks() {
        XCTAssertTrue(Mark(tool: .rect, color: red, size: 3, points: [.zero, CGPoint(x: 3, y: 3)]).isTrivial)
        XCTAssertFalse(Mark(tool: .rect, color: red, size: 3, points: [.zero, CGPoint(x: 30, y: 3)]).isTrivial)
        XCTAssertTrue(Mark(tool: .pen, color: red, size: 3, points: [.zero]).isTrivial)
        XCTAssertTrue(Mark(tool: .text, color: red, size: 18, points: [.zero], text: "  ").isTrivial)
        XCTAssertFalse(Mark(tool: .text, color: red, size: 18, points: [.zero], text: "Wrong price").isTrivial)
    }

    func testArrowHeadSitsBehindTheTip() {
        let m = Mark(tool: .arrow, color: red, size: 3, points: [.zero, CGPoint(x: 100, y: 0)])
        let (p1, p2) = m.arrowHead
        XCTAssertLessThan(p1.x, 100)
        XCTAssertLessThan(p2.x, 100)
        XCTAssertEqual(p1.y, -p2.y, accuracy: 1e-9)
        XCTAssertEqual(hypot(100 - p1.x, p1.y), 16, accuracy: 1e-9)
    }
}
