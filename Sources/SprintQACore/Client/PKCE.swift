import CryptoKit
import Foundation

/// RFC 7636 S256, the same as Sprint's pkceChallengeFor.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init() {
        self.init(verifier: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64URL)
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The two halves of "Sign in with Sprint" that don't need a browser.
public enum SignIn {
    /// Opened in an ASWebAuthenticationSession. `redirect` must use a scheme
    /// listed in the project's QA URLs.
    public static func startURL(origin: URL, widgetKey: String, redirect: String, deviceId: String, challenge: String) -> URL {
        var c = URLComponents(url: origin.appendingPathComponent("api/widget/mobile-auth/start"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "key", value: widgetKey),
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "device", value: deviceId),
            URLQueryItem(name: "challenge", value: challenge),
        ]
        // URLComponents leaves + unescaped; the server reads it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    public enum Callback: Equatable, Sendable {
        case code(String)
        case error(String)
    }

    /// The redirect Sprint sends back: `?code=…`, or `?error=…`.
    public static func parse(_ url: URL) -> Callback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let e = items.first(where: { $0.name == "error" })?.value, !e.isEmpty { return .error(e) }
        if let c = items.first(where: { $0.name == "code" })?.value, !c.isEmpty { return .code(c) }
        return .error("no_code")
    }
}

extension SignIn {
    /// What a failed sign-in tells the person, by the code Sprint sends back.
    /// Nil when they closed the sheet themselves.
    public static func message(for error: String) -> StringKey? {
        switch error {
        case "cancelled": return nil
        case "not_a_qa_member": return .signInNotMember
        case "widget_disabled": return .reportingOff
        case "not_authenticated", "expired": return .signInIncomplete
        case "network": return .networkError
        default: return .signInFailed
        }
    }
}
