import CoreGraphics
import Foundation

/// One mark drawn on a screenshot, in the screenshot's own points, so it
/// draws the same at any zoom and when the crop is flattened for upload.
public struct Mark: Equatable, Sendable {
    public enum Tool: String, CaseIterable, Sendable {
        case pen, rect, ellipse, arrow, text, hide
    }

    public var tool: Tool
    public var color: RGBA
    /// Stroke width, or the font size for text.
    public var size: Double
    /// The path for pen; start and end for shapes; the baseline origin for text.
    public var points: [CGPoint]
    public var text: String

    public init(tool: Tool, color: RGBA, size: Double, points: [CGPoint], text: String = "") {
        self.tool = tool
        self.color = color
        self.size = size
        self.points = points
        self.text = text
    }

    /// The web widget's palette, so a marked-up shot reads the same from either.
    public static let colors: [RGBA] = ["#ef4444", "#f59e0b", "#eab308", "#22c55e", "#3b82f6", "#a855f7", "#ec4899", "#ffffff", "#111827"]
        .compactMap { RGBA(hex: $0) }

    /// The fill of the Hide tool: solid, so nothing under it can be recovered.
    public static let hideFill = RGBA(hex: "#111827")!

    public var start: CGPoint { points.first ?? .zero }
    public var end: CGPoint { points.last ?? .zero }

    /// The box a shape spans, whichever way it was dragged.
    public var box: CGRect { AreaSelection.rect(start, end) }

    /// True for a mark too small to mean anything, such as a tap with a shape tool.
    public var isTrivial: Bool {
        switch tool {
        case .pen: return points.count < 2
        case .text: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return abs(end.x - start.x) < 4 && abs(end.y - start.y) < 4
        }
    }

    /// The two outer corners of an arrow's head; the tip is `end`.
    public var arrowHead: (CGPoint, CGPoint) {
        let a = atan2(end.y - start.y, end.x - start.x)
        let head = 10 + size * 2
        return (
            CGPoint(x: end.x - head * cos(a - 0.45), y: end.y - head * sin(a - 0.45)),
            CGPoint(x: end.x - head * cos(a + 0.45), y: end.y - head * sin(a + 0.45))
        )
    }
}

/// The part of a screenshot a report is about.
public enum AreaSelection {
    /// The rectangle between two drag points, whichever way the drag went.
    public static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Big enough to be a deliberate selection rather than a stray tap.
    public static func isUsable(_ r: CGRect) -> Bool {
        r.width > 12 && r.height > 12
    }

    /// A selection made over the shown screen, in the screenshot's points, kept inside it.
    public static func crop(_ r: CGRect, view: CGSize, image: CGSize) -> CGRect {
        guard view.width > 0, view.height > 0 else { return CGRect(origin: .zero, size: image) }
        let sx = image.width / view.width, sy = image.height / view.height
        let scaled = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy).integral
        return scaled.intersection(CGRect(origin: .zero, size: image))
    }

    /// True when the crop leaves part of the screenshot out.
    public static func isPartial(_ crop: CGRect, of image: CGSize) -> Bool {
        crop.minX > 0 || crop.minY > 0 || crop.width < image.width || crop.height < image.height
    }
}
