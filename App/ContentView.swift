// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var input = ""
    @State private var correction: Correction?
    @State private var error: String?
    @State private var isFixing = false
    @State private var elapsed: TimeInterval?
    @State private var status: ServerStatus = .checking
    @State private var macModel: String?
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    enum ServerStatus: Equatable { case checking, online, problem(Proofreader.Failure) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $input)
                        .frame(minHeight: 110)
                        .accessibilityIdentifier("input")
                        .focused($inputFocused)
                    Button {
                        Task { await fix() }
                    } label: {
                        HStack {
                            Text(isFixing ? "Fixing…" : "Fix grammar")
                            Spacer()
                            if isFixing { ProgressView() }
                        }
                    }
                    .disabled(isFixing || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("fix")
                } header: {
                    Text("Try it")
                } footer: {
                    Text("Uses the same code as the keyboard. The first fix after a few idle minutes is slower while the Mac loads the model.")
                }

                if let correction {
                    Section {
                        if correction.changeCount == 0 {
                            Text(correction.fixed)
                        } else {
                            ChangesText(correction: correction, scrolls: false) { self.correction?.toggle($0) }
                        }
                        Button("Copy") { UIPasteboard.general.string = correction.text }
                    } header: {
                        Text(correction.changeCount == 0 ? "Looks good — no changes" : "Suggestion")
                    } footer: {
                        Text(footer(for: correction))
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section("Turn on the keyboard") {
                    Label("Open Settings › Apps › Fixkey › Keyboards", systemImage: "1.circle")
                    Label("Turn on Fixkey and Allow Full Access", systemImage: "2.circle")
                    Label("In any app, hold 🌐 and choose Fixkey", systemImage: "3.circle")
                    Button("Open Fixkey settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    LabeledContent("Mac", value: FixkeyConfig.usesRelay ? FixkeyConfig.macHost : "This Mac")
                    LabeledContent("Model", value: Self.shortName(macModel ?? FixkeyConfig.model))
                    LabeledContent("Connection", value: FixkeyConfig.usesRelay ? "Encrypted, Wi-Fi only" : "On this Mac")
                    if let worksUntil = Self.worksUntil {
                        LabeledContent("Works until", value: worksUntil.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Status") {
                        switch status {
                        case .checking: ProgressView()
                        case .online: Text("Online").foregroundStyle(.green)
                        case .problem(let failure): Text(Self.title(for: failure)).foregroundStyle(.red)
                        }
                    }
                    if case .problem(let failure) = status, let hint = failure.errorDescription {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Check again") { Task { await checkServer() } }
                } header: {
                    Text("Your Mac")
                } footer: {
                    Text("Text is only sent when you press Fix here or tap the Fixkey icon on the keyboard. It goes only to your Mac and is never stored.\n\nFixkey \(FixkeyConfig.version)")
                }
            }
            .navigationTitle("Fixkey")
            .task {
                #if DEBUG
                // -FixkeyFocusInput YES brings up the current keyboard (used to screenshot Apple's keyboard for reference).
                if UserDefaults.standard.bool(forKey: "FixkeyFocusInput") { inputFocused = true }
                if let demo = UserDefaults.standard.string(forKey: "FixkeyDemoText") {
                    input = demo
                    await fix()
                }
                #endif
                await checkServer()
            }
            .onChange(of: scenePhase) { _, phase in
                // Back from Settings, or after starting the relay: show the current state.
                if phase == .active, status != .checking { Task { await checkServer() } }
            }
        }
    }

    private func fix() async {
        isFixing = true
        error = nil
        correction = nil
        let start = Date()
        let text = input
        do {
            correction = Correction(original: text, fixed: try await Proofreader().fix(text))
            elapsed = Date().timeIntervalSince(start)
        } catch {
            self.error = error.localizedDescription
        }
        isFixing = false
    }

    private func checkServer() async {
        status = .checking
        switch await MacConnection.check() {
        case .success(let model):
            macModel = model
            status = .online
        case .failure(let problem):
            status = .problem(problem)
        }
    }

    /// "unsloth/Qwen3.5-4B-GGUF:Q4_K_M" → "Qwen3.5-4B-GGUF:Q4_K_M"
    /// When this build stops opening (with a free Apple ID, 7 days after it was installed; the Mac renews it), read
    /// from its provisioning profile. nil in the simulator, which has none.
    static let worksUntil: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound],
                                                                       format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    static func shortName(_ model: String) -> String {
        model.components(separatedBy: "/").last ?? model
    }

    private func footer(for correction: Correction) -> String {
        var parts: [String] = []
        if correction.changeCount > 0 {
            parts.append(correction.appliedCount == correction.changeCount
                         ? "Tap a change to leave it out."
                         : "\(correction.appliedCount) of \(correction.changeCount) changes chosen.")
        }
        if let elapsed { parts.append(String(format: "%.1f s", elapsed)) }
        return parts.joined(separator: " ")
    }

    static func title(for failure: Proofreader.Failure) -> String {
        switch failure {
        case .offline: return "No Wi-Fi"
        case .macNotFound: return "Mac not found"
        case .relayNotRunning: return "Relay not listening"
        case .llamaNotRunning: return "Llama.app not running"
        case .wrongKey: return "Wrong key"
        case .untrustedRelay: return "Relay doesn't match"
        case .timedOut: return "No answer"
        default: return "Offline"
        }
    }
}
