import Foundation

/// One line on a capture's console, network or action track.
public struct CaptureEntry: Encodable, Sendable {
    public struct Network: Encodable, Sendable {
        public var method: String
        public var url: String
        public var status: Int
        public var ms: Int
        public var via = "urlsession"
        public var type = "fetch-xhr"
        public var resBytes: Int?
        public var reqHeaders: [String: String]?
        public var resHeaders: [String: String]?
    }

    public var t: Int
    public var kind: String
    public var level: String?
    public var args: [String]?
    public var action: String?
    public var label: String?
    public var error: Bool?
    public var data: Network?
}

/// The sidecar Sprint's capture viewer reads: the web's version 2 shape with
/// no DOM events, telemetry timed against the video's clock.
public struct CapturePayload: Encodable, Sendable {
    public var version = 2
    public var startedAt: Int64
    public var durationMs: Int
    public var truncated: Bool
    public var eventCount = 0
    public var telemetryCount: Int
    public var meta: [String: String]
    public var events: [String] = []
    public var telemetry: [CaptureEntry]
}

/// Collects a recording's telemetry, redacted as it arrives, from any thread.
public final class CaptureLog: @unchecked Sendable {
    public static let cap = 5000

    public let startedAt: Date
    private let lock = NSLock()
    private var entries: [CaptureEntry] = []
    private var truncated = false

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    /// Milliseconds from the start of the recording.
    public func offset(of date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt) * 1000))
    }

    public func console(level: String, _ message: String, at date: Date = Date()) {
        push(CaptureEntry(t: offset(of: date), kind: "console", level: level, args: [Redact.consoleArg(message)]))
    }

    public func network(method: String, url: String, status: Int, started: Date, resBytes: Int?,
                        reqHeaders: [String: String], resHeaders: [String: String], failed: Bool) {
        let data = CaptureEntry.Network(
            method: method.uppercased(), url: Redact.url(url), status: status, ms: Int(Date().timeIntervalSince(started) * 1000),
            resBytes: resBytes, reqHeaders: Redact.headers(reqHeaders), resHeaders: Redact.headers(resHeaders))
        push(CaptureEntry(t: offset(), kind: "network", error: failed ? true : nil, data: data))
    }

    /// A screen change in the host app, the phone's closest thing to a click trail.
    public func navigation(_ route: String) {
        push(CaptureEntry(t: offset(), kind: "action", action: "navigate", label: Redact.url(route)))
    }

    private func push(_ e: CaptureEntry) {
        lock.lock()
        defer { lock.unlock() }
        guard entries.count < Self.cap else {
            truncated = true
            return
        }
        entries.append(e)
    }

    public func finish(meta: [String: String], at end: Date = Date()) -> CapturePayload {
        lock.lock()
        defer { lock.unlock() }
        let sorted = entries.sorted { $0.t < $1.t }
        return CapturePayload(
            startedAt: Int64(startedAt.timeIntervalSince1970 * 1000), durationMs: offset(of: end),
            truncated: truncated, telemetryCount: sorted.count, meta: meta, telemetry: sorted)
    }
}
