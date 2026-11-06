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
        /// The look set in code; wins over the project's Appearance settings.
        public var appearance: AppearanceOverride?
        /// The host's own text, by `StringKey` raw value, plus "title" and "intro".
        public var strings: [String: String]
        public var rightToLeft: Bool?

        public init(
            widgetKey: String, enabled: Bool, redirectScheme: String, origin: URL = defaultOrigin,
            appearance: AppearanceOverride? = nil, strings: [String: String] = [:], rightToLeft: Bool? = nil
        ) {
            self.widgetKey = widgetKey
            self.enabled = enabled
            self.redirectScheme = redirectScheme
            self.origin = origin
            self.appearance = appearance
            self.strings = strings
            self.rightToLeft = rightToLeft
        }
    }

    static private(set) var configuration: Configuration?
    static private(set) var client: SprintQAClient?
    static let storage = WidgetStorage()

    public static func configure(_ configuration: Configuration) {
        guard configuration.enabled else { return }
        guard configuration.widgetKey.hasPrefix("pk_qa_") else {
            print("[SprintQA] no widget key (pk_qa_…); the widget stays off.")
            return
        }
        self.configuration = configuration
        client = SprintQAClient(origin: configuration.origin, widgetKey: configuration.widgetKey, pat: storage.pat)
    }

    /// The screen the person is on, matched against the project's hidden
    /// routes and sent with each report.
    public static var route: String?

    /// The person's own choice to hide the bubble on this device. A host's
    /// settings switch reads and sets it.
    public static var isHidden: Bool {
        get { storage.hidden }
        set { storage.hidden = newValue }
    }

    public static var isSignedIn: Bool { client?.hasPat ?? false }

    /// Runs "Sign in with Sprint" and keeps the token in the Keychain. Returns
    /// the text to show when it failed, nil on success or when the person
    /// closed the sheet.
    @discardableResult
    public static func signIn() async -> String? {
        guard let configuration, let client else { return Strings()(.reportingOff) }
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
            return SignIn.message(for: code).map { Strings(host: configuration.strings)($0) }
        }
    }

    /// Accepts a token pasted from the team, the fallback to signing in.
    public static func usePastedToken(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPatShape(t), let client else { return false }
        storage.pat = t
        client.pat = t
        return true
    }

    public static func signOut() {
        storage.pat = nil
        client?.pat = nil
    }
}
#endif
