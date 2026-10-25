// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI
import UIKit

/// The checked text with every change marked: removed words struck through in red, added words in green.
/// Tapping a change keeps your own words there instead (the suggestion turns grey and struck through);
/// tapping it again brings the change back. UIKit, because SwiftUI's Text can't tell which word was tapped.
struct ChangesText: UIViewRepresentable {
    let correction: Correction
    var fontSize: CGFloat = 17
    /// Off in the app's form, where the text grows to fit; on in the keyboard card, which has a fixed height.
    var scrolls = true
    let toggle: (Int) -> Void

    func makeUIView(context: Context) -> ChangesTextView {
        ChangesTextView()
    }

    func updateUIView(_ view: ChangesTextView, context: Context) {
        view.isScrollEnabled = scrolls
        view.onToggle = toggle
        view.show(correction, fontSize: fontSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChangesTextView, context: Context) -> CGSize? {
        guard !scrolls, let width = proposal.width, width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .infinity)).height))
    }
}

final class ChangesTextView: UITextView {
    var onToggle: ((Int) -> Void)?
    private var shown: Correction?
    private var shownFontSize: CGFloat = 0
    private static let change = NSAttributedString.Key("FixkeyChange")

    init() {
        // An explicit TextKit 1 stack, for its glyph hit-testing.
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ correction: Correction, fontSize: CGFloat) {
        guard correction != shown || fontSize != shownFontSize else { return }
        shown = correction
        shownFontSize = fontSize
        attributedText = Self.text(for: correction, fontSize: fontSize)
        accessibilityCustomActions = (0..<correction.changeCount).map { change in
            let label = correction.applies(change) ? "Fravælg rettelse \(change + 1)" : "Vælg rettelse \(change + 1)"
            return UIAccessibilityCustomAction(name: label) { [weak self] _ in
                self?.onToggle?(change)
                return true
            }
        }
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard let onToggle, attributedText.length > 0 else { return }
        var point = tap.location(in: self)
        point.x -= textContainerInset.left
        point.y -= textContainerInset.top
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        // Only a tap on (or right next to) the words counts, not on empty space after the last line.
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -12, dy: -6).contains(point) else { return }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < attributedText.length,
              let change = attributedText.attribute(Self.change, at: index, effectiveRange: nil) as? Int else { return }
        onToggle(change)
    }

    static func text(for correction: Correction, fontSize: CGFloat) -> NSAttributedString {
        let regular = UIFont.systemFont(ofSize: fontSize)
        let bold = UIFont.boldSystemFont(ofSize: fontSize)
        let green = UIColor(FixkeyColors.green), red = UIColor(FixkeyColors.red)
        let text = NSMutableAttributedString()
        func add(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        for segment in correction.segments {
            let word = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let space = String(segment.text.dropFirst(segment.text.prefix { !$0.isWhitespace && !$0.isNewline }.count))
            guard let change = segment.change else {
                add(segment.text, [.font: regular, .foregroundColor: UIColor.label])
                continue
            }
            let applied = correction.applies(change)
            var attributes: [NSAttributedString.Key: Any] = [.font: regular, .foregroundColor: UIColor.label, Self.change: change]
            switch (segment.kind, applied) {
            case (.removed, true):
                attributes[.foregroundColor] = red
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = red
            case (.removed, false):
                // Your own words, kept: dotted underline shows they can still be changed.
                attributes[.underlineStyle] = NSUnderlineStyle.single.union(.patternDot).rawValue
                attributes[.underlineColor] = UIColor.secondaryLabel
            case (.added, true):
                attributes[.font] = bold
                attributes[.foregroundColor] = green
            case (.added, false):
                attributes[.foregroundColor] = UIColor.tertiaryLabel
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = UIColor.tertiaryLabel
            case (.same, _):
                break
            }
            add(word, attributes)
            attributes.removeValue(forKey: .strikethroughStyle)
            attributes.removeValue(forKey: .underlineStyle)
            // Keep a gap between a struck-out word and whatever replaces it.
            add(segment.kind == .removed && space.isEmpty ? " " : space, attributes)
        }
        return text
    }
}
