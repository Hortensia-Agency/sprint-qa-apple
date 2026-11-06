import Foundation

// Wire contract for Sprint's /api/widget/* routes, mirroring the React Native
// widget's contract.ts. The server only adds fields, so every type decodes
// with unknown keys ignored and newer fields optional.

public enum Severity: String, Codable, CaseIterable, Sendable {
    case low, medium, high, blocker
}

/// "standard", or a strict profile for widget reporters.
public enum CaptureProfile: String, Codable, Sendable {
    case standard, strict
    case strictText = "strict_text"
}

/// The project's look, resolved by Sprint. Absent on older servers.
public struct WidgetAppearance: Codable, Equatable, Sendable {
    public struct Radius: Codable, Equatable, Sendable {
        public var sm: Double
        public var md: Double
        public var lg: Double
        public init(sm: Double, md: Double, lg: Double) {
            self.sm = sm
            self.md = md
            self.lg = lg
        }
    }
    public struct ThemeTokens: Codable, Equatable, Sendable {
        public var light: [String: String]
        public var dark: [String: String]
    }
    public struct Bubble: Codable, Equatable, Sendable {
        public var icon: String
        public var size: Double
        public var side: String
        public var label: String?
    }
    public struct Copy: Codable, Equatable, Sendable {
        public var title: String?
        public var intro: String?
        public var submit: String?
        public var thanks: String?
    }

    public var theme: String
    public var radius: Radius
    /// HSL triples laid over Sprint's tokens, per theme; nil keeps Sprint's look.
    public var tokens: ThemeTokens?
    public var bubbleAccent: Bool?
    public var logoUrl: String?
    public var bubble: Bubble
    /// Matched against the route the host sets per screen.
    public var hiddenRoutes: [String]
    public var copy: Copy
}

/// The look a host sets in code, in the same raw form as the project's
/// Appearance settings in Sprint. Every field is optional and wins over the
/// project's setting. Sprint validates it; a refused override leaves the
/// project's look in place and comes back as `appearanceOverrideError`.
public struct AppearanceOverride: Encodable, Equatable, Sendable {
    public struct Accent: Encodable, Equatable, Sendable {
        public var light: String
        public var dark: String?
        public init(light: String, dark: String? = nil) {
            self.light = light
            self.dark = dark
        }
    }
    public struct Colors: Encodable, Equatable, Sendable {
        public var light: [String: String]?
        public var dark: [String: String]?
        public init(light: [String: String]? = nil, dark: [String: String]? = nil) {
            self.light = light
            self.dark = dark
        }
    }
    public struct Bubble: Encodable, Equatable, Sendable {
        public var icon: String?
        public var size: String?
        public var side: String?
        public var label: String?
        public init(icon: String? = nil, size: String? = nil, side: String? = nil, label: String? = nil) {
            self.icon = icon
            self.size = size
            self.side = side
            self.label = label
        }
    }
    public struct Copy: Encodable, Equatable, Sendable {
        public var title: String?
        public var intro: String?
        public var submit: String?
        public var thanks: String?
        public init(title: String? = nil, intro: String? = nil, submit: String? = nil, thanks: String? = nil) {
            self.title = title
            self.intro = intro
            self.submit = submit
            self.thanks = thanks
        }
    }

    public var accent: Accent?
    public var colors: Colors?
    public var theme: String?
    public var radius: String?
    public var showLogo: Bool?
    public var bubble: Bubble?
    public var hiddenRoutes: [String]?
    public var copy: Copy?

    public init(
        accent: Accent? = nil, colors: Colors? = nil, theme: String? = nil, radius: String? = nil,
        showLogo: Bool? = nil, bubble: Bubble? = nil, hiddenRoutes: [String]? = nil, copy: Copy? = nil
    ) {
        self.accent = accent
        self.colors = colors
        self.theme = theme
        self.radius = radius
        self.showLogo = showLogo
        self.bubble = bubble
        self.hiddenRoutes = hiddenRoutes
        self.copy = copy
    }
}

/// GET /api/widget/config
public struct WidgetConfig: Decodable, Sendable {
    public var enabled: Bool
    // Declared by older contracts but never sent.
    public var projectId: Int?
    public var projectName: String
    public var qaUrls: [String]
    public var signoffPolicy: String
    public var captureEnabled: Bool?
    public var appearance: WidgetAppearance?
    public var appearanceOverrideError: String?
}

