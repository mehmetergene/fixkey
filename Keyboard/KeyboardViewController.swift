// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI
import UIKit

/// Lets keys play the system click, which follows the user's Keyboard Clicks setting (no vibration).
private final class ClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private let model = KeyboardModel()

    override func loadView() {
        view = ClickInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.host = self
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.model.loadLexicon(lexicon.entries.map { (input: $0.userInput, text: $0.documentText) })
        }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        cancelKeyInteractions(in: view)
        super.viewWillDisappear(animated)
    }

    private func cancelKeyInteractions(in view: UIView) {
        if let keys = view as? KeysUIView { keys.cancelInteractions() }
        else { view.subviews.forEach { cancelKeyInteractions(in: $0) } }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The system's edge gestures delay touches near the screen edges; keys must react at once.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.textDidChange()
    }

    // MARK: KeyboardHost

    var textBeforeCursor: String { textDocumentProxy.documentContextBeforeInput ?? "" }
    var textAfterCursor: String { textDocumentProxy.documentContextAfterInput ?? "" }
    var canUseNetwork: Bool { hasFullAccess }
    var showsGlobeKey: Bool { needsInputModeSwitchKey }
    var returnKeyType: UIReturnKeyType { textDocumentProxy.returnKeyType ?? .default }
    var autocapitalization: UITextAutocapitalizationType { textDocumentProxy.autocapitalizationType ?? .sentences }
    var keyboardType: UIKeyboardType { textDocumentProxy.keyboardType ?? .default }
    var autocorrectionType: UITextAutocorrectionType { textDocumentProxy.autocorrectionType ?? .default }
    var spellCheckingType: UITextSpellCheckingType { textDocumentProxy.spellCheckingType ?? .default }
    var hasSelection: Bool { !(textDocumentProxy.selectedText ?? "").isEmpty }
    var documentIdentifier: UUID { textDocumentProxy.documentIdentifier }

    func insert(_ text: String) { textDocumentProxy.insertText(text) }
    func deleteBackward() { textDocumentProxy.deleteBackward() }
    /// `offset` is in characters as Swift counts them; UIKit moves in UTF-16 units, where an emoji counts 2+.
    func moveCursor(by offset: Int) {
        let units: Int
        if offset >= 0 {
            units = String(textAfterCursor.prefix(offset)).utf16.count + max(0, offset - textAfterCursor.count)
        } else {
            units = -(String(textBeforeCursor.suffix(-offset)).utf16.count + max(0, -offset - textBeforeCursor.count))
        }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: units)
    }
    func nextKeyboard() { advanceToNextInputMode() }
}
