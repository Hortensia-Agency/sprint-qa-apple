#if os(iOS)
import XCTest
@testable import SprintQA
@testable import SprintQACore

final class MarkupTests: XCTestCase {
    /// A 100 by 200 point capture at 2x, white everywhere.
    private func capture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        let cg = image.cgImage!
        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return Array(out.prefix(3))
    }

    func testFlattenKeepsTheCropAtTheCaptureScale() {
        let d = ShotDraft(image: capture(), crop: CGRect(x: 10, y: 20, width: 50, height: 60))
        let out = d.flattened()
        XCTAssertEqual(out.size, CGSize(width: 50, height: 60))
        XCTAssertEqual(out.cgImage?.width, 100)
        XCTAssertTrue(d.isPartial)
    }

    func testHideCoversWhatIsUnderIt() {
        let hide = Mark(tool: .hide, color: Mark.colors[0], size: 3, points: [CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 50)])
        let d = ShotDraft(image: capture(), crop: CGRect(x: 0, y: 0, width: 100, height: 200), marks: [hide])
        let out = d.flattened()
        XCTAssertEqual(pixel(out, x: 50, y: 70), [0x11, 0x18, 0x27])
        XCTAssertEqual(pixel(out, x: 150, y: 300), [255, 255, 255])
    }
}
#endif
