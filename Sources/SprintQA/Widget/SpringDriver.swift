#if os(iOS)
import QuartzCore
import SprintQACore
import UIKit

/// Runs two independent springs (x and y) on the display's refresh, starting
/// from the bubble's live position and the release velocity, so the hand-off
/// from the finger has no seam. Interruptible: `stop()` leaves it where it is.
@MainActor
final class SpringDriver: NSObject {
    private var link: CADisplayLink?
    private var x = Spring.State(value: 0, velocity: 0)
    private var y = Spring.State(value: 0, velocity: 0)
    private var target = BubbleLayout.Point(x: 0, y: 0)
    private var dampingRatio = 1.0
    private var last: CFTimeInterval = 0
    private var onFrame: ((BubbleLayout.Point) -> Void)?

    func animate(from: BubbleLayout.Point, to: BubbleLayout.Point, velocity: BubbleLayout.Point, dampingRatio: Double, onFrame: @escaping (BubbleLayout.Point) -> Void) {
        stop()
        if UIAccessibility.isReduceMotionEnabled {
            onFrame(to)
            return
        }
        x = .init(value: from.x, velocity: velocity.x)
        y = .init(value: from.y, velocity: velocity.y)
        target = to
        self.dampingRatio = dampingRatio
        self.onFrame = onFrame
        last = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = now - last
        last = now
        let sx = Spring.step(x, to: target.x, dt: dt, dampingRatio: dampingRatio, response: 0.4)
        let sy = Spring.step(y, to: target.y, dt: dt, dampingRatio: dampingRatio, response: 0.4)
        x = sx.state
        y = sy.state
        onFrame?(.init(x: x.value, y: y.value))
        if sx.atRest && sy.atRest { stop() }
    }
}
#endif
