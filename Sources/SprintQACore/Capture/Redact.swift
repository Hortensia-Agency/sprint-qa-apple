import Foundation

/// The web's capture redaction (lib/qa/capture-redact.ts in Sprint), held to
/// it by a shared fixture. Auth headers are always masked, sensitive query
/// values and token-shaped strings redacted, bodies never kept.
public enum Redact {
    public static let redacted = "•redacted•"

    static let stringCap = 2000
    static let headerValueCap = 1024

    private static let sensitiveHeader = try! NSRegularExpression(
        pattern: "^(authorization|cookie|set-cookie|proxy-authorization|x-api-key|x-auth-token|x-access-token|x-csrf-token|x-xsrf-token|x-session-token)$",
        options: .caseInsensitive)
    private static let sensitiveParam = try! NSRegularExpression(
        pattern: "(token|secret|password|passwd|pwd|api[-_]?key|apikey|auth|session|access[-_]?token|refresh[-_]?token|id[-_]?token|code|signature|sig)",
        options: .caseInsensitive)
    private static let tokenLike = try! NSRegularExpression(
        pattern: "(eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{4,}|[A-Za-z0-9_-]{32,})")

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Token-shaped runs (JWTs, long opaque strings) anywhere in a string.
    public static func tokens(_ s: String) -> String {
        tokenLike.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: NSRegularExpression.escapedTemplate(for: redacted))
    }

    /// Origin and path kept, sensitive query values redacted, the fragment
    /// dropped (fragments carry OAuth tokens). The query is re-serialized the
    /// way URLSearchParams does it.
    public static func url(_ raw: String) -> String {
        let noHash = String(raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let parts = noHash.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var head = String(parts[0])
        let query = parts.count > 1 ? String(parts[1]) : ""
        if let scheme = head.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) {
            let rest = head[scheme.upperBound...]
            let slash = rest.firstIndex(of: "/") ?? rest.endIndex
            var authority = String(rest[..<slash])
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            let proto = head[..<scheme.upperBound].lowercased()
            authority = authority.lowercased()
            if (proto == "http://" && authority.hasSuffix(":80")) || (proto == "https://" && authority.hasSuffix(":443")) {
                authority = String(authority[..<authority.lastIndex(of: ":")!])
            }
            let path = rest[slash...]
            head = proto + authority + (path.isEmpty ? "/" : path)
        } else if !head.hasPrefix("/") {
            head = "/" + head
        }
        let pairs: [(String, String)] = query.split(separator: "&").map { piece in
            let kv = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = formDecode(String(kv[0]))
            let value = kv.count > 1 ? formDecode(String(kv[1])) : ""
            return (key, matches(sensitiveParam, key) ? redacted : value)
        }
        let serialized = pairs.map { formEncode($0.0) + "=" + formEncode($0.1) }.joined(separator: "&")
        return serialized.isEmpty ? head : head + "?" + serialized
    }

    /// Auth-bearing headers become a mask; the rest are token-redacted and capped.
    public static func headers(_ h: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in h {
            out[k] = matches(sensitiveHeader, k) ? redacted : cap(tokens(v), headerValueCap)
        }
        return out
    }

    public static func consoleArg(_ s: String) -> String {
        cap(tokens(s), stringCap)
    }

    /// JavaScript's slice counts UTF-16 units; so does this.
    static func cap(_ s: String, _ n: Int) -> String {
        guard s.utf16.count > n else { return s }
        let end = s.utf16.index(s.utf16.startIndex, offsetBy: n)
        return String(s.utf16[..<end]) ?? String(s.prefix(n))
    }

    private static func formDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    private static let formSafe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._".utf8)

    private static func formEncode(_ s: String) -> String {
        var out = ""
        for byte in s.utf8 {
            if byte == 0x20 { out += "+" }
            else if formSafe.contains(byte) { out.unicodeScalars.append(UnicodeScalar(byte)) }
            else { out += String(format: "%%%02X", byte) }
        }
        return out
    }
}
