#if os(iOS)
import UIKit

/// The host app's screen as the person sees it, without the widget's window.
@MainActor
enum Screenshot {
    static func capture(excluding overlay: UIWindow?) -> UIImage? {
        guard let scene = overlay?.windowScene ?? OverlayInstaller.foregroundScene() else { return nil }
        let windows = scene.windows
            .filter { $0 !== overlay && !$0.isHidden && $0.alpha > 0 }
            .sorted { $0.windowLevel < $1.windowLevel }
        guard !windows.isEmpty else { return nil }
        let bounds = scene.screen.bounds
        let format = UIGraphicsImageRendererFormat(for: scene.traitCollection)
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            for w in windows { w.drawHierarchy(in: w.frame, afterScreenUpdates: false) }
        }
    }
}
#endif
