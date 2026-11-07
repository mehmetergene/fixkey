// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI
import UIKit

/// What the keyboard needs from its text field. The extension's view controller implements it;
/// the app's debug preview implements it with a plain string.
@MainActor
protocol KeyboardHost: AnyObject {
    var textBeforeCursor: String { get }
    var textAfterCursor: String { get }
    var canUseNetwork: Bool { get }
    var showsGlobeKey: Bool { get }
    var returnKeyType: UIReturnKeyType { get }
    var autocapitalization: UITextAutocapitalizationType { get }
    var keyboardType: UIKeyboardType { get }
    var autocorrectionType: UITextAutocorrectionType { get }
    var spellCheckingType: UITextSpellCheckingType { get }
    var hasSelection: Bool { get }
    var documentIdentifier: UUID { get }
    func insert(_ text: String)
    func deleteBackward()
    func moveCursor(by offset: Int)
    func nextKeyboard()
}

@MainActor
final class KeyboardModel: ObservableObject {
    enum Page { case letters, numbers, symbols }
    enum Shift { case off, on, locked }
    enum Check: Equatable {
        case idle
        case checking
        case result(Correction)
        case clean
        /// `offline`: the Mac can't be reached at all, so the icon shows it.
        case failed(String, offline: Bool = false)
    }

    @Published var page: Page = .letters
    @Published private(set) var shift: Shift = .on
    @Published var check: Check = .idle
    @Published var showsCard = false
    @Published private var traits = Traits()
    let suggestions = WordSuggestions()

    private struct Traits: Equatable {
        var showsGlobe = false
        var returnKey: UIReturnKeyType = .default
    }

    private func setShift(_ value: Shift) {
        if shift != value { shift = value }
    }

    weak var host: KeyboardHost?
    private var task: Task<Void, Never>?
    private var lastShiftTap: Date?
    private var lastSpaceTap: Date?
    private var suggestionTask: Task<Void, Never>?
    private var interacting = false
    private var active = true

    private struct Edit {
        let word: KeyboardWord
        let replacement: String
        let separator: String
        let before: String
        let after: String
        let document: UUID?
    }

    private var correction: Edit?
    private var boundary: Edit?

    /// What a grammar check was run on: the full visible context (to detect edits) and the part actually checked.
    private struct CheckSnapshot {
        let before: String
        let after: String
        let checkedAfter: String
        let document: UUID
    }
    private var checkSnapshot: CheckSnapshot?

    private func snapshotMatches() -> Bool {
        guard let snapshot = checkSnapshot, let host else { return false }
        return host.documentIdentifier == snapshot.document && !host.hasSelection
            && host.textBeforeCursor == snapshot.before && host.textAfterCursor == snapshot.after
    }

    private var allowsSuggestions: Bool {
        guard let host, host.autocorrectionType != .no, host.spellCheckingType != .no else { return false }
        return ![UIKeyboardType.URL, .emailAddress, .webSearch, .twitter].contains(host.keyboardType)
    }

    private var currentWord: KeyboardWord? {
        guard allowsSuggestions, let host else { return nil }
        return KeyboardWord(before: host.textBeforeCursor, after: host.textAfterCursor, hasSelection: host.hasSelection)
    }

    private func stillMatches(_ edit: Edit) -> Bool {
        guard let host else { return false }
        return !host.hasSelection && host.documentIdentifier == edit.document
            && host.textBeforeCursor == edit.before && host.textAfterCursor == edit.after
    }

    private var currentText: String {
        guard let host else { return "" }
        return host.textBeforeCursor + host.textAfterCursor
    }

    var showsGlobeKey: Bool { traits.showsGlobe }

    var returnLabel: String {
        switch traits.returnKey {
        case .go: return "gå"
        case .google, .yahoo, .search: return "søg"
        case .join: return "tilmeld"
        case .next: return "næste"
        case .route: return "rute"
        case .send: return "send"
        case .done: return "færdig"
        case .emergencyCall: return "nødopkald"
        case .continue: return "fortsæt"
        default: return "retur"
        }
    }

    var returnIsProminent: Bool { traits.returnKey != .default }

    // MARK: Typing

    func type(_ text: String) {
        if text.count == 1, ".,?!:;".contains(text) {
            insertBoundary(text)
        } else {
            correction = nil
            boundary = nil
            host?.insert(text)
        }
        lastSpaceTap = nil
        textDidChange()
    }

