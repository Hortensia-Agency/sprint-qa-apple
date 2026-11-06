#if os(iOS)
import Combine
import SprintQACore
import SwiftUI
import UIKit

/// What the sheet is showing.
enum SheetScreen: Equatable {
    case signIn
    case launcher
    case review(UIImage?)
    case sent(SentResult)
}

struct SentResult: Equatable {
    var taskId: Int
    var held: Bool
    /// A screenshot that didn't upload; the ticket exists, Retry sends it again.
    var failedScreenshot: Data?
}

/// The widget's state and flows. One per app, owned by `SprintQA`.
@MainActor
final class WidgetModel: ObservableObject {
    @Published private(set) var config: WidgetConfig?
    @Published private(set) var me: WidgetMe?
    @Published var route: String?
    @Published var hidden: Bool
    @Published var sheetShown = false
    @Published var screen: SheetScreen = .launcher
    @Published var detent: PresentationDetent = .medium
    @Published var showHiddenNotice = false
    @Published var position: BubbleLayout.Point?
    @Published var dragging = false
    @Published var overHide = false
    @Published var pressed = false
    @Published var signInError: String?
    @Published var signingIn = false

    weak var window: OverlayWindow?
    var layout: BubbleLayout?
    var noticeFrame: CGRect = .zero

    let client: SprintQAClient
    let configuration: SprintQA.Configuration
    let style: SprintQAStyle
    private let storage: WidgetStorage
    private let installer = OverlayInstaller()
    private let driver = SpringDriver()
    private var afterDismiss: (() -> Void)?
    private var previousKeyWindow: UIWindow?
    private var noticeTask: Task<Void, Never>?
    private var history: [(t: TimeInterval, p: BubbleLayout.Point)] = []
    private var grab = BubbleLayout.Point(x: 0, y: 0)
    private var styleChanges: AnyCancellable?

