import Foundation

/// A color as sRGB components, so this target stays free of UIKit.
public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    /// "39 80% 31.2%" or "225 13% 6% / 0.32", the form Sprint's tokens use.
    public init?(hsl triple: String) {
        let halves = triple.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let parts = halves[0].split(whereSeparator: \.isWhitespace).map { $0.replacingOccurrences(of: "%", with: "") }
        guard parts.count == 3, let h = Double(parts[0]), let s = Double(parts[1]), let l = Double(parts[2]) else { return nil }
        let alpha = halves.count > 1 ? Double(halves[1]) : 1
        guard let alpha else { return nil }
        let sat = s / 100, light = l / 100
        let k = { (n: Double) in (n + h / 30).truncatingRemainder(dividingBy: 12) }
        let chroma = sat * min(light, 1 - light)
        let f = { (n: Double) in light - chroma * max(-1, min(k(n) - 3, 9 - k(n), 1)) }
        self.init(r: f(0), g: f(8), b: f(4), a: alpha)
    }

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// "#1F6FEB", "1F6FEB", "#1F6FEBCC" or the short "#16E". Nil for anything else.
    public init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let n = h.count == 8 ? v : (v << 8) | 0xFF
        self.init(r: Double((n >> 24) & 0xFF) / 255, g: Double((n >> 16) & 0xFF) / 255, b: Double((n >> 8) & 0xFF) / 255, a: Double(n & 0xFF) / 255)
    }

    public func opacity(_ a: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a) }

    /// WCAG relative luminance, for picking readable text on a color.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

/// The widget's colors and corners for one appearance, with the project's
/// tokens laid over Sprint's.
public struct Theme: Equatable, Sendable {
    public let dark: Bool
    public let radius: WidgetAppearance.Radius
    /// The bubble is ink by default and takes the accent once a project sets one.
    public let accented: Bool
    public let rtl: Bool
    private let colors: [String: RGBA]

    public init(dark: Bool, appearance: WidgetAppearance?, rtl: Bool = false) {
        var tokens = dark ? Tokens.dark : Tokens.light
        let own = dark ? appearance?.tokens?.dark : appearance?.tokens?.light
        if let own { tokens.merge(own) { _, theirs in theirs } }
        self.dark = dark
        self.radius = appearance?.radius ?? .init(sm: 4, md: 6, lg: 8)
        self.accented = appearance?.bubbleAccent ?? (own != nil)
        self.rtl = rtl
        self.colors = tokens.compactMapValues(RGBA.init(hsl:))
    }

    /// Whether the widget draws dark, from the project's theme and the device's.
    public static func isDark(mode: String?, systemDark: Bool) -> Bool {
        switch mode {
        case "dark": return true
        case "light": return false
        default: return systemDark
        }
    }

    public subscript(_ token: Token) -> RGBA { self[token.rawValue] }

    public subscript(_ token: String) -> RGBA {
        colors[token] ?? colors["foreground"] ?? RGBA(r: 0, g: 0, b: 0)
    }

    /// Same mapping as the web widget's severity dots.
    public func severity(_ s: Severity) -> RGBA {
        switch s {
        case .low: return self["subtle-foreground"]
        case .medium: return self["warning"]
        case .high: return self["destructive"].opacity(0.65)
        case .blocker: return self["destructive"]
        }
    }

    public func state(_ state: String) -> RGBA {
        colors["state-\(state)"] ?? self["state-backlog"]
    }
}
