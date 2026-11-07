// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import CryptoKit
import Foundation

/// Requests to the Mac, shared by the keyboard, the app and the Mac tools.
/// Nothing is kept: no URL cache, cookies or stored credentials. Over HTTPS (the relay), the only certificate
/// trusted is the one whose fingerprint ./fixkey setup built into the app.
enum MacConnection {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    /// Sends `request` and returns the body of a 2xx reply. Every error becomes a `Proofreader.Failure`.
    static func send(_ request: URLRequest) async throws -> Data {
        try await exchange(request).data
    }

    /// Like `send`, with the reply's headers as well.
    static func exchange(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let pin = CertificatePin(expected: FixkeyConfig.relayCertificateSHA256)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: pin)
        } catch {
            throw pin.mismatch ? Proofreader.Failure.untrustedRelay
                : failure(for: error, viaRelay: request.url?.scheme == "https")
        }
        guard let http = response as? HTTPURLResponse else { throw Proofreader.Failure.server("No HTTP response") }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw Proofreader.Failure.wrongKey
        case 502:
            throw Proofreader.Failure.llamaNotRunning
        case 504:
            throw Proofreader.Failure.timedOut
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw Proofreader.Failure.server(message ?? "HTTP \(http.statusCode)")
        }
    }

    /// Checks the whole way to Llama.app (relay, key and certificate included) with its cheapest request.
    /// Returns the model the Mac uses (named by the relay), or the problem.
    static func check(timeout: TimeInterval = 5) async -> Swift.Result<String?, Proofreader.Failure> {
        var request = URLRequest(url: FixkeyConfig.serverURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = timeout
        if let key = FixkeyConfig.apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        do {
            return .success(try await exchange(request).response.value(forHTTPHeaderField: "X-Fixkey-Model"))
        } catch {
            return .failure(error as? Proofreader.Failure ?? .unreachable)
        }
    }

    /// What a network error means for the user. Through the relay, a refused connection means the Mac is there
    /// but the relay isn't running; on the Mac itself it means Llama.app isn't.
    static func failure(for error: Error, viaRelay: Bool) -> Proofreader.Failure {
        guard let error = error as? URLError else { return .unreachable }
        switch error.code {
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .cannotFindHost, .dnsLookupFailed:
            return .macNotFound
        case .cannotConnectToHost:
            return viaRelay ? .relayNotRunning : .llamaNotRunning
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            // Typically a relay from before HTTPS, or a certificate made after this app was built.
            return .untrustedRelay
        default:
            return .unreachable
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Accepts a server only if its certificate's SHA-256 matches the fingerprint from setup.
private final class CertificatePin: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let expected: String?
    /// Set while the request runs; read once it has finished.
    private(set) var mismatch = false

    init(expected: String?) {
        self.expected = expected
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        guard let expected, let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              MacConnection.sha256(SecCertificateCopyData(certificate) as Data) == expected else {
            mismatch = true
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
