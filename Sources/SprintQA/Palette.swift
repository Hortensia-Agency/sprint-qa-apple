#if os(iOS)
import SprintQACore
import SwiftUI
import UIKit

/// Resolves the widget's colors and metrics from the host's style, the
/// project's appearance and Sprint's tokens. Colors are dynamic UIColors, so
/// they follow light and dark wherever they're drawn.
@MainActor
struct Palette {
    let style: SprintQAStyle
    let appearance: WidgetAppearance?

    func uiColor(_ token: Token) -> UIColor {
        if let own = style.colors[token] { return own }
        if let accent = style.accent, let derived = accentFamily(token, accent) { return derived }
        let appearance = self.appearance
        return UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return UIColor(Theme(dark: dark, appearance: appearance)[token])
        }
    }

    func color(_ token: Token) -> Color { Color(uiColor: uiColor(token)) }

    private func accentFamily(_ token: Token, _ accent: UIColor) -> UIColor? {
        switch token {
        case .signal, .signalStrong, .ring: return accent
        case .signalSoft: return accent.withAlphaComponent(0.14)
        case .signalForeground:
            return UIColor { traits in
                let c = accent.resolvedColor(with: traits)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                return RGBA(r: r, g: g, b: b).luminance > 0.4 ? .black : .white
            }
        default: return nil
        }
    }

    /// The UIKit style to force on the widget's window, or unspecified to follow the device.
    var interfaceStyle: UIUserInterfaceStyle {
        let mode = style.colorScheme.map(\.rawValue) ?? appearance?.theme
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    var radius: SprintQAStyle.Radius {
        if let own = style.radius { return own }
        let r = appearance?.radius ?? .init(sm: 4, md: 6, lg: 8)
        return .init(small: r.sm, medium: r.md, large: r.lg)
    }

    /// Ink by default; the accent once the project or the host sets one.
    var bubbleBackground: UIColor {
        if let own = style.bubble.background { return own }
        let accented = style.accent != nil || style.colors[.signal] != nil || Theme(dark: false, appearance: appearance).accented
        return uiColor(accented ? .signal : .primary)
    }

    var bubbleForeground: UIColor {
        if let own = style.bubble.foreground { return own }
        return bubbleBackground == uiColor(.signal) ? uiColor(.signalForeground) : uiColor(.primaryForeground)
    }

    var bubbleSize: CGFloat { max(44, style.bubble.size ?? appearance?.bubble.size ?? 56) }

    var bubbleOnLeading: Bool {
        if let side = style.bubble.side { return side == .leading }
        return appearance?.bubble.side == "left"
    }

    var bubbleIcon: SprintQAStyle.Bubble.Icon {
        if let own = style.bubble.icon { return own }
        switch appearance?.bubble.icon {
        case "bug": return .symbol("ladybug.fill")
        case "chat": return .symbol("bubble.left.fill")
        case "help": return .symbol("questionmark")
        case "logo":
            if let logo = appearance?.logoUrl.flatMap(URL.init(string:)) { return .url(logo) }
            return .symbol("exclamationmark.bubble.fill")
        default: return .symbol("exclamationmark.bubble.fill")
        }
    }

    var bubbleLabel: String? { style.bubble.label ?? appearance?.bubble.label }

    var rightToLeft: Bool {
        style.rightToLeft ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
    }

    func hidden(on route: String?) -> Bool {
        routeHidden(route, (appearance?.hiddenRoutes ?? []) + style.hiddenRoutes)
    }

    var strings: Strings {
        var host = Dictionary(uniqueKeysWithValues: style.strings.map { ($0.key.rawValue, $0.value) })
        if let title = style.title { host["title"] = title }
        if let intro = style.intro { host["intro"] = intro }
        return Strings(host: host, copy: appearance?.copy)
    }

    /// The widget's font at a text style, in the host's family when set, scaled with Dynamic Type.
    func font(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let family = style.fontFamily else { return .system(textStyle, weight: weight) }
        return .custom(family, size: UIFont.preferredFont(forTextStyle: textStyle.uiKit).pointSize, relativeTo: textStyle).weight(weight)
    }
}

extension UIColor {
    convenience init(_ c: RGBA) {
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}
#endif