/// GET /api/widget/me
public struct WidgetMe: Decodable, Sendable {
    public struct User: Decodable, Sendable {
        public var id: String
        public var name: String?
        public var email: String?
        public var tier: String?
    }
    public var user: User
    public var canQa: Bool
    public var blocked: Bool
    public var role: String?
    public var captureProfile: CaptureProfile?
}

/// A row in GET /api/widget/queue
public struct QueueTask: Decodable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var state: String
    public var severity: Severity?
    public var assigneeId: String?
    public var updatedAt: String
    public var reporterId: String?
}

public struct QueueResponse: Decodable, Sendable {
    public var tasks: [QueueTask]
    public var blocked: Bool
}

/// GET /api/widget/tasks/:id, the fields the widget shows.
public struct TaskDetail: Decodable, Sendable {
    public struct Task: Decodable, Sendable {
        public var id: Int
        public var title: String
        public var state: String
        public var description: String?
    }

    public struct Person: Decodable, Sendable {
        public var name: String
    }

    public struct Media: Decodable, Identifiable, Sendable {
        public var id: Int
        public var filename: String
        public var url: String?
    }

    public struct Transcript: Decodable, Sendable {
        public var state: String
        public var text: String?
        public var parkReason: String?
        public var failedReason: String?
    }

    public struct AudioNote: Decodable, Identifiable, Sendable {
        public var id: Int
        public var filename: String
        public var url: String
        /// Absent on servers older than transcription.
        public var transcript: Transcript?
    }

    public struct Repro: Decodable, Sendable {
        public var staleEnvRetest: Bool?
        public var staleEnvRetestReason: String?
    }

    public var task: Task
    public var activeVerifiedCount: Int
    public var fixer: Person?
    public var screenshots: [Media]?
    public var audioNotes: [AudioNote]?
    public var demoVideos: [Media]?
    public var reproContext: Repro?
}

/// POST /api/widget/report
public struct ReportInput: Encodable, Sendable {
    public struct AutoContext: Encodable, Sendable {
        public struct Size: Encodable, Equatable, Sendable {
            public var w: Int
            public var h: Int
            public init(w: Int, h: Int) {
                self.w = w
                self.h = h
            }
        }
        /// Sprint's DiagnosticContext (lib/signals/context.ts), the fields a phone knows.
        public struct Env: Encodable, Equatable, Sendable {
            public var platform = "ios"
            public var osName: String?
            public var osVersion: String?
            public var appVersion: String?
            public var deviceModel: String?
            public var timezone: String?
            public var utcOffset: Int?
            public var locale: String?
            public var viewport: Size?
            public var screen: Size?
            public var handled = true
            public init(osName: String? = nil, osVersion: String? = nil, appVersion: String? = nil, deviceModel: String? = nil, timezone: String? = nil, utcOffset: Int? = nil, locale: String? = nil, viewport: Size? = nil, screen: Size? = nil) {
                self.osName = osName
                self.osVersion = osVersion
                self.appVersion = appVersion
                self.deviceModel = deviceModel
                self.timezone = timezone
                self.utcOffset = utcOffset
                self.locale = locale
                self.viewport = viewport
                self.screen = screen
            }
        }
        /// The screen the app was on, e.g. "Checkout/Payment".
        public var route: String?
        public var viewport: Size?
        public var userAgent: String?
        public var consoleErrors: [String]?
        public var env: Env?
        public init(route: String? = nil, viewport: Size? = nil, userAgent: String? = nil, consoleErrors: [String]? = nil, env: Env? = nil) {
            self.route = route
            self.viewport = viewport
            self.userAgent = userAgent
            self.consoleErrors = consoleErrors
            self.env = env
        }
    }
    public var title: String
    public var description: String?
    public var severity: Severity?
    /// http(s) only; the server refuses anything else, so app screens go in autoContext.route.
    public var reproUrl: String?
    public var autoContext: AutoContext?

    public init(title: String, description: String? = nil, severity: Severity? = nil, autoContext: AutoContext? = nil) {
        self.title = title
        self.description = description
        self.severity = severity
        self.autoContext = autoContext
    }
}

public struct ReportResponse: Decodable, Sendable {
    public var bugTaskId: Int
    public var state: String
    /// The ticket waits for a team member's review before it reaches the board.
    public var held: Bool?
}

public struct AttachmentResponse: Decodable, Sendable {
    public var id: Int
    public var sizeBytes: Int
    public var mimeType: String
}

public struct PresignResponse: Decodable, Sendable {
    public var uploadUrl: String
    public var objectKey: String
}
