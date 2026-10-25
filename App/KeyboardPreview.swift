// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

#if DEBUG
import SwiftUI
import UIKit

/// Debug-only: shows the keyboard inside the app, backed by a plain string, so it can be screenshotted
/// in the simulator without enabling the keyboard.
/// Launch with `-FixkeyKeyboardPreview letters|capitals|numbers|strip|card|card-choice|suggestions`.
@MainActor
final class PreviewHost: ObservableObject, KeyboardHost {
    @Published private(set) var text: String
    @Published private(set) var cursor: Int

    init(text: String) {
        self.text = text
        cursor = text.count
    }

    var textBeforeCursor: String { String(text.prefix(cursor)) }
    var textAfterCursor: String { String(text.dropFirst(cursor)) }
    var canUseNetwork: Bool { true }
    var showsGlobeKey: Bool { false }
    var returnKeyType: UIReturnKeyType { .default }
    var autocapitalization: UITextAutocapitalizationType { .sentences }
    var keyboardType: UIKeyboardType { .default }
    var autocorrectionType: UITextAutocorrectionType { .default }
    var spellCheckingType: UITextSpellCheckingType { .default }
    var hasSelection: Bool { false }
    let documentIdentifier = UUID()

    // Recount from the new prefix: "\r" + "\n" or e + combining accent merge into one Character.
    func insert(_ text: String) {
        let prefix = textBeforeCursor + text
        self.text = prefix + textAfterCursor
        cursor = prefix.count
    }
    func deleteBackward() {
        guard cursor > 0 else { return }
        let prefix = String(textBeforeCursor.dropLast())
        text = prefix + textAfterCursor
        cursor = prefix.count
    }
    func moveCursor(by offset: Int) {
        let next = min(text.count, max(0, cursor + offset))
        if cursor != next { cursor = next }
    }
    func reset(_ text: String) {
        self.text = text
        cursor = text.count
    }
    func nextKeyboard() {}
}

struct KeyboardPreviewScreen: View {
    static let checked = "hej, kommer du komme morgen? jeg har ikke mye tid idag"
    static let fixed = "Hej, kommer du i morgen? Jeg har ikke meget tid i dag."
    let mode: String
    @StateObject private var host = PreviewHost(text: "Jeg har lavet en fejl i den her sætning ikke")
    @StateObject private var model = KeyboardModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(host.textBeforeCursor + "|" + host.textAfterCursor)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            KeyboardView(model: model)
                .frame(height: KeyboardView.height)
                .padding(.bottom, 24)
                .background(scheme == .dark ? Color(white: 0.17) : Color(red: 0.82, green: 0.83, blue: 0.86))
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            switch mode {
            case "suggestions": host.reset("Jeg har brug for hjæl")
            case "capitals": host.reset("")
            case "card", "card-choice", "strip": host.reset(Self.checked)
            default: break
            }
            model.host = host
            model.loadLexicon([])
            model.activate()
            switch mode {
            case "numbers": model.page = .numbers
            case "card", "card-choice", "strip":
                // card-choice: one change turned off, as after tapping "meget" in the card.
                model.showPreviewResult(fixed: Self.fixed, openCard: mode != "strip",
                                        rejecting: mode == "card-choice" ? [3] : [])
            default: break
            }
        }
        .task {
            guard mode == "suggestions" else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            // Simulator dictionaries can omit Danish; keep this screenshot mode useful there too.
            if host.textBeforeCursor == "Jeg har brug for hjæl", model.suggestions.state.alternatives.isEmpty {
                model.suggestions.show(.init(typed: "hjæl", alternatives: ["hjælp", "hjælpe"]))
            }
        }
        .onDisappear { model.deactivate() }
    }
}
#endif
