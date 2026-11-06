#if os(iOS)
import SprintQACore
import UIKit

/// What a report says about the device and app, in Sprint's context shape.
@MainActor
enum DeviceContext {
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if id == "arm64" || id == "x86_64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) Simulator" } ?? "Simulator"
        }
        return id
    }

    static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return nil }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(v) (\($0))" } ?? v
    }

    /// e.g. "SprintQA-iOS/0.2.1 (iPhone17,1; iOS 26.1) com.tapinn.app/4.2 (318)"
    static var userAgent: String {
        let device = UIDevice.current
        var ua = "SprintQA-iOS/\(SprintQA.version) (\(modelIdentifier); \(device.systemName) \(device.systemVersion))"
        if let bundle = Bundle.main.bundleIdentifier { ua += " \(bundle)" + (appVersion.map { "/\($0)" } ?? "") }
        return ua
    }

    static func autoContext(route: String?, window: UIWindow?) -> ReportInput.AutoContext {
        let bounds = window?.bounds ?? UIScreen.main.bounds
        let viewport = ReportInput.AutoContext.Size(w: Int(bounds.width), h: Int(bounds.height))
        let screen = UIScreen.main.bounds
        let tz = TimeZone.current
        let env = ReportInput.AutoContext.Env(
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            appVersion: appVersion,
            deviceModel: modelIdentifier,
            timezone: tz.identifier,
            utcOffset: tz.secondsFromGMT() / 60,
            locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            viewport: viewport,
            screen: .init(w: Int(screen.width), h: Int(screen.height))
        )
        return .init(route: route, viewport: viewport, userAgent: userAgent, env: env)
    }
}
#endif
