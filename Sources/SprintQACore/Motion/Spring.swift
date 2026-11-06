import Foundation

/// Sprint's gesture spring (lib/motion/spring.ts), in Apple's two-parameter
/// form: `dampingRatio` (1 = no overshoot) and `response` (seconds to reach the
/// target, not a duration). Kept step for step identical so the iOS bubble
/// moves like the web and React Native ones.
public enum Spring {
    public struct State: Equatable, Sendable {
        public var value: Double
        public var velocity: Double
        public init(value: Double, velocity: Double) {
            self.value = value
            self.velocity = velocity
        }
    }

    static let restVelocity = 4.0
    static let restDistance = 0.4
    static let maxFrame = 0.032
    static let substeps = 4

    /// Advances a spring by `dt` seconds toward `target`.
    public static func step(_ state: State, to target: Double, dt: Double, dampingRatio: Double = 1, response: Double = 0.35) -> (state: State, atRest: Bool) {
        let stiffness = pow(2 * .pi / response, 2)
        let damping = 4 * .pi * dampingRatio / response
        let h = min(maxFrame, max(0, dt)) / Double(substeps)
        var value = state.value, velocity = state.velocity
        for _ in 0..<substeps {
            let accel = -stiffness * (value - target) - damping * velocity
            velocity += accel * h
            value += velocity * h
        }
        let atRest = abs(velocity) < restVelocity && abs(value - target) < restDistance
        return atRest ? (State(value: target, velocity: 0), true) : (State(value: value, velocity: velocity), false)
    }

    /// Where a release at `velocity` (points per second) would coast to, the
    /// way a scroll view decelerates. Pick the snap target from this point.
    public static func projection(velocity: Double, decelerationRate: Double = 0.998) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }
}
