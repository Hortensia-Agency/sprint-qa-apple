import Foundation

/// The widget's text: the host's own strings first, then the project's
/// wording from Sprint (title, intro, submit, thanks), then English.
public struct Strings: Sendable {
    /// Keys a host may set that have no English default.
    public enum Own: String, Sendable {
        case title, intro
    }

    private let host: [String: String]
    private let copy: WidgetAppearance.Copy?

    public init(host: [String: String] = [:], copy: WidgetAppearance.Copy? = nil) {
        self.host = host
        self.copy = copy
    }

    /// The host's or the project's text for a key, or nil when neither set one.
    public func own(_ key: String) -> String? {
        if let s = host[key], !s.isEmpty { return s }
        let projectText: String?
        switch key {
        case "title": projectText = copy?.title
        case "intro": projectText = copy?.intro
        case "submit": projectText = copy?.submit
        case "thanks": projectText = copy?.thanks
        default: projectText = nil
        }
        return projectText.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func own(_ key: Own) -> String? { own(key.rawValue) }

    public func callAsFunction(_ key: StringKey, _ vars: [String: CustomStringConvertible] = [:]) -> String {
        var s = own(key.rawValue) ?? StringKey.defaults[key] ?? key.rawValue
        for (name, value) in vars {
            s = s.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return s
    }
}
