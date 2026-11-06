import Foundation

/// Any non-2xx answer. Sprint answers every auth miss with the same 404 and no
/// reason, so only the status is kept.
public struct SprintQAError: Error, Equatable, Sendable {
    public let status: Int
}

/// The network layer. Authed calls carry the public widget key, which selects
/// the project and tenant, and a Bearer mobile_widget token, which is the
/// identity. Sprint checks the two belong together.
public final class SprintQAClient: @unchecked Sendable {
    public let origin: URL
    private let widgetKey: String
    private let session: URLSession
    private let lock = NSLock()
    private var _pat: String?

    public init(origin: URL = defaultOrigin, widgetKey: String, pat: String? = nil, session: URLSession = .shared) {
        self.origin = origin
        self.widgetKey = widgetKey
        self._pat = pat
        self.session = session
    }

    public var pat: String? {
        get { lock.withLock { _pat } }
        set { lock.withLock { _pat = newValue } }
    }

    public var hasPat: Bool { isPatShape(pat) }

    // MARK: Routes

    /// Unauthed: only the widget key. `appearance` is the host's override.
    public func config(appearance: AppearanceOverride? = nil) async throws -> WidgetConfig {
        var path = "/api/widget/config"
        if let appearance, let json = String(data: try JSONEncoder().encode(appearance), encoding: .utf8) {
            var q = URLComponents()
            q.queryItems = [URLQueryItem(name: "appearance", value: json)]
            path += "?" + (q.percentEncodedQuery ?? "")
        }
        return try await send(path, authed: false)
    }

    public func me() async throws -> WidgetMe {
        try await send("/api/widget/me")
    }

    public func queue() async throws -> QueueResponse {
        try await send("/api/widget/queue")
    }

    public func report(_ input: ReportInput) async throws -> ReportResponse {
        try await send("/api/widget/report", method: "POST", json: input)
    }

    /// What a tester needs to verify a fix: the task, who fixed it, and the
    /// screenshots, voice notes and demo videos it carries.
    public func taskDetail(taskId: Int) async throws -> TaskDetail {
        try await send("/api/widget/tasks/\(taskId)")
    }

    public func take(taskId: Int) async throws {
        let _: Empty = try await send("/api/widget/tasks/\(taskId)/take", method: "POST")
    }

    public enum Verdict: String, Encodable, Sendable {
        case verified
        case bugFound = "bug_found"
    }

    public func verify(taskId: Int, verdict: Verdict, notes: String? = nil) async throws {
        struct Body: Encodable { let verdict: Verdict; let notes: String? }
        let _: Empty = try await send("/api/widget/tasks/\(taskId)/verify", method: "POST", json: Body(verdict: verdict, notes: notes))
    }

    public enum AttachmentKind: String, Sendable {
        case screenshot
        case annotatedScreenshot = "annotated_screenshot"
        case audioNote = "audio_note"
    }

