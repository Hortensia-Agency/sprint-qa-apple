import XCTest
@testable import SprintQACore

final class CaptureTests: XCTestCase {
    private struct Parity: Decodable {
        let redactTokens: [[String]]
        let redactUrl: [[String]]
        let sanitizeHeaders: [[[String: String]]]
        let consoleArg: [[String]]
    }

    /// Sprint writes this from lib/qa/capture-redact.ts; its own test fails when this copy drifts.
    private func parity() throws -> Parity {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try JSONDecoder().decode(Parity.self, from: Data(contentsOf: dir.appendingPathComponent("Fixtures/capture-redact-parity.json")))
    }

    func testTokensMatchTheWeb() throws {
        for c in try parity().redactTokens { XCTAssertEqual(Redact.tokens(c[0]), c[1], c[0]) }
    }

    func testUrlsMatchTheWeb() throws {
        for c in try parity().redactUrl { XCTAssertEqual(Redact.url(c[0]), c[1], c[0]) }
    }

    func testHeadersMatchTheWeb() throws {
        for c in try parity().sanitizeHeaders { XCTAssertEqual(Redact.headers(c[0]), c[1]) }
    }

    func testConsoleMatchesTheWeb() throws {
        for c in try parity().consoleArg { XCTAssertEqual(Redact.consoleArg(c[0]), c[1]) }
    }

    func testLogCapsAndSorts() {
        let start = Date(timeIntervalSince1970: 1000)
        let log = CaptureLog(startedAt: start)
        log.console(level: "log", "second", at: start.addingTimeInterval(2))
        log.console(level: "error", "first", at: start.addingTimeInterval(1))
        let p = log.finish(meta: ["platform": "ios"], at: start.addingTimeInterval(3))
        XCTAssertEqual(p.telemetry.map(\.t), [1000, 2000])
        XCTAssertEqual(p.durationMs, 3000)
        XCTAssertEqual(p.startedAt, 1_000_000)
        XCTAssertFalse(p.truncated)

        for _ in 0...CaptureLog.cap { log.navigation("Home") }
        let full = log.finish(meta: [:])
        XCTAssertTrue(full.truncated)
        XCTAssertEqual(full.telemetryCount, CaptureLog.cap)
    }

    func testCrc32KnownValue() {
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    #if os(macOS)
    func testGzipRoundTripsThroughTheSystemTool() throws {
        let text = String(repeating: "{\"kind\":\"network\",\"url\":\"https://example.com\"}\n", count: 400)
        let gz = try XCTUnwrap(Gzip.compress(Data(text.utf8)))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sprintqa-\(UUID().uuidString).gz")
        try gz.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-dc", file.path]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), text)
        XCTAssertLessThan(gz.count, text.utf8.count / 5)
    }
    #endif
}
