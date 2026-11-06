#if os(iOS)
import AuthenticationServices
import SprintQACore
import UIKit

/// "Sign in with Sprint": an ASWebAuthenticationSession on Sprint's start
/// route, PKCE, then the code is exchanged for this device's token. The
/// redirect comes back to this app only, so another app registering the same
/// scheme can't take it.
@MainActor
final class SignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Outcome: Equatable {
        case token(String)
        /// A code from Sprint, "cancelled", or "network".
        case failed(String)
    }

    private var session: ASWebAuthenticationSession?

    func run(client: SprintQAClient, widgetKey: String, scheme: String, deviceId: String) async -> Outcome {
        let pkce = PKCE()
        let url = SignIn.startURL(
            origin: client.origin, widgetKey: widgetKey, redirect: "\(scheme)://sprint-qa",
            deviceId: deviceId, challenge: pkce.challenge
        )
        let callback: URL
        do {
            callback = try await open(url, scheme: scheme)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            return .failed("cancelled")
        } catch {
            return .failed("signin_failed")
        }
        switch SignIn.parse(callback) {
        case .error(let e):
            return .failed(e)
        case .code(let code):
            do {
                return .token(try await client.exchange(code: code, verifier: pkce.verifier))
            } catch is SprintQAError {
                return .failed("exchange_failed")
            } catch {
                return .failed("network")
            }
        }
    }

    private func open(_ url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let done: (URL?, Error?) -> Void = { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin)) }
            }
            let s: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                s = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: done)
            } else {
                s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: done)
            }
            s.presentationContextProvider = self
            session = s
            if !s.start() { cont.resume(throwing: ASWebAuthenticationSessionError(.presentationContextInvalid)) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
#endif
