#if os(iOS)
import Compression
import Network
import XCTest
@testable import SprintQA
@testable import SprintQACore

/// A one-route HTTP server on localhost, so the capture sees a real request.
private final class TinyServer: @unchecked Sendable {
    let listener = try! NWListener(using: .tcp, on: .any)
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    func start() async {
        listener.newConnectionHandler = { c in
            c.start(queue: .global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let body = "{\"ok\":true}"
                let res = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nSet-Cookie: s=abc\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                c.send(content: Data(res.utf8), completion: .contentProcessed { _ in c.cancel() })
            }
        }
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { if case .ready = $0 { k.resume() } }
            listener.start(queue: .global())
        }
    }
}

final class DebugCaptureTests: XCTestCase {
    private struct Payload: Decodable {
        struct Entry: Decodable {
            struct Net: Decodable { let method: String; let url: String; let status: Int; let reqHeaders: [String: String]?; let resHeaders: [String: String]? }
            let kind: String
            let level: String?
            let args: [String]?
            let label: String?
            let data: Net?
        }
        let version: Int
        let telemetry: [Entry]
        let meta: [String: String]
    }

    private func gunzipJSON(_ gz: Data) throws -> Payload {
        // Strip the gzip header and trailer, inflate the raw DEFLATE body.
        let body = gz.dropFirst(10).dropLast(8)
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 << 20)
        defer { out.deallocate() }
        let n = body.withUnsafeBytes { src in
            compression_decode_buffer(out, 1 << 20, src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
        }
        return try JSONDecoder().decode(Payload.self, from: Data(bytes: out, count: n))
    }

    func testCapturesRedactedNetworkConsoleAndScreens() async throws {
        let server = TinyServer()
        await server.start()
        defer { server.listener.cancel() }

        let capture = DebugCapture(sprintOrigin: URL(string: "https://sprint.example.com")!)
        capture.log.navigation("Checkout")
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/api/cart?token=\(String(repeating: "a", count: 8))&page=2")!)
        req.setValue("Bearer secret-value", forHTTPHeaderField: "Authorization")
        req.setValue("trace-1", forHTTPHeaderField: "X-Trace")
        let (_, res) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((res as? HTTPURLResponse)?.statusCode, 200)
        print("cart loaded with eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.abcdefghijk")
        try await Task.sleep(nanoseconds: 300_000_000)

        let finished = try XCTUnwrap(capture.finish())
        let p = try gunzipJSON(finished.gzip)
        XCTAssertEqual(p.version, 2)
        XCTAssertEqual(p.meta["platform"], "ios")

        let net = try XCTUnwrap(p.telemetry.first { $0.kind == "network" }?.data)
        XCTAssertEqual(net.method, "GET")
        XCTAssertEqual(net.status, 200)
        XCTAssertTrue(net.url.contains("token=%E2%80%A2redacted%E2%80%A2"), net.url)
        XCTAssertTrue(net.url.contains("page=2"))
        XCTAssertEqual(net.reqHeaders?["Authorization"], Redact.redacted)
        XCTAssertEqual(net.reqHeaders?["X-Trace"], "trace-1")
        XCTAssertEqual(net.resHeaders?["set-cookie"], Redact.redacted)

        let line = try XCTUnwrap(p.telemetry.first { $0.kind == "console" && ($0.args?.first ?? "").contains("cart loaded") })
        XCTAssertEqual(line.args?.first, "cart loaded with \(Redact.redacted)")
        XCTAssertEqual(p.telemetry.first { $0.kind == "action" }?.label, "/Checkout")

        // Once finished, traffic is no longer intercepted.
        XCTAssertFalse(CaptureURLProtocol.canInit(with: req))
    }

    func testIgnoresTheWidgetsOwnCalls() {
        let capture = DebugCapture(sprintOrigin: URL(string: "https://sprint.example.com")!)
        defer { _ = capture.finish() }
        XCTAssertFalse(CaptureURLProtocol.canInit(with: URLRequest(url: URL(string: "https://sprint.example.com/api/widget/report")!)))
        XCTAssertTrue(CaptureURLProtocol.canInit(with: URLRequest(url: URL(string: "https://api.example.com/v1")!)))
    }
}
#endif