    init(configuration: SprintQA.Configuration, client: SprintQAClient, storage: WidgetStorage, style: SprintQAStyle) {
        self.configuration = configuration
        self.client = client
        self.storage = storage
        self.style = style
        self.hidden = storage.hidden
        // A host changing the bubble's size or side moves it to the matching rest spot.
        styleChanges = style.$bubble.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout(force: true) }
        }
    }

    var palette: Palette { Palette(style: style, appearance: config?.appearance) }

    // MARK: Lifecycle

    /// L1: Sprint's config must say the widget is on before anything shows.
    func start() async {
        do {
            let config = try await client.config(appearance: configuration.appearance)
            if let reason = config.appearanceOverrideError {
                print("[SprintQA] appearance ignored: \(reason)")
            }
            guard config.enabled else { return }
            self.config = config
        } catch {
            print("[SprintQA] widget config unavailable (\(error)); the widget stays off.")
            return
        }
        installer.install(model: self)
        await refreshMe()
    }

    func refreshMe() async {
        guard client.hasPat else {
            me = nil
            return
        }
        do {
            me = try await client.me()
        } catch let e as SprintQAError where e.status == 401 || e.status == 404 {
            // Revoked or expired token: Sprint answers 404 with no reason.
            SprintQA.signOut()
            me = nil
        } catch {
            // Offline: keep the token, try again when the sheet opens.
        }
    }

    var bubbleVisible: Bool {
        config != nil && !hidden && !palette.hidden(on: route)
    }

    /// Touches the overlay keeps; everything else reaches the host app.
    func accepts(_ point: CGPoint) -> Bool {
        if sheetShown { return true }
        if showHiddenNotice, noticeFrame.insetBy(dx: -8, dy: -8).contains(point) { return true }
        guard bubbleVisible, let p = position else { return false }
        let size = palette.bubbleSize
        let frame = CGRect(x: p.x, y: p.y, width: bubbleWidth(size), height: size)
        return frame.insetBy(dx: -10, dy: -10).contains(point)
    }

    func bubbleWidth(_ size: CGFloat) -> CGFloat {
        guard let label = palette.bubbleLabel, !label.isEmpty else { return size }
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        return size + (label as NSString).size(withAttributes: [.font: font]).width + 20
    }

    // MARK: Bubble position

    func updateLayout(size: CGSize, insets: EdgeInsets) {
        let s = palette.bubbleSize
        let next = BubbleLayout(width: size.width, height: size.height, insets: (insets.top, insets.leading, insets.bottom, insets.trailing), size: Double(bubbleWidth(s)))
        if next == layout, position != nil { return }
        layout = next
        relayout(force: false)
    }

    private func relayout(force: Bool) {
        guard let layout else { return }
        if !force, dragging { return }
        driver.stop()
        // Where the person last left it, unless the host just set a side in code.
        let stored = storage.bubblePosition
        var side = stored.map { Int($0.x) } ?? (palette.bubbleOnLeading ? 0 : 1)
        if force, let s = style.bubble.side { side = s == .leading ? 0 : 1 }
        position = layout.rest(side: side, fraction: stored?.y ?? 0.72)
    }

    func dragChanged(location: CGPoint, time: TimeInterval) {
        guard let layout else { return }
        if !dragging {
            driver.stop()
            let p = position ?? layout.rest(side: 1, fraction: 0.72)
            grab = .init(x: location.x - p.x, y: location.y - p.y)
            history = [(time, p)]
            pressed = true
        }
        let raw = BubbleLayout.Point(x: location.x - grab.x, y: location.y - grab.y)
        if !dragging {
            let start = history.first?.p ?? raw
            guard hypot(raw.x - start.x, raw.y - start.y) > 8 else { return }
            dragging = true
        }
        let p = layout.clampDrag(raw)
        position = p
        history.append((time, p))
        if history.count > 6 { history.removeFirst() }
        overHide = isOverHide(p)
    }

    /// Returns true when the touch was a tap rather than a drag.
    func dragEnded() -> Bool {
        pressed = false
        guard dragging, let layout, let p = position else {
            dragging = false
            return true
        }
        dragging = false
        if overHide {
            overHide = false
            hideByDrop()
            return false
        }
        var v = BubbleLayout.Point(x: 0, y: 0)
        if let a = history.first, let b = history.last, b.t > a.t {
            v = .init(x: (b.p.x - a.p.x) / (b.t - a.t), y: (b.p.y - a.p.y) / (b.t - a.t))
        }
        let to = layout.snap(from: p, velocity: v)
        let rest = layout.stored(to)
        storage.bubblePosition = (Double(rest.side), rest.fraction)
        let flick = hypot(v.x, v.y) > 600
        driver.animate(from: p, to: to, velocity: v, dampingRatio: flick ? 0.8 : 1) { [weak self] q in
            self?.position = q
        }
        return false
    }

    /// The Hide target's center, bottom middle above the home indicator.
    var hideCenter: CGPoint? {
        guard let layout else { return nil }
        return CGPoint(x: layout.width / 2, y: layout.height - layout.insets.bottom - 70)
    }

    private func isOverHide(_ p: BubbleLayout.Point) -> Bool {
        guard let c = hideCenter else { return false }
        let s = palette.bubbleSize
        return hypot(p.x + s / 2 - c.x, p.y + s / 2 - c.y) < 64
    }

    private func hideByDrop() {
        if style.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        setHidden(true)
        showHiddenNotice = true
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showHiddenNotice = false
        }
    }

    func undoHide() {
        noticeTask?.cancel()
        showHiddenNotice = false
        setHidden(false)
    }

    func setHidden(_ value: Bool) {
        hidden = value
        storage.hidden = value
        if !value { relayout(force: false) }
    }

    // MARK: Sheet

    func open() {
        guard config != nil else { return }
        signInError = nil
        screen = client.hasPat ? .launcher : .signIn
        detent = .medium
        present()
        if client.hasPat, me == nil { Task { await refreshMe() } }
    }

    private func present() {
        if !sheetShown {
            // Remember the host's key window once per visit, not the overlay itself
            // when the sheet comes back after a screenshot.
            if previousKeyWindow == nil {
                previousKeyWindow = window?.windowScene?.windows.first { $0.isKeyWindow && $0 !== window }
            }
            window?.makeKey()
        }
        sheetShown = true
    }

    func close() {
        sheetShown = false
    }

    /// Called by SwiftUI once the sheet is fully gone.
    func sheetDismissed() {
        if afterDismiss == nil {
            previousKeyWindow?.makeKey()
            previousKeyWindow = nil
        }
        let next = afterDismiss
        afterDismiss = nil
        next?()
    }

    func signIn() async {
        signingIn = true
        signInError = nil
        let failure = await SprintQA.signIn()
        signingIn = false
        if let failure {
            signInError = failure
            return
        }
        await refreshMe()
        if client.hasPat {
            withAnimation(.easeOut(duration: 0.2)) { screen = .launcher }
        }
    }

    func takeScreenshot() {
        afterDismiss = { [weak self] in
            guard let self else { return }
            // The sheet is gone; draw the host's windows only, never the overlay.
            let image = Screenshot.capture(excluding: self.window)
            self.screen = .review(image)
            self.detent = .large
            self.present()
        }
        close()
    }

    func writeItDown() {
        withAnimation(.easeOut(duration: 0.2)) {
            screen = .review(nil)
            detent = .large
        }
    }

    // MARK: Sending

    func send(title: String, details: String, severity: Severity, screenshot: UIImage?) async -> String? {
        let t = palette.strings
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return t(.summaryRequired) }
        let input = ReportInput(
            title: trimmed,
            description: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details,
            severity: severity,
            autoContext: DeviceContext.autoContext(route: route, window: previousKeyWindow ?? window)
        )
        let report: ReportResponse
        do {
            report = try await client.report(input)
        } catch let e as SprintQAError {
            switch e.status {
            case 401, 404:
                SprintQA.signOut()
                me = nil
                withAnimation(.easeOut(duration: 0.2)) { screen = .signIn }
                return t(.signInIncomplete)
            case 403: return t(.reportForbidden)
            case 429: return t(.reportRateLimited)
            case 400, 422: return t(.reportNeedsTitle)
            default: return t(.reportFailed)
            }
        } catch {
            return t(.reportFailed)
        }
        let data = screenshot?.jpegData(compressionQuality: 0.85)
        let uploaded = data == nil ? true : await upload(data!, taskId: report.bugTaskId)
        withAnimation(.easeOut(duration: 0.2)) {
            screen = .sent(.init(taskId: report.bugTaskId, held: report.held ?? false, failedScreenshot: uploaded ? nil : data))
            detent = .medium
        }
        return nil
    }

    /// Best effort, retried once; the ticket already exists either way.
    private func upload(_ data: Data, taskId: Int) async -> Bool {
        for attempt in 0..<2 {
            do {
                _ = try await client.uploadAttachment(taskId: taskId, kind: .screenshot, data: data, filename: "screenshot.jpg", mimeType: "image/jpeg")
                return true
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
            }
        }
        return false
    }

    func retryUpload(_ result: SentResult) async {
        guard let data = result.failedScreenshot else { return }
        let ok = await upload(data, taskId: result.taskId)
        if ok { screen = .sent(.init(taskId: result.taskId, held: result.held, failedScreenshot: nil)) }
    }
}
#endif
