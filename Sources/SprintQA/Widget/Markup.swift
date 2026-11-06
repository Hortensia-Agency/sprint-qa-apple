#if os(iOS)
import SprintQACore
import SwiftUI
import UIKit

/// A screenshot on its way into a report: the whole capture, the part chosen
/// and what was drawn on it.
struct ShotDraft: Equatable {
    var image: UIImage
    var crop: CGRect
    var marks: [Mark] = []
    var includeFull = false

    var isPartial: Bool { AreaSelection.isPartial(crop, of: image.size) }

    /// The crop with every mark burnt in, at the capture's pixel scale.
    func flattened() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { ctx in
            image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
            ctx.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            MarkRenderer.draw(marks, in: ctx.cgContext)
        }
    }
}

/// Draws marks in screenshot points. The editor, the review thumbnail and the
/// uploaded file all go through here, so the file matches what was on screen.
enum MarkRenderer {
    static func draw(_ marks: [Mark], in cg: CGContext) {
        for m in marks { draw(m, in: cg) }
    }

    static func draw(_ m: Mark, in cg: CGContext) {
        let color = UIColor(m.color).cgColor
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(color)
        cg.setFillColor(color)
        cg.setLineWidth(m.size)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        switch m.tool {
        case .pen:
            guard let first = m.points.first else { return }
            cg.move(to: first)
            for p in m.points.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()
        case .rect:
            cg.addPath(UIBezierPath(roundedRect: m.box, cornerRadius: 3).cgPath)
            cg.strokePath()
        case .ellipse:
            cg.strokeEllipse(in: m.box)
        case .hide:
            cg.setFillColor(UIColor(Mark.hideFill).cgColor)
            cg.fill(m.box)
        case .arrow:
            cg.move(to: m.start)
            cg.addLine(to: m.end)
            cg.strokePath()
            let (a, b) = m.arrowHead
            cg.move(to: m.end)
            cg.addLine(to: a)
            cg.addLine(to: b)
            cg.closePath()
            cg.fillPath()
        case .text:
            let light = m.color.luminance > 0.6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: m.size, weight: .semibold),
                .foregroundColor: UIColor(m.color),
                .strokeColor: light ? UIColor(Mark.hideFill) : UIColor.white,
                .strokeWidth: -1.5,
            ]
            let s = NSAttributedString(string: m.text, attributes: attrs)
            UIGraphicsPushContext(cg)
            s.draw(at: CGPoint(x: m.start.x, y: m.start.y - s.size().height / 2))
            UIGraphicsPopContext()
        }
    }
}

/// A crop with its marks, fitted to whatever frame it is given.
struct MarkedShot: View {
    let image: UIImage
    let crop: CGRect
    let marks: [Mark]

    var body: some View {
        Canvas { ctx, size in
            let scale = size.width / crop.width
            ctx.draw(Image(uiImage: image), in: CGRect(
                x: -crop.minX * scale, y: -crop.minY * scale,
                width: image.size.width * scale, height: image.size.height * scale
            ))
            ctx.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -crop.minX, y: -crop.minY)
                MarkRenderer.draw(marks, in: cg)
            }
        }
        .aspectRatio(crop.width / crop.height, contentMode: .fit)
        .clipped()
    }
}
#endif
