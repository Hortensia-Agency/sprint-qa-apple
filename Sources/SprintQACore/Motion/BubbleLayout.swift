import Foundation

/// Where the bubble rests: always against the leading or trailing edge, at a
/// height inside the safe area. Pure geometry, so the snap rules are testable.
public struct BubbleLayout: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public var width: Double
    public var height: Double
    /// Safe area insets: top, leading, bottom, trailing.
    public var insets: (top: Double, left: Double, bottom: Double, right: Double)
    public var size: Double
    public var margin: Double = 12

    public init(width: Double, height: Double, insets: (top: Double, left: Double, bottom: Double, right: Double), size: Double) {
        self.width = width
        self.height = height
        self.insets = insets
        self.size = size
    }

    public static func == (a: BubbleLayout, b: BubbleLayout) -> Bool {
        a.width == b.width && a.height == b.height && a.size == b.size && a.margin == b.margin
            && a.insets.top == b.insets.top && a.insets.left == b.insets.left
            && a.insets.bottom == b.insets.bottom && a.insets.right == b.insets.right
    }

    public var leftX: Double { insets.left + margin }
    public var rightX: Double { width - insets.right - margin - size }
    public var minY: Double { insets.top + margin }
    public var maxY: Double { max(minY, height - insets.bottom - margin - size) }

    /// Top-left corner of the bubble resting on `side` (0 leading, 1 trailing) at `fraction` of the usable height.
    public func rest(side: Int, fraction: Double) -> Point {
        Point(x: side == 0 ? leftX : rightX, y: minY + (maxY - minY) * min(1, max(0, fraction)))
    }

    /// Side and height fraction for a resting point, the form stored on the device.
    public func stored(_ p: Point) -> (side: Int, fraction: Double) {
        (p.x + size / 2 < width / 2 ? 0 : 1, maxY > minY ? (p.y - minY) / (maxY - minY) : 0)
    }

    /// The snap target for a release at `p` moving at `velocity` (points per
    /// second): the edge and height nearest to where momentum would carry it.
    public func snap(from p: Point, velocity: Point) -> Point {
        let px = p.x + Spring.projection(velocity: velocity.x)
        let py = p.y + Spring.projection(velocity: velocity.y)
        return Point(x: px + size / 2 < width / 2 ? leftX : rightX, y: min(maxY, max(minY, py)))
    }

    /// Past an edge the bubble follows less and less (rubber band).
    public static func rubberBand(_ overshoot: Double, dimension: Double, constant: Double = 0.55) -> Double {
        overshoot * dimension * constant / (dimension + constant * abs(overshoot))
    }

    /// Keeps a dragged point inside the screen, with resistance past the safe area.
    public func clampDrag(_ p: Point) -> Point {
        func soft(_ v: Double, _ lo: Double, _ hi: Double, _ dim: Double) -> Double {
            if v < lo { return lo + BubbleLayout.rubberBand(v - lo, dimension: dim) }
            if v > hi { return hi + BubbleLayout.rubberBand(v - hi, dimension: dim) }
            return v
        }
        return Point(x: soft(p.x, leftX, rightX, width), y: soft(p.y, minY, maxY, height))
    }
}
