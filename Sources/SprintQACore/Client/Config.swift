import Foundation

public let defaultOrigin = URL(string: "https://sprint.hortensia-agency.com")!

private let patPrefix = "sprint_pat_"

/// Cheap shape check before sending, the same as Sprint's isPatShape.
public func isPatShape(_ s: String?) -> Bool {
    guard let s else { return false }
    return s.hasPrefix(patPrefix) && s.count == patPrefix.count + 32
}

/// A route matches a hidden entry exactly, or through `*` wildcards.
public func routeHidden(_ route: String?, _ hiddenRoutes: [String]?) -> Bool {
    guard let route, let hiddenRoutes else { return false }
    return hiddenRoutes.contains { pattern in
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map { NSRegularExpression.escapedPattern(for: String($0)) }
        let regex = "^" + parts.joined(separator: ".*") + "$"
        return route.range(of: regex, options: .regularExpression) != nil
    }
}
