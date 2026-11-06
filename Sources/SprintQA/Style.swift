#if os(iOS)
import Combine
import SprintQACore
import SwiftUI
import UIKit

/// Everything about how the widget looks, set from code at any time. Every
/// open screen redraws when a value changes, so values can come from remote
/// config, a theme switcher or a user setting while the app runs.
///
/// Precedence, highest first: what you set here, the project's Appearance
/// settings in Sprint, then Sprint's own look.
@MainActor
public final class SprintQAStyle: ObservableObject {
    /// Any color for any token. Dynamic colors work as they do in UIKit, e.g.
    /// `UIColor { $0.userInterfaceStyle == .dark ? .white : .black }`.
    @Published public var colors: [Token: UIColor] = [:]

    /// One color for the accent family (signal, signal-strong, signal-soft,
    /// ring), with readable text picked for it. Specific `colors` still win.
    @Published public var accent: UIColor?

    /// Light, dark, or follow the device. Nil keeps the project's setting.
    @Published public var colorScheme: ColorSchemePreference?

    /// Corner radii for small, medium and large surfaces. Nil keeps the project's.
    @Published public var radius: Radius?

    /// A font family for the widget's text, scaled with Dynamic Type. Nil uses the system font.
    @Published public var fontFamily: String?

    @Published public var bubble = Bubble()

    /// Your own text by key; keys you leave out stay as Sprint's.
    @Published public var strings: [StringKey: String] = [:]
    /// The sheet's title and a line above the report form; no default text.
    @Published public var title: String?
    @Published public var intro: String?

    /// Right to left. Nil follows the app's layout direction.
    @Published public var rightToLeft: Bool?

    /// Route names on which the bubble hides, `*` as a wildcard. Added to the project's own list.
    @Published public var hiddenRoutes: [String] = []

    @Published public var haptics = true

    public enum ColorSchemePreference: String, Sendable {
        case system, light, dark
    }

    public struct Radius: Equatable, Sendable {
        public var small: CGFloat
        public var medium: CGFloat
        public var large: CGFloat
        public init(small: CGFloat, medium: CGFloat, large: CGFloat) {
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Bubble: Equatable {
        public enum Side: String, Sendable { case leading, trailing }
        public enum Icon: Equatable {
            /// An SF Symbol by name, e.g. "flag.fill".
            case symbol(String)
            /// Any image: an asset from your catalog, or one drawn at runtime.
            case image(UIImage)
            /// An image loaded from a URL, e.g. a logo from your own backend.
            case url(URL)
        }

        /// Diameter in points; at least 44 is enforced.
        public var size: CGFloat?
        public var side: Side?
        public var icon: Icon?
        /// Text beside the bubble, e.g. "Feedback". Nil shows the icon alone.
        public var label: String?
        public var background: UIColor?
        public var foreground: UIColor?
        /// Frosted glass on iOS 26; solid elsewhere and under Reduce Transparency.
        public var glass = true

        public init() {}
    }

    /// The same color for a token, from SwiftUI.
    public func set(_ color: Color, for token: Token) {
        colors[token] = UIColor(color)
    }

    /// Clears everything set here; the project's look applies again.
    public func reset() {
        colors = [:]
        accent = nil
        colorScheme = nil
        radius = nil
        fontFamily = nil
        bubble = Bubble()
        strings = [:]
        title = nil
        intro = nil
        rightToLeft = nil
        hiddenRoutes = []
        haptics = true
    }
}

extension UIColor {
    /// A color from "#1F6FEB", "1F6FEB", "#1F6FEBCC" or "#16E", for values
    /// that arrive as text. Nil when the string isn't a hex color.
    public convenience init?(sprintQAHex hex: String) {
        guard let c = RGBA(hex: hex) else { return nil }
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// One color in light mode and another in dark.
    public static func sprintQA(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}
#endif
