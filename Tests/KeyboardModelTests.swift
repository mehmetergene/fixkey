// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import XCTest
@testable import Fixkey

/// The keyboard's logic against a plain-string text field (the app's debug PreviewHost). No network needed.
@MainActor
final class KeyboardModelTests: XCTestCase {
    private let checked = "jeg har ikke mye tid idag"
    private let fixed = "Jeg har ikke meget tid i dag."

    /// The model holds its host weakly, as the extension does; the test keeps them alive.
    private var hosts: [PreviewHost] = []

    private func keyboard(_ text: String) -> (KeyboardModel, PreviewHost) {
        let host = PreviewHost(text: text)
        hosts.append(host)
        let model = KeyboardModel()
        model.host = host
        model.loadLexicon([])
        model.activate()
        return (model, host)
    }

    // MARK: Accepting a check

    func testAcceptAppliesEveryChange() {
        let (model, host) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        model.accept()
        XCTAssertEqual(host.text, fixed)
        XCTAssertEqual(model.check, .idle)
        XCTAssertFalse(model.showsCard)
    }

    func testAcceptLeavesOutTurnedOffChanges() {
        let (model, host) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        model.toggleChange(1)
        guard case .result(let correction) = model.check else { return XCTFail("no result") }
        XCTAssertEqual(correction.appliedCount, correction.changeCount - 1)
        model.accept()
        XCTAssertEqual(host.text, "Jeg har ikke mye tid i dag.")
    }

    func testTurningAChangeBackOnRestoresIt() {
        let (model, host) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        model.toggleChange(2)
        model.toggleChange(2)
        model.accept()
        XCTAssertEqual(host.text, fixed)
    }

    func testNothingChosenChangesNothing() {
        let (model, host) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        guard case .result(let correction) = model.check else { return XCTFail("no result") }
        for change in 0..<correction.changeCount { model.toggleChange(change) }
        model.accept()
        XCTAssertEqual(host.text, checked)
        XCTAssertEqual(model.check, .idle)
    }

    func testAcceptWithTextAfterTheCursor() {
        let (model, host) = keyboard(checked)
        host.moveCursor(by: -8)
        model.showPreviewResult(fixed: fixed, openCard: true)
        model.accept()
        XCTAssertEqual(host.text, fixed)
        XCTAssertEqual(host.textAfterCursor, "")
    }

    func testAcceptRefusesTextThatChangedMeanwhile() {
        let (model, host) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        host.insert("x")
        model.accept()
        XCTAssertEqual(host.text, checked + "x")
        XCTAssertEqual(model.check, .failed("Teksten er ændret – tjek igen"))
    }

    func testTypingDropsAWaitingResult() {
        let (model, _) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: false)
        guard case .result = model.check else { return XCTFail("no result") }
        model.handle(.character("a"))
        XCTAssertEqual(model.check, .idle)
    }

    func testHidingTheCardKeepsTheResult() {
        let (model, _) = keyboard(checked)
        model.showPreviewResult(fixed: fixed, openCard: true)
        model.hideCard()
        XCTAssertFalse(model.showsCard)
        guard case .result = model.check else { return XCTFail("result was dropped") }
        model.iconTapped()
        XCTAssertTrue(model.showsCard)
    }

    // MARK: Typing

    func testCapitalisationAndDoubleSpace() {
        let (model, host) = keyboard("")
        XCTAssertEqual(model.shift, .on)
        for letter in ["h", "e", "j"] { model.handle(.character(letter)) }
        XCTAssertEqual(host.text, "Hej")
        XCTAssertEqual(model.shift, .off)
        model.handle(.space)
        model.handle(.space)
        XCTAssertEqual(host.text, "Hej. ")
        XCTAssertEqual(model.shift, .on)
    }

    func testDeleteWord() {
        let (model, host) = keyboard("Hej med dig")
        model.handle(.deleteWord)
        XCTAssertEqual(host.text, "Hej med ")
        model.handle(.deleteWord)
        XCTAssertEqual(host.text, "Hej ")
    }

    func testBackspaceAndNewline() {
        let (model, host) = keyboard("Hej")
        model.handle(.backspace)
        model.handle(.newline)
        XCTAssertEqual(host.text, "He\n")
        XCTAssertEqual(model.shift, .on)
    }

    // MARK: Messages

    func testEveryFailureHasItsOwnMessage() {
        let failures: [Proofreader.Failure] = [.offline, .macNotFound, .relayNotRunning, .llamaNotRunning, .wrongKey,
                                               .untrustedRelay, .unreachable, .timedOut, .server("x"), .emptyReply,
                                               .truncated, .rejected(.wordsReplaced)]
        let messages = failures.map(KeyboardModel.message(for:))
        XCTAssertEqual(Set(messages).count, failures.count)
        XCTAssertTrue(failures.allSatisfy { $0.errorDescription?.isEmpty == false })
        XCTAssertEqual(failures.filter(\.isConnection), [.offline, .macNotFound, .relayNotRunning, .llamaNotRunning, .unreachable])
    }
}

/// The card's tappable text.
@MainActor
final class ChangesTextTests: XCTestCase {
    private let change = NSAttributedString.Key("FixkeyChange")

    func testEveryChangeIsMarkedAndTappable() {
        let correction = Correction(original: "jeg har ikke mye tid idag", fixed: "Jeg har ikke meget tid i dag.")
        let text = ChangesTextView.text(for: correction, fontSize: 17)
        var marked = Set<Int>()
        text.enumerateAttribute(change, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let value = value as? Int { marked.insert(value) }
        }
        XCTAssertEqual(marked, Set(0..<correction.changeCount))
        XCTAssertTrue(text.string.contains("mye"))
        XCTAssertTrue(text.string.contains("meget"))
    }

    func testTurnedOffChangeShowsTheSuggestionAsLeftOut() {
        var correction = Correction(original: "jeg har ikke mye tid", fixed: "jeg har ikke meget tid")
        correction.toggle(0)
        let text = ChangesTextView.text(for: correction, fontSize: 17)
        let range = (text.string as NSString).range(of: "meget")
        let color = text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
        let traits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(color?.resolvedColor(with: traits), UIColor.tertiaryLabel.resolvedColor(with: traits))
        XCTAssertNotNil(text.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil))
        let kept = (text.string as NSString).range(of: "mye")
        XCTAssertNil(text.attribute(.strikethroughStyle, at: kept.location, effectiveRange: nil))
    }
}
