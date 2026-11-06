#if os(iOS)
import Foundation
@_exported import SprintQACore

/// Sprint's QA widget for iOS. Call `configure` once at launch; the widget
/// stays off unless the host's build enables it and Sprint's config says the
/// project takes reports.
@MainActor
public enum SprintQA {
    public struct Configuration {
        /// The project's public key, `pk_qa_…`. Safe to ship.
        public var widgetKey: String
        /// The host's build flag (L0). False keeps the widget off entirely.
        public var enabled: Bool
        /// A URL scheme this app registers, also listed in the project's QA
        /// URLs in Sprint (for example `tapinn`). Sign-in returns to it.
        public var redirectScheme: String
        public var origin: URL
        /// A look Sprint checks (for example the accent's contrast) before
        /// applying, in the same form as the project's Appearance settings.
        /// For values set and changed from code at any time, use `SprintQA.style`.
        public var appearance: AppearanceOverride?

        public init(
            widgetKey: String, enabled: Bool, redirectScheme: String, origin: URL = defaultOrigin,
            appearance: AppearanceOverride? = nil
        ) {
            self.widgetKey = widgetKey
            self.enabled = enabled
            self.redirectScheme = redirectScheme
            self.origin = origin
            self.appearance = appearance
        }
    }

    /// This package's version, sent in each report's user agent.
    public static let version = "0.2.1"

    static private(set) var configuration: Configuration?
    static private(set) var client: SprintQAClient?
    static private(set) var model: WidgetModel?
    static let storage = WidgetStorage()

    /// Colors, icon, sizes, fonts and text, changeable from code at any time.
    public static let style = SprintQAStyle()

    public static func configure(_ configuration: Configuration) {
        guard configuration.enabled else { return }
        guard configuration.widgetKey.hasPrefix("pk_qa_") else {
            print("[SprintQA] no widget key (pk_qa_…); the widget stays off.")
            return
        }
        guard model == nil else { return }
        self.configuration = configuration
        let client = SprintQAClient(origin: configuration.origin, widgetKey: configuration.widgetKey, pat: storage.pat)
        self.client = client
        let model = WidgetModel(configuration: configuration, client: client, storage: storage, style: style)
        model.route = pendingRoute
        self.model = model
        Task { await model.start() }
    }

    private static var pendingRoute: String?

    /// The screen the person is on, matched against the project's hidden
    /// routes and sent with each report. Set it as screens appear.
    public static var route: String? {
        get { model?.route ?? pendingRoute }
        set {
            pendingRoute = newValue
            model?.route = newValue
        }
    }

    /// The person's own choice to hide the bubble on this device. A host's
    /// settings switch reads and sets it; the bubble shows or hides at once.
    public static var isHidden: Bool {
        get { model?.hidden ?? storage.hidden }
        set {
            if let model { model.setHidden(newValue) } else { storage.hidden = newValue }
        }
    }

    /// Opens the report sheet, e.g. from the host's own "Report a problem" button.
    public static func open() {
        model?.open()
    }

    public static var isSignedIn: Bool { client?.hasPat ?? false }

    /// Runs "Sign in with Sprint" and keeps the token in the Keychain. Returns
    /// the text to show when it failed, nil on success or when the person
    /// closed the sheet.
    @discardableResult
    public static func signIn() async -> String? {
        let strings = (model?.palette ?? Palette(style: style, appearance: nil)).strings
        guard let configuration, let client else { return strings(.reportingOff) }
        let outcome = await SignInSession().run(
            client: client, widgetKey: configuration.widgetKey,
            scheme: configuration.redirectScheme, deviceId: storage.deviceId
        )
        switch outcome {
        case .token(let token):
            storage.pat = token
            client.pat = token
            return nil
        case .failed(let code):
            if code == "exchange_failed" || code.hasPrefix("bad") {
                print("[SprintQA] sign-in refused (\(code)). Check that \"\(configuration.redirectScheme)://\" is in the project's QA URLs.")
            }
            return SignIn.message(for: code).map { strings($0) }
        }
    }

    /// Adds the widget's network capture to one of your own session
    /// configurations; URLSession.shared is covered already. It only records
    /// while a tester's bug video records, and redacts as the web widget does.
    public static func captureNetwork(in configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [CaptureURLProtocol.self] + (configuration.protocolClasses ?? [])
    }

    public static func signOut() {
        storage.pat = nil
        client?.pat = nil
    }
}
#endif