    func space() {
        guard let host else { return }
        let before = host.textBeforeCursor
        let now = Date()
        correction = nil
        boundary = nil
        // Double space after a word types ". ", like the system keyboard.
        if let last = lastSpaceTap, now.timeIntervalSince(last) < 0.45, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            host.deleteBackward()
            host.insert(". ")
            lastSpaceTap = nil
        } else {
            insertBoundary(" ")
            lastSpaceTap = now
        }
        if page != .letters { page = .letters }
        textDidChange()
    }

    func returnKey() {
        type("\n")
    }

    func backspace() {
        if !restoreCorrection(keepingSeparator: false) { host?.deleteBackward() }
        boundary = nil
        lastSpaceTap = nil
        textDidChange()
    }

    /// Repeated deletion is one edit for prediction purposes, even when it removes a whole word.
    func deleteWord() {
        guard let host else { return }
        correction = nil
        boundary = nil
        lastSpaceTap = nil
        var text = host.textBeforeCursor[...]
        let originalCount = text.count
        while text.last?.isWhitespace == true { text.removeLast() }
        if let last = text.last {
            if last.isLetter || last.isNumber {
                while let last = text.last, last.isLetter || last.isNumber || "'’-".contains(last) { text.removeLast() }
            } else {
                text.removeLast()
            }
        }
        // With unavailable context, keep the system's ordinary delete behaviour.
        for _ in 0..<max(1, originalCount - text.count) { host.deleteBackward() }
        textDidChange()
    }

    func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        correction = nil
        boundary = nil
        lastSpaceTap = nil
        host?.moveCursor(by: offset)
        textDidChange()
    }

    func keyInteractionChanged(_ active: Bool) {
        guard interacting != active else { return }
        interacting = active
        if active, boundary == nil { suggestionTask?.cancel() } else { refreshSuggestions() }
    }

    func activate() {
        active = true
        textDidChange()
    }

    func deactivate() {
        if check == .checking { cancelCheck() }
        active = false
        interacting = false
        suggestionTask?.cancel()
        correction = nil
        boundary = nil
        lastSpaceTap = nil
        if suggestions.hasPendingLearning {
            Task { [suggestions] in
                await Task.yield()
                suggestions.flushLearning()
            }
        }
    }

    func loadLexicon(_ entries: [(input: String, text: String)]) {
        suggestions.loadLexicon(entries)
        refreshSuggestions()
    }

    func chooseSuggestion(_ slot: Int) {
        guard allowsSuggestions else { return }
        if slot == 0, restoreCorrection(keepingSeparator: true) {
            lastSpaceTap = nil
            textDidChange()
            return
        }
        guard let word = currentWord, word.text == suggestions.state.typed else { return }
        correction = nil
        boundary = nil
        if slot == 0 {
            suggestions.learn(word.text)
            host?.insert(" ")
        } else {
            let index = slot - 1
            guard suggestions.state.alternatives.indices.contains(index) else { return }
            replaceSuffix(word.text, with: suggestions.state.alternatives[index] + " ")
        }
        lastSpaceTap = nil
        if page != .letters { page = .letters }
        textDidChange()
    }

    private func insertBoundary(_ separator: String) {
        guard let host else { return }
        correction = nil
        boundary = nil
        let word = currentWord
        let replacement = word.flatMap { word in
            separator == " " ? suggestions.replacement(for: word) ?? suggestions.cached(for: word)?.automatic
                : suggestions.cached(for: word)?.automatic
        }
        if let word, let replacement {
            replaceSuffix(word.text, with: replacement)
            host.insert(separator)
            correction = edit(word, replacement: replacement, separator: separator)
        } else {
            host.insert(separator)
            if let word { boundary = edit(word, replacement: word.text, separator: separator) }
        }
    }

    private func edit(_ word: KeyboardWord, replacement: String, separator: String) -> Edit {
        Edit(word: word, replacement: replacement, separator: separator,
             before: host?.textBeforeCursor ?? "", after: host?.textAfterCursor ?? "", document: host?.documentIdentifier)
    }

    @discardableResult
    private func replaceSuffix(_ suffix: String, with text: String) -> Bool {
        guard let host, host.textBeforeCursor.hasSuffix(suffix), !host.hasSelection else { return false }
        for _ in suffix { host.deleteBackward() }
        host.insert(text)
        return true
    }

    @discardableResult
    private func restoreCorrection(keepingSeparator: Bool) -> Bool {
        guard let correction, stillMatches(correction),
              host?.textBeforeCursor.hasSuffix(correction.replacement + correction.separator) == true else {
            correction = nil
            return false
        }
        self.correction = nil
        suggestions.learn(correction.word.text)
        replaceSuffix(correction.replacement + correction.separator,
                      with: correction.word.text + (keepingSeparator ? correction.separator : ""))
        return true
    }

    private func refreshSuggestions() {
        suggestionTask?.cancel()
        guard active else { return }
        guard allowsSuggestions else {
            correction = nil
            boundary = nil
            suggestions.show(.init())
            return
        }
        if let correction {
            suggestions.show(.init(typed: correction.word.text, isUndo: true))
            return
        }
        let word = boundary?.word ?? currentWord
        if boundary != nil {
            suggestions.show(.init())
        } else if let word {
            let result = suggestions.cached(for: word)
            suggestions.show(.init(typed: word.text, alternatives: result?.alternatives ?? [], automatic: result?.automatic))
        } else {
            suggestions.show(.init())
        }
        let atBoundary = boundary != nil
        guard !interacting || atBoundary, word != nil || suggestions.hasPendingLearning else { return }
        suggestionTask = Task { [weak self] in
            // A completed word gets the next idle turn, including during two-thumb rollover.
            if atBoundary { await Task.yield() }
            else { do { try await Task.sleep(for: .milliseconds(45)) } catch { return } }
            guard let self, !Task.isCancelled else { return }
            suggestions.flushLearning()
            guard let word else { return }
            let result = suggestions.lookup(word)
            if let boundary, stillMatches(boundary) {
                self.boundary = nil
                if let replacement = result.automatic,
                   replaceSuffix(word.text + boundary.separator, with: replacement + boundary.separator) {
                    correction = edit(word, replacement: replacement, separator: boundary.separator)
                    textDidChange()
                }
            } else if currentWord == word {
                suggestions.show(.init(typed: word.text, alternatives: result.alternatives, automatic: result.automatic))
            }
        }
    }

    func tapShift() {
        let now = Date()
        if shift == .locked {
            setShift(.off)
        } else if let last = lastShiftTap, now.timeIntervalSince(last) < 0.35 {
            setShift(.locked)
        } else {
            setShift(shift == .on ? .off : .on)
        }
        lastShiftTap = now
    }

    func show(_ page: Page) {
        if self.page != page { self.page = page }
    }

    func handle(_ action: KeyAction) {
        guard active else { return }
        switch action {
        case .character(let text):
            // Rollover can commit two touches before SwiftUI has delivered the new shift state.
            type(page == .letters ? (shift == .off ? text.lowercased() : text.uppercased()) : text)
        case .shift: tapShift()
        case .backspace: backspace()
        case .deleteWord: deleteWord()
        case .moveCursor(let offset): moveCursor(by: offset)
        case .page(let page): show(page)
        case .globe: nextKeyboard()
        case .space: space()
        case .newline: returnKey()
        }
    }

    func nextKeyboard() {
        deactivate()
        host?.nextKeyboard()
    }

    /// Called after every edit, ours or the text field's.
    func textDidChange() {
        let newTraits = Traits(showsGlobe: host?.showsGlobeKey ?? false, returnKey: host?.returnKeyType ?? .default)
        if traits != newTraits { traits = newTraits }
        if let correction, !stillMatches(correction) { self.correction = nil }
        if let boundary, !stillMatches(boundary) { self.boundary = nil }
        updateShift()
        invalidateCheckIfNeeded()
        refreshSuggestions()
    }

    private func updateShift() {
        guard shift != .locked, let host else { return }
        setShift(shouldCapitalize(host) ? .on : .off)
    }

    private func shouldCapitalize(_ host: KeyboardHost) -> Bool {
        let before = host.textBeforeCursor
        switch host.autocapitalization {
        case .none: return false
        case .allCharacters: return true
        case .words: return before.isEmpty || before.last?.isWhitespace == true
        default:
            if before.isEmpty || before.hasSuffix("\n") { return true }
            guard before.last == " " else { return false }
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || [".", "!", "?"].contains(trimmed.last)
        }
    }

    // MARK: Checking

    func iconTapped() {
        switch check {
        case .result: showsCard = true
        case .checking: cancelCheck()
        default: runCheck()
        }
    }

    private func runCheck() {
        guard let host else { return }
        // An idle correction must not change the snapshot while the grammar request is in flight.
        suggestionTask?.cancel()
        boundary = nil
        guard host.canUseNetwork else {
            check = .failed("Slå »Tillad fuld adgang« til i Indstillinger")
            return
        }
        // Selected text is not part of the context iOS shares, so Accept could replace the wrong characters.
        guard !host.hasSelection else {
            check = .failed("Fjern markeringen først")
            return
        }
        let (before, after) = (host.textBeforeCursor, host.textAfterCursor)
        let checked = CheckRange.around(before: before, after: after)
        let original = checked.before + checked.after
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            check = .failed("Skriv noget først")
            return
        }
        checkSnapshot = CheckSnapshot(before: before, after: after, checkedAfter: checked.after,
                                      document: host.documentIdentifier)
        check = .checking
        task = Task {
            do {
                let fixed = try await Proofreader().fix(original)
                guard !Task.isCancelled else { return }
                // The text changed while waiting: this result describes text that no longer exists.
                guard snapshotMatches() else { cancelCheck(); return }
                if fixed == original {
                    check = .clean
                } else {
                    check = .result(Correction(original: original, fixed: fixed))
                    showsCard = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard snapshotMatches() else { cancelCheck(); return }
                check = .failed(Self.message(for: error), offline: (error as? Proofreader.Failure)?.isConnection == true)
            }
        }
    }

    private func cancelCheck() {
        task?.cancel()
        task = nil
        checkSnapshot = nil
        showsCard = false
        check = .idle
    }

    /// Turns one change of the card on or off.
    func toggleChange(_ change: Int) {
        guard case .result(var correction) = check else { return }
        correction.toggle(change)
        check = .result(correction)
    }

    func accept() {
        guard case .result(let correction) = check, let host, let snapshot = checkSnapshot else { return }
        guard correction.appliedCount > 0 else { return dismiss() }
        guard snapshotMatches() else {
            showsCard = false
            check = .failed("Teksten er ændret – tjek igen")
            return
        }
        // Move the cursor to the end of the checked text, delete it, insert the fix with the chosen changes.
        if !snapshot.checkedAfter.isEmpty { host.moveCursor(by: snapshot.checkedAfter.count) }
        for _ in 0..<correction.original.count { host.deleteBackward() }
        host.insert(correction.text)
        showsCard = false
        check = .idle
        checkSnapshot = nil
        self.correction = nil
        boundary = nil
        textDidChange()
    }

    #if DEBUG
    /// Preview only: show a result for the current text as if a check had returned `fixed`.
    func showPreviewResult(fixed: String, openCard: Bool, rejecting rejected: Set<Int> = []) {
        guard let host else { return }
        checkSnapshot = CheckSnapshot(before: host.textBeforeCursor, after: host.textAfterCursor,
                                      checkedAfter: host.textAfterCursor, document: host.documentIdentifier)
        var correction = Correction(original: host.textBeforeCursor + host.textAfterCursor, fixed: fixed)
        rejected.forEach { correction.toggle($0) }
        check = .result(correction)
        showsCard = openCard
    }
    #endif

    func dismiss() {
        showsCard = false
        check = .idle
        checkSnapshot = nil
    }

    /// Back to the keys without dropping the suggestion; the badge keeps it reachable.
    func hideCard() {
        showsCard = false
    }

    private func invalidateCheckIfNeeded() {
        switch check {
        case .checking, .result:
            if !snapshotMatches() { cancelCheck() }
        case .clean, .failed:
            check = .idle
        case .idle:
            break
        }
    }

    /// Short Danish messages for the strip: what went wrong and, where it helps, what to do on the Mac.
    static func message(for error: Error) -> String {
        switch error as? Proofreader.Failure {
        case .offline?: return "iPhonen er ikke på Wi-Fi"
        case .macNotFound?: return "Kan ikke finde din Mac – er den tændt og på samme Wi-Fi?"
        case .relayNotRunning?: return "Relæet lytter ikke – kør ./fixkey doctor på din Mac"
        case .llamaNotRunning?: return "Llama.app kører ikke – åbn den på din Mac"
        case .wrongKey?: return "Forkert nøgle – kør ./fixkey reinstall på din Mac"
        case .untrustedRelay?: return "Relæet passer ikke til appen – kør ./fixkey doctor på din Mac"
        case .unreachable?: return "Kan ikke nå din Mac"
        case .timedOut?: return "Det tog for lang tid – prøv igen"
        case .server?: return "Fejl fra serveren"
        case .emptyReply?: return "Intet svar fra modellen"
        case .truncated?: return "Teksten er for lang til ét tjek"
        case .rejected?: return "Ingen sikker rettelse"
        case nil: return "Noget gik galt"
        }
    }
}
