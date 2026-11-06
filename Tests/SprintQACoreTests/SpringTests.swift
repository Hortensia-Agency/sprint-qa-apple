import XCTest
@testable import SprintQACore

final class SpringTests: XCTestCase {
    // Reference values printed by Sprint's lib/motion/spring.ts stepSpring.
    func testMatchesSprintsSpring() {
        var s = Spring.State(value: 0, velocity: 0)
        var out: [Double] = []
        for _ in 0..<10 {
            s = Spring.step(s, to: 100, dt: 1.0 / 60, dampingRatio: 1, response: 0.4).state
            out.append(s.value)
        }
        let ref = [3.734004, 11.245355, 20.491939, 30.211672, 39.658046, 48.420437, 56.302801, 63.242482, 69.256425, 74.406044]
        for (a, b) in zip(out, ref) { XCTAssertEqual(a, b, accuracy: 1e-5) }

        var f = Spring.State(value: 0, velocity: 1500)
        var flick: [Double] = []
        for _ in 0..<5 {
            f = Spring.step(f, to: 100, dt: 1.0 / 120, dampingRatio: 0.8, response: 0.4).state
            flick.append(f.value)
        }
        for (a, b) in zip(flick, [11.9318, 22.946792, 33.048245, 42.25324, 50.589729]) { XCTAssertEqual(a, b, accuracy: 1e-5) }
    }

    func testSettlesExactlyOnTarget() {
        var s = Spring.State(value: 0, velocity: 0)
        var rest = false
        for _ in 0..<600 where !rest { (s, rest) = Spring.step(s, to: 50, dt: 1.0 / 60) }
        XCTAssertTrue(rest)
        XCTAssertEqual(s, Spring.State(value: 50, velocity: 0))
    }

    func testStalledFrameDoesNotFling() {
        let a = Spring.step(.init(value: 0, velocity: 0), to: 100, dt: 5).state
        let b = Spring.step(.init(value: 0, velocity: 0), to: 100, dt: 0.032).state
        XCTAssertEqual(a, b)
    }

    func testProjection() {
        XCTAssertEqual(Spring.projection(velocity: 1000), 499, accuracy: 0.001)
        XCTAssertEqual(Spring.projection(velocity: 0), 0)
    }
}
