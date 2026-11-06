#if os(iOS)
import Foundation
import OSLog
import SprintQACore
import UIKit

/// Network, console and screen changes while a bug video records. Best
/// effort throughout: a failure here only means the video ships without its
/// sidecar.
final class DebugCapture: @unchecked Sendable {
    let log = CaptureLog()
    private let console = ConsoleTee()

    init(sprintOrigin: URL) {
        CaptureURLProtocol.begin(log: log, ignoring: sprintOrigin)
        console.start(log)
    }

    /// Ends the capture and returns the gzipped sidecar.
    func finish() -> (payload: CapturePayload, gzip: Data)? {
        CaptureURLProtocol.end()
        console.stop()
        appLogs()
        let device = UIDevice.current
        let payload = log.finish(meta: ["platform": "ios", "osVersion": device.systemVersion, "model": device.model])
        guard let json = try? JSONEncoder().encode(payload), let gz = Gzip.compress(json) else { return nil }
        return (payload, gz)
    }

    /// The host's own Logger and os_log lines from the recording; the
    /// system's frameworks are left out.
    private func appLogs() {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
        let since = store.position(date: log.startedAt)
        guard let entries = try? store.getEntries(at: since) else { return }
        for case let e as OSLogEntryLog in entries {
            guard e.date >= log.startedAt, !e.subsystem.isEmpty, !e.subsystem.hasPrefix("com.apple.") else { continue }
            let level: String
            switch e.level {
            case .error, .fault: level = "error"
            case .notice: level = "warn"
            case .info, .debug: level = "info"
            default: level = "log"
            }
            log.console(level: level, e.composedMessage, at: e.date)
        }
    }
}

/// Copies what the app prints to stdout and stderr into the capture, and
/// still to where it went before.
private final class ConsoleTee {
    private var saved: [(fd: Int32, copy: Int32)] = []
    private var pipes: [Pipe] = []

    func start(_ log: CaptureLog) {
        for (fd, level) in [(STDOUT_FILENO, "log"), (STDERR_FILENO, "error")] {
            let original = dup(fd)
            guard original >= 0 else { continue }
            let pipe = Pipe()
            setvbuf(fd == STDOUT_FILENO ? stdout : stderr, nil, _IOLBF, 0)
            dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
            let out = FileHandle(fileDescriptor: original, closeOnDealloc: false)
            pipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                out.write(data)
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where !line.isEmpty {
                    log.console(level: level, String(line))
                }
            }
            saved.append((fd, original))
            pipes.append(pipe)
        }
    }

    func stop() {
        fflush(stdout)
        fflush(stderr)
        for (fd, original) in saved {
            dup2(original, fd)
            close(original)
        }
        for p in pipes { p.fileHandleForReading.readabilityHandler = nil }
        saved = []
        pipes = []
    }
}

/// Watches URLSession traffic while a capture runs. URLSession.shared is
/// covered once it starts; a host adds it to its own sessions with
/// `SprintQA.captureNetwork(in:)`.
final class CaptureURLProtocol: URLProtocol, URLSessionDataDelegate, @unchecked Sendable {
    private static let handled = "SprintQACaptureHandled"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var log: CaptureLog?
    nonisolated(unsafe) private static var ignored = ""

    static func begin(log: CaptureLog, ignoring origin: URL) {
        lock.lock()
        self.log = log
        ignored = origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/widget"
        lock.unlock()
        URLProtocol.registerClass(CaptureURLProtocol.self)
    }

    static func end() {
        URLProtocol.unregisterClass(CaptureURLProtocol.self)
        lock.lock()
        log = nil
        lock.unlock()
    }

    private static func current(for url: URL?) -> CaptureLog? {
        lock.lock()
        defer { lock.unlock() }
        guard let log, let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        // The widget's own calls are the report being sent, not the bug.
        return url.absoluteString.hasPrefix(ignored) ? nil : log
    }

    override class func canInit(with request: URLRequest) -> Bool {
        property(forKey: handled, in: request) == nil && current(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var session: URLSession?
    private var started = Date()
    private var response: HTTPURLResponse?
    private var bytes = 0

    override func startLoading() {
        guard let copy = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: Self.handled, in: copy)
        started = Date()
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        s.dataTask(with: copy as URLRequest).resume()
    }

    override func stopLoading() {
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytes += data.count
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        if let log = Self.current(for: request.url) {
            let resHeaders = (response?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { $0["\($1.key)".lowercased()] = "\($1.value)" }
            log.network(method: request.httpMethod ?? "GET", url: request.url?.absoluteString ?? "", status: response?.statusCode ?? 0,
                        started: started, resBytes: bytes > 0 ? bytes : nil, reqHeaders: request.allHTTPHeaderFields ?? [:],
                        resHeaders: resHeaders, failed: error != nil)
        }
        session.finishTasksAndInvalidate()
    }
}
#endif
