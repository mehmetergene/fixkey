// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation

/// Where Fixkey sends text. The simulator and Mac tools talk to Llama.app directly; the iPhone goes
/// through the Wi-Fi relay (Tools/lan-relay) over HTTPS, which only works on the same network as the Mac.
/// Your own values (Mac name, relay key, certificate fingerprint, ports) live in Config/Local.xcconfig, which
/// is not committed. ./fixkey setup writes it.
enum FixkeyConfig {
    static var serverURL: URL {
        #if DEBUG
        // Launch argument override for testing, e.g. -FixkeyServerURL https://my-mac.local:9932
        if let override = UserDefaults.standard.string(forKey: "FixkeyServerURL"), let url = URL(string: override) {
            return url
        }
        #endif
        #if os(iOS) && !targetEnvironment(simulator)
        // Bonjour name, so it keeps working when the router gives the Mac a new IP.
        return URL(string: "https://\(macHost):\(setting("FixkeyRelayPort") ?? "9932")")!
        #else
        return URL(string: "http://127.0.0.1:\(llamaPort)")!
        #endif
    }

    /// The relay is HTTPS; Llama.app on this machine is plain HTTP.
    static var usesRelay: Bool { serverURL.scheme == "https" }

    /// The Mac's Bonjour name, e.g. "Your-MacBook.local".
    static var macHost: String { setting("FixkeyMacHost") ?? "localhost" }

    /// The tested model: Tools/model-eval chose it (2026-10-14) for accuracy, speed and never changing correct text.
    static let recommendedModel = "unsloth/Qwen3.5-4B-GGUF:Q4_K_M"
    /// The model chosen on the Mac (./fixkey model, FIXKEY_MODEL). Through the relay, the Mac's current choice wins.
    static let model = setting("FixkeyModel") ?? recommendedModel
    /// Qwen3.5 thinks by default; thinking takes minutes per sentence, so it stays off.
    static let thinking: Bool? = false
    /// Correction passes per check (2 = re-check once). Set from Tools/model-eval results.
    static let correctionPasses = 1
    /// Send the extra Danish worked examples with every request. Set from Tools/model-eval results.
    static let danishExamples = true
    /// Must match Tools/lan-relay/key.txt. Llama.app itself ignores it.
    static let apiKey: String? = setting("FixkeyAPIKey")
    /// SHA-256 of the relay's certificate (Tools/lan-relay/relay-cert.pem). Over HTTPS, no other certificate is trusted.
    static let relayCertificateSHA256: String? = setting("FixkeyRelayCertSHA256")?.lowercased()
    /// Generous because Llama.app unloads idle models after 5 minutes and reloading takes a few seconds.
    static let timeout: TimeInterval = 45

    /// The version from project.yml, e.g. "0.4.0".
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }

    /// Llama.app's port: read from its own settings when running on the Mac (tools), else from the build settings.
    private static var llamaPort: String {
        #if os(macOS)
        if let port = UserDefaults(suiteName: "app.llama.Llama")?.object(forKey: "serverPort") as? Int { return String(port) }
        #endif
        return setting("FixkeyLlamaPort") ?? "9931"
    }

    /// A value from Info.plist, filled in from Config/*.xcconfig at build time. Empty means not set.
    private static func setting(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
