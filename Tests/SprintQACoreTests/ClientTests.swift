import XCTest
@testable import SprintQACore

/// Answers every request from `handler` and records what was sent.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            req.httpBody = data
        }
        Self.seen.append(req)
        let (status, body) = Self.handler?(req) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    let pat = "sprint_pat_" + String(repeating: "b", count: 32)
    var client: SprintQAClient!

    override func setUp() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        client = SprintQAClient(origin: URL(string: "https://sprint.test")!, widgetKey: "pk_qa_k", pat: pat, session: URLSession(configuration: cfg))
        StubProtocol.seen = []
    }

    func testSendsTheKeyAndToken() async throws {
        StubProtocol.handler = { _ in (200, try! fixture("me")) }
        _ = try await client.me()
        let req = StubProtocol.seen[0]
        XCTAssertEqual(req.url?.absoluteString, "https://sprint.test/api/widget/me")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Widget-Key"), "pk_qa_k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(pat)")
    }

    func testConfigIsUnauthedAndCarriesTheOverride() async throws {
        StubProtocol.handler = { _ in (200, try! fixture("config")) }
        _ = try await client.config(appearance: AppearanceOverride(theme: "dark"))
        let req = StubProtocol.seen[0]
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(req.url?.query, "appearance=%7B%22theme%22:%22dark%22%7D")
    }

    func testAnyFailureIsOnlyAStatus() async {
        StubProtocol.handler = { _ in (404, Data(#"{"error":"nope"}"#.utf8)) }
        do {
            _ = try await client.queue()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? SprintQAError, SprintQAError(status: 404))
        }
    }

    func testNoTokenNeverReachesTheNetwork() async {
        client.pat = nil
        do {
            _ = try await client.me()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? SprintQAError, SprintQAError(status: 401))
            XCTAssertTrue(StubProtocol.seen.isEmpty)
        }
    }

    func testUploadsAMultipartAttachment() async throws {
        StubProtocol.handler = { _ in (201, Data(#"{"id":4,"sizeBytes":3,"mimeType":"image/png"}"#.utf8)) }
        let r = try await client.uploadAttachment(taskId: 7, kind: .annotatedScreenshot, data: Data([1, 2, 3]), filename: "a.png", mimeType: "image/png")
        XCTAssertEqual(r.id, 4)
        let req = StubProtocol.seen[0]
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"kind\"\r\n\r\nannotated_screenshot"))
        XCTAssertTrue(body.contains("filename=\"a.png\""))
    }

    func testExchangeIsUnauthed() async throws {
        StubProtocol.handler = { _ in (200, Data(#"{"token":"sprint_pat_t"}"#.utf8)) }
        client.pat = nil
        let token = try await client.exchange(code: "c", verifier: "v")
        XCTAssertEqual(token, "sprint_pat_t")
        let sent = try JSONDecoder().decode([String: String].self, from: StubProtocol.seen[0].httpBody!)
        XCTAssertEqual(sent, ["code": "c", "verifier": "v"])
    }
}

private func fixture(_ name: String) throws -> Data {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: dir.appendingPathComponent("Fixtures/\(name).json"))
}

final class TaskDetailDecodingTests: XCTestCase {
    /// The shape GET /api/widget/tasks/:id answers with, trimmed to what the widget reads plus extras it must ignore.
    func testDecodesTheDetailRoute() throws {
        let json = """
        {"task":{"id":41,"title":"Wrong coach","state":"deployed","description":null,"projectId":6,"tenantId":"t"},
         "transitions":[],"comments":[],"verifications":[],"activeVerifiedCount":1,
         "fixer":{"name":"Ada","login":"ada","avatar":null,"via":"commit"},
         "screenshots":[{"id":1,"filename":"annotated-screenshot.png","url":"https://s/1"}],
         "audioNotes":[{"id":2,"filename":"voice-note.m4a","mimeType":"audio/mp4","url":"https://s/2",
           "transcript":{"state":"parked","text":null,"parkReason":"over_cap","failedReason":null}}],
         "demoVideos":[{"id":3,"filename":"demo.mp4","mimeType":"video/mp4","url":"https://s/3"}],
         "reproContext":{"reproUrl":null,"bugBuildSha":null,"fixBranch":"main","fixCommitSha":"abc","staleEnvRetest":true,"staleEnvRetestReason":null}}
        """
        let d = try JSONDecoder().decode(TaskDetail.self, from: Data(json.utf8))
        XCTAssertEqual(d.task.title, "Wrong coach")
        XCTAssertNil(d.task.description)
        XCTAssertEqual(d.activeVerifiedCount, 1)
        XCTAssertEqual(d.fixer?.name, "Ada")
        XCTAssertEqual(d.audioNotes?.first?.transcript?.parkReason, "over_cap")
        XCTAssertEqual(d.demoVideos?.first?.url, "https://s/3")
        XCTAssertEqual(d.reproContext?.staleEnvRetest, true)
    }
}
