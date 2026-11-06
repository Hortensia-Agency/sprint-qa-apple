#if os(iOS)
import SwiftUI
import UIKit

/// A window above the host app that only takes touches on the widget's own
/// views (the bubble, the toast, a presented sheet); everything else falls
/// through to the app underneath.
final class OverlayWindow: UIWindow {
    weak var model: WidgetModel?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if rootViewController?.presentedViewController != nil { return hit }
        return MainActor.assumeIsolated { model?.accepts(point) == true } ? hit : nil
    }

    /// Insets are zero until the window is on screen; lay the bubble out again once they arrive.
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        let i = safeAreaInsets
        MainActor.assumeIsolated {
            model?.updateLayout(size: bounds.size, insets: EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right))
        }
    }
}

/// Puts the overlay on the app's foreground scene, now or once one activates.
@MainActor
final class OverlayInstaller {
    private(set) var window: OverlayWindow?
    private var observer: NSObjectProtocol?

    func install(model: WidgetModel) {
        if window != nil { return }
        if let scene = Self.foregroundScene() {
            attach(to: scene, model: model)
            return
        }
        observer = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.window == nil, let scene = note.object as? UIWindowScene else { return }
                self.attach(to: scene, model: model)
            }
        }
    }

    private func attach(to scene: UIWindowScene, model: WidgetModel) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let w = OverlayWindow(windowScene: scene)
        w.model = model
        w.windowLevel = .alert - 1
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: WidgetRoot(model: model, style: SprintQA.style))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
        model.window = w
    }

    static func foregroundScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first { $0.activationState == .foregroundInactive }
    }
}
#endif
