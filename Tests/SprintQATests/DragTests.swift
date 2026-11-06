#if os(iOS)
import SwiftUI
import XCTest
@testable import SprintQA
@testable import SprintQACore

@MainActor
final class DragTests: XCTestCase {
    private func model() -> WidgetModel {
        let defaults = UserDefaults(suiteName: "sprintqa-drag-\(UUID().uuidString)")!
        let m = WidgetModel(
            configuration: .init(widgetKey: "pk_qa_test", enabled: true, redirectScheme: "demo"),
            client: SprintQAClient(widgetKey: "pk_qa_test"),
            storage: WidgetStorage(secrets: MemoryStore(), defaults: defaults),
            style: SprintQAStyle()
        )
        m.updateLayout(size: CGSize(width: 390, height: 844), insets: EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0))
        return m
    }

    func testAFingerMovingPastTheThresholdDragsTheBubble() throws {
        let m = model()
        let rest = try XCTUnwrap(m.position)
        let start = CGPoint(x: rest.x + 20, y: rest.y + 20)
        // Small steps, as a real finger sends them: each is under the threshold.
        for (i, dy) in stride(from: 0.0, through: -120.0, by: -4.0).enumerated() {
            m.dragChanged(location: CGPoint(x: start.x, y: start.y + dy), start: start, time: Double(i) * 0.016)
        }
        XCTAssertTrue(m.dragging)
        let moved = try XCTUnwrap(m.position)
        XCTAssertEqual(moved.y, rest.y - 120, accuracy: 0.5)
        XCTAssertFalse(m.dragEnded(), "a drag is not a tap")
    }

    func testATouchThatBarelyMovesIsATap() {
        let m = model()
        let start = CGPoint(x: (m.position?.x ?? 0) + 20, y: (m.position?.y ?? 0) + 20)
        m.dragChanged(location: start, start: start, time: 0)
        m.dragChanged(location: CGPoint(x: start.x + 3, y: start.y + 2), start: start, time: 0.05)
        XCTAssertFalse(m.dragging)
        XCTAssertTrue(m.dragEnded())
    }
}
#endif
