import XCTest
@testable import SprintQACore

final class BubbleLayoutTests: XCTestCase {
    let layout = BubbleLayout(width: 393, height: 852, insets: (59, 0, 34, 0), size: 56)

    func testRestsAgainstAnEdgeInsideTheSafeArea() {
        XCTAssertEqual(layout.rest(side: 1, fraction: 1), .init(x: 393 - 12 - 56, y: 852 - 34 - 12 - 56))
        XCTAssertEqual(layout.rest(side: 0, fraction: 0), .init(x: 12, y: 59 + 12))
        let p = layout.rest(side: 0, fraction: 0.4)
        XCTAssertEqual(layout.stored(p).side, 0)
        XCTAssertEqual(layout.stored(p).fraction, 0.4, accuracy: 1e-9)
    }

    func testAFlickCarriesItToTheFarEdge() {
        let start = BubbleLayout.Point(x: 120, y: 400)
        XCTAssertEqual(layout.snap(from: start, velocity: .init(x: 0, y: 0)).x, layout.leftX)
        XCTAssertEqual(layout.snap(from: start, velocity: .init(x: 900, y: 0)).x, layout.rightX)
    }

    func testProjectionIsClampedVertically() {
        XCTAssertEqual(layout.snap(from: .init(x: 300, y: 700), velocity: .init(x: 0, y: 5000)).y, layout.maxY)
        XCTAssertEqual(layout.snap(from: .init(x: 300, y: 100), velocity: .init(x: 0, y: -5000)).y, layout.minY)
    }

    func testDragResistsPastTheEdges() {
        let past = layout.clampDrag(.init(x: -100, y: 400))
        XCTAssertLessThan(past.x, layout.leftX)
        XCTAssertGreaterThan(past.x, -100)
        XCTAssertEqual(layout.clampDrag(.init(x: 200, y: 400)), .init(x: 200, y: 400))
    }
}