    /// A screenshot, the marked-up crop (shown first on the task) or a voice note.
    public func uploadAttachment(taskId: Int, kind: AttachmentKind, data: Data, filename: String, mimeType: String) async throws -> AttachmentResponse {
        let boundary = "sprintqa-" + UUID().uuidString
        var body = Data()
        func part(_ header: String, _ content: Data) {
            body.append(Data("--\(boundary)\r\n\(header)\r\n\r\n".utf8))
            body.append(content)
            body.append(Data("\r\n".utf8))
        }
        part("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)", data)
        part("Content-Disposition: form-data; name=\"kind\"", Data(kind.rawValue.utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        return try await send(
            "/api/widget/tasks/\(taskId)/attachments", method: "POST", body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    /// A presigned PUT for a demo video on a task. The bytes go straight to
    /// storage with `put(fileAt:to:)`, never through Sprint.
    public func presignDemoVideo(taskId: Int, filename: String, mimeType: String, sizeBytes: Int) async throws -> PresignResponse {
        struct Body: Encodable { let taskId: Int; let filename: String; let contentType: String; let sizeBytes: Int }
        return try await send("/api/widget/uploads/presign", method: "POST", json: Body(taskId: taskId, filename: filename, contentType: mimeType, sizeBytes: sizeBytes))
    }

    /// Records the uploaded video on the task; Sprint checks its size. Trim
    /// points are seconds the player clamps to; nothing is re-encoded.
    public func recordDemoVideo(taskId: Int, objectKey: String, filename: String, mimeType: String, durationSec: Double? = nil, trimStart: Double? = nil, trimEnd: Double? = nil) async throws -> AttachmentResponse {
        struct Body: Encodable {
            let objectKey: String, filename: String, mimeType: String
            let durationSec: Double?, trimStart: Double?, trimEnd: Double?
            let kind = "demo_video"
        }
        return try await send("/api/widget/tasks/\(taskId)/attachments", method: "POST", json: Body(objectKey: objectKey, filename: filename, mimeType: mimeType, durationSec: durationSec, trimStart: trimStart, trimEnd: trimEnd))
    }

    /// A presigned PUT for a gzipped debug capture.
    public func presignCapture(taskId: Int, sizeBytes: Int) async throws -> PresignResponse {
        struct Body: Encodable { let taskId: Int; let contentType = "application/gzip"; let sizeBytes: Int }
        return try await send("/api/widget/captures/presign", method: "POST", json: Body(taskId: taskId, sizeBytes: max(1, sizeBytes)))
    }

    public struct CaptureRecord: Encodable, Sendable {
        public var taskId: Int
        public var captureObjectKey: String
        public var videoAttachmentId: Int?
        public var startedAtEpochMs: Int64
        public var durationMs: Int
        public var eventCount: Int
        public var telemetryCount: Int
        public var truncated: Bool

        public init(taskId: Int, captureObjectKey: String, videoAttachmentId: Int?, startedAtEpochMs: Int64,
                    durationMs: Int, eventCount: Int, telemetryCount: Int, truncated: Bool) {
            self.taskId = taskId
            self.captureObjectKey = captureObjectKey
            self.videoAttachmentId = videoAttachmentId
            self.startedAtEpochMs = startedAtEpochMs
            self.durationMs = durationMs
            self.eventCount = eventCount
            self.telemetryCount = telemetryCount
            self.truncated = truncated
        }
    }

    /// Links an uploaded capture to the task and, when there is one, its video.
    public func recordCapture(_ record: CaptureRecord) async throws {
        let _: Empty = try await send("/api/widget/captures", method: "POST", json: record)
    }

    /// A presigned PUT for a project demo (the Demo tab), not tied to a task.
    public func presignDemo(filename: String, mimeType: String, sizeBytes: Int) async throws -> PresignResponse {
        struct Body: Encodable { let filename: String; let contentType: String; let sizeBytes: Int }
        return try await send("/api/widget/demos/presign", method: "POST", json: Body(filename: filename, contentType: mimeType, sizeBytes: sizeBytes))
    }

    /// Adds an uploaded demo to the project's library, unpublished to clients.
    public func recordDemo(objectKey: String, filename: String, mimeType: String, durationSec: Double, title: String, description: String? = nil) async throws {
        struct Body: Encodable { let objectKey: String, filename: String, mimeType: String, durationSec: Double, title: String, description: String? }
        let _: Empty = try await send("/api/widget/demos", method: "POST", json: Body(objectKey: objectKey, filename: filename, mimeType: mimeType, durationSec: durationSec, title: title, description: description))
    }

    /// Streams a file to a presigned URL, so a long clip is never held in memory.
    public func put(fileAt file: URL, to uploadUrl: String, mimeType: String) async throws {
        guard let url = URL(string: uploadUrl) else { throw SprintQAError(status: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (_, res) = try await session.upload(for: req, fromFile: file)
        try Self.check(res)
    }

    /// Trades the code from the sign-in redirect for a token, proving the
    /// PKCE verifier. The token never travels in a URL.
    public func exchange(code: String, verifier: String) async throws -> String {
        struct Body: Encodable { let code: String; let verifier: String }
        struct Token: Decodable { let token: String }
        let t: Token = try await send("/api/widget/mobile-auth/exchange", method: "POST", json: Body(code: code, verifier: verifier), authed: false)
        return t.token
    }

    // MARK: Transport

    private struct Empty: Decodable {}

    private func send<T: Decodable>(_ path: String, method: String = "GET", json: (some Encodable)? = nil as String?, authed: Bool = true) async throws -> T {
        let body = try json.map { try JSONEncoder().encode($0) }
        return try await send(path, method: method, body: body, contentType: body == nil ? nil : "application/json", authed: authed)
    }

    private func send<T: Decodable>(_ path: String, method: String, body: Data?, contentType: String?, authed: Bool = true) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw SprintQAError(status: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(widgetKey, forHTTPHeaderField: "X-Widget-Key")
        if authed {
            guard let pat, isPatShape(pat) else { throw SprintQAError(status: 401) }
            req.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        }
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        let (data, res) = try await session.data(for: req)
        try Self.check(res)
        if T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func check(_ res: URLResponse) throws {
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SprintQAError(status: status) }
    }
}
