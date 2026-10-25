// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI
import UIKit

/// Measured from Apple's keyboard on an iPhone (dark mode): every key, letters and function keys alike,
/// is #444444 with no shadow line.
enum KeyColors {
    static func character(_ dark: Bool) -> UIColor { dark ? UIColor(white: 0x44 / 255, alpha: 1) : .white }
    static func function(_ dark: Bool) -> UIColor { character(dark) }
    static func pressed(_ dark: Bool) -> UIColor { dark ? UIColor(white: 0x6B / 255, alpha: 1) : UIColor(red: 0.74, green: 0.76, blue: 0.79, alpha: 1) }
    static func shadow(_ dark: Bool) -> UIColor { .clear }

    static func character(_ scheme: ColorScheme) -> Color { Color(character(scheme == .dark)) }
}

/// What a key does. Characters, space, return and page keys fire on touch-up; shift and backspace on touch-down.
enum KeyAction: Equatable {
    case character(String)
    case shift
    case backspace
    case deleteWord
    case moveCursor(Int)
    case page(KeyboardModel.Page)
    case globe
    case space
    case newline
}

/// The key area in UIKit for native responsiveness: immediate highlight and popup on touch-down,
/// multi-touch rollover for fast two-thumb typing, and no SwiftUI re-render per keystroke.
final class KeysUIView: UIView {
    struct State: Equatable {
        var page: KeyboardModel.Page = .letters
        var shift: KeyboardModel.Shift = .on
        var showsGlobe = false
        var returnLabel = "retur"
        var returnProminent = false
    }

    private enum Style { case character, function, active, prominent }

    private struct Key {
        let action: KeyAction
        let frame: CGRect
        let label: String?
        let symbol: String?
        let style: Style
    }

    var onAction: ((KeyAction) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    // Apple's keyboard on an iPhone: 43 pt keys, 6 pt gaps, 11 pt between rows, 6.5 pt side margins,
    // 41 pt shift/delete, 43 pt "123", 93 pt return.
    static let keyHeight: CGFloat = 43
    private let margin: CGFloat = 6.5
    private let gap: CGFloat = 6
    private let rowSpacing: CGFloat = 11
    private let topInset: CGFloat = 4
    private let sideKeyWidth: CGFloat = 41
    private let modeKeyWidth: CGFloat = 43.3
    private let returnKeyWidth: CGFloat = 93

    private var state = State()
    private var keys: [Key] = []
    private var caps: [KeyCap] = []
    private var activeTouches: [UITouch: Int] = [:]
    private var popups: [UITouch: KeyCap] = [:]
    private var repeatTimer: Timer?
    private var repeatStarted: TimeInterval = 0
    private var holdTimers: [UITouch: Timer] = [:]
    private var origins: [UITouch: CGPoint] = [:]
    private var outsideTouches: Set<UITouch> = []
    private var variantTouch: UITouch?
    private var variantCallout: VariantCallout?
    private var cursorTouch: UITouch?
    private var cursorAnchor: CGFloat = 0
    private var reportedInteraction = false
    private var laidOutWidth: CGFloat = 0

    private static let letters = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "å"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "æ", "ø"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private static let numbers = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "kr", "&", "@", "\""],
    ]
    private static let symbols = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "$", "£", "€", "•"],
    ]
    private static let punctuation = [".", ",", "?", "!", "'"]
    private static let variants: [String: [String]] = [
        "a": ["æ", "å", "ä", "á", "à", "â", "ã", "ā"],
        "e": ["é", "è", "ê", "ë", "ē", "ė", "ę"],
        "i": ["í", "ì", "î", "ï", "ī", "į"],
        "o": ["ø", "ö", "ó", "ò", "ô", "õ", "ō", "œ"],
        "u": ["ü", "ú", "ù", "û", "ū"], "y": ["ý", "ÿ"],
        "c": ["ç", "ć", "č"], "n": ["ñ", "ń"], "s": ["ß", "ś", "š"],
        "z": ["ž", "ź", "ż"], "l": ["ł"],
        "-": ["–", "—", "•"], "kr": ["$", "€", "£", "¥"], ".": ["…"],
        "?": ["¿"], "!": ["¡"], "'": ["’", "‘", "`"], "\"": ["“", "”", "„", "«", "»"],
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        backgroundColor = .clear
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: KeysUIView, _: UITraitCollection) in
            view.refreshCaps()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ newState: State) {
        guard newState != state else { return }
        let needsLayout = state.page != newState.page || state.showsGlobe != newState.showsGlobe
            || state.returnLabel != newState.returnLabel || state.returnProminent != newState.returnProminent
        state = newState
        if needsLayout { rebuild() } else { refreshCaps() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != laidOutWidth { rebuild() }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { cancelInteractions() }
        super.willMove(toWindow: newWindow)
    }

    deinit {
        repeatTimer?.invalidate()
        holdTimers.values.forEach { $0.invalidate() }
    }

    // MARK: Layout

    private func rebuild() {
        cancelInteractions()
        laidOutWidth = bounds.width
        guard bounds.width > 0 else { return }
        keys = layout(width: bounds.width - 2 * margin)
        caps.forEach { $0.removeFromSuperview() }
        caps = keys.map { key in
            let cap = KeyCap(frame: key.frame)
            addSubview(cap)
            return cap
        }
        refreshCaps()
    }

    /// Shift and appearance changes keep every key view and in-flight touch intact.
    private func refreshCaps() {
        guard bounds.width > 0, !caps.isEmpty else { return }
        keys = layout(width: bounds.width - 2 * margin)
        guard keys.count == caps.count else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        for (index, key) in keys.enumerated() {
            caps[index].configure(label: key.label, symbol: key.symbol, fill: fill(for: key.style, dark: dark),
                                  highlight: highlight(for: key.style, dark: dark), shadow: KeyColors.shadow(dark),
                                  textColor: key.style == .prominent ? .white : .label, fontSize: fontSize(for: key),
                                  lift: lift(for: key))
            caps[index].cornerText = key.action == .space ? "DA" : nil
        }
    }

    private func layout(width: CGFloat) -> [Key] {
        var result: [Key] = []
        var y = topInset
        func row(_ items: [(KeyAction, CGFloat, String?, String?, Style)]) {
            var x = margin
            for (action, w, label, symbol, style) in items {
                result.append(Key(action: action, frame: CGRect(x: x, y: y, width: w, height: Self.keyHeight),
                                  label: label, symbol: symbol, style: style))
                x += w + gap
            }
            y += Self.keyHeight + rowSpacing
        }

        let unit = (width - 10 * gap) / 11
        let upper = state.shift != .off
        switch state.page {
        case .letters:
            for letters in Self.letters.prefix(2) {
                row(letters.map { let s = upper ? $0.uppercased() : $0; return (.character(s), unit, s, nil, .character) })
            }
            // Apple keeps Z–M on the same columns as E–O, with narrow shift/delete at the edges.
            func at(_ x: CGFloat, _ w: CGFloat, _ action: KeyAction, _ label: String?, _ symbol: String?, _ style: Style) {
                result.append(Key(action: action, frame: CGRect(x: margin + x, y: y, width: w, height: Self.keyHeight),
                                  label: label, symbol: symbol, style: style))
            }
            at(0, sideKeyWidth, .shift, nil, shiftSymbol, state.shift == .off ? .function : .active)
            for (index, letter) in Self.letters[2].enumerated() {
                let s = upper ? letter.uppercased() : letter
                at(CGFloat(index + 2) * (unit + gap), unit, .character(s), s, nil, .character)
            }
            at(width - sideKeyWidth, sideKeyWidth, .backspace, nil, "delete.left", .function)
            y += Self.keyHeight + rowSpacing
        case .numbers, .symbols:
            let rows = state.page == .numbers ? Self.numbers : Self.symbols
            let unit10 = (width - 9 * gap) / 10
            for keys in rows { row(keys.map { (.character($0), unit10, $0, nil, .character) }) }
            let side = sideKeyWidth
            let wide = (width - 2 * side - 6 * gap) / 5
            let toggle: (KeyAction, String) = state.page == .numbers ? (.page(.symbols), "#+=") : (.page(.numbers), "123")
            row([(toggle.0, side, toggle.1, nil, .function)]
                + Self.punctuation.map { (.character($0), wide, $0, nil, .character) }
                + [(.backspace, side, nil, "delete.left", .function)])
        }

        let modeWidth = modeKeyWidth, globeWidth = modeKeyWidth, returnWidth = returnKeyWidth
        let spaceWidth = width - modeWidth - returnWidth - (state.showsGlobe ? globeWidth + gap : 0) - 2 * gap
        var bottom: [(KeyAction, CGFloat, String?, String?, Style)] = [
            (.page(state.page == .letters ? .numbers : .letters), modeWidth, state.page == .letters ? "123" : "ABC", nil, .function),
        ]
        if state.showsGlobe { bottom.append((.globe, globeWidth, nil, "globe", .function)) }
        bottom.append((.space, spaceWidth, nil, nil, .character))
        // The default return key is an icon on Apple's keyboard; "søg", "send"… stay as words.
        let returnIsIcon = state.returnLabel == "retur"
        bottom.append((.newline, returnWidth, returnIsIcon ? nil : state.returnLabel, returnIsIcon ? "return.left" : nil,
                       state.returnProminent ? .prominent : .function))
        row(bottom)
        return result
    }

    private var shiftSymbol: String {
        switch state.shift {
        case .off: return "shift"
        case .on: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }

    private func fill(for style: Style, dark: Bool) -> UIColor {
        switch style {
        case .character, .active: return KeyColors.character(dark)
        case .function: return KeyColors.function(dark)
        case .prominent: return .systemBlue
        }
    }

    private func highlight(for style: Style, dark: Bool) -> UIColor {
        style == .prominent ? UIColor.systemBlue.withAlphaComponent(0.7) : KeyColors.pressed(dark)
    }

    /// Measured against Apple's keyboard on an iPhone: lowercase letters are drawn larger than capitals.
    private func fontSize(for key: Key) -> CGFloat {
        guard case .character(let s) = key.action, s.count == 1 else { return 18 }
        if Self.isLowercaseLetter(s) { return 24.5 }
        return s.first?.isLetter == true ? 21.3 : 22
    }

    /// How far a label sits above the key's centre; a centred label looks low. Apple raises lowercase letters more.
    private func lift(for key: Key) -> CGFloat {
        if case .character(let s) = key.action, Self.isLowercaseLetter(s) { return 2.4 }
        return 1.2
    }

    private static func isLowercaseLetter(_ s: String) -> Bool {
        s.count == 1 && s.first?.isLetter == true && s == s.lowercased() && s != s.uppercased()
    }

    // MARK: Touches

    private func keyIndex(at point: CGPoint) -> Int? {
        guard bounds.insetBy(dx: -18, dy: -12).contains(point) else { return nil }
        if let hit = keys.firstIndex(where: { $0.frame.insetBy(dx: -gap / 2, dy: -rowSpacing / 2).contains(point) }) {
            return hit
        }
        return keys.indices.min { distance(point, keys[$0].frame) < distance(point, keys[$1].frame) }
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard variantTouch == nil, cursorTouch == nil else { continue }
            // Rollover: a new finger commits the key the previous finger is still holding.
            for (other, index) in Array(activeTouches) where other !== touch { release(other, index: index, commit: true) }
            guard let index = keyIndex(at: touch.location(in: self)) else { continue }
            activeTouches[touch] = index
            origins[touch] = touch.location(in: self)
            syncInteraction()
            press(touch, index: index)
        }
        syncInteraction()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if touch === cursorTouch {
                let steps = Int((point.x - cursorAnchor) / 9)
                if steps != 0 {
                    cursorAnchor += CGFloat(steps) * 9
                    for _ in 0..<abs(steps) { onAction?(.moveCursor(steps > 0 ? 1 : -1)) }
                }
                continue
            }
            if touch === variantTouch {
                variantCallout?.track(point, origin: origins[touch] ?? point)
                continue
            }
            guard let current = activeTouches[touch], keys.indices.contains(current), caps.indices.contains(current) else { continue }
            guard let index = keyIndex(at: point) else {
                outsideTouches.insert(touch)
                unpress(touch, index: current)
                if keys[current].action == .backspace { stopRepeating() }
                continue
            }
            guard case .character = keys[current].action, case .character = keys[index].action else {
                if let origin = origins[touch], hypot(point.x - origin.x, point.y - origin.y) > 18 { cancelHold(touch) }
                if keys[current].frame.insetBy(dx: -18, dy: -18).contains(point) {
                    outsideTouches.remove(touch)
                    caps[current].isHighlighted = true
                } else {
                    outsideTouches.insert(touch)
                    unpress(touch, index: current)
                    if keys[current].action == .backspace { stopRepeating() }
                }
                continue
            }
            guard index != current || outsideTouches.contains(touch) else { continue }
            // Sliding to a neighbouring letter moves the highlight, like the system keyboard.
            unpress(touch, index: current)
            outsideTouches.remove(touch)
            activeTouches[touch] = index
            origins[touch] = point
            press(touch, index: index)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let index = activeTouches[touch] {
                let point = touch.location(in: self)
                if touch === variantTouch { variantCallout?.track(point, origin: origins[touch] ?? point) }
                let inside = touch === variantTouch ? variantCallout?.allows(point) == true : keyIndex(at: point) != nil
                release(touch, index: index, commit: inside || touch === cursorTouch)
            }
        }
        syncInteraction()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let index = activeTouches[touch] { release(touch, index: index, commit: false) }
        }
        syncInteraction()
    }

    private func press(_ touch: UITouch, index: Int) {
        guard keys.indices.contains(index), caps.indices.contains(index) else { return }
        let key = keys[index]
        caps[index].isHighlighted = true
        UIDevice.current.playInputClick()
        switch key.action {
        case .character(let s):
            showPopup(s, for: key, touch: touch)
            if Self.variants[s.lowercased()] != nil { startHold(touch, index: index, delay: 0.4) }
        case .shift:
            onAction?(.shift)
        case .backspace:
            onAction?(.backspace)
            startRepeating()
        case .space:
            startHold(touch, index: index, delay: 0.35)
        default:
            break
        }
    }

    private func unpress(_ touch: UITouch, index: Int) {
        cancelHold(touch)
        if caps.indices.contains(index) { caps[index].isHighlighted = false }
        popups.removeValue(forKey: touch)?.removeFromSuperview()
    }

    private func release(_ touch: UITouch, index: Int, commit: Bool) {
        activeTouches.removeValue(forKey: touch)
        unpress(touch, index: index)
        origins.removeValue(forKey: touch)
        let wasOutside = outsideTouches.remove(touch) != nil
        if touch === cursorTouch {
            cursorTouch = nil
            caps.forEach { $0.setLabelAlpha(1) }
            return
        }
        if touch === variantTouch {
            let selected = variantCallout?.selectedText
            variantTouch = nil
            variantCallout?.removeFromSuperview()
            variantCallout = nil
            if commit, let selected { onAction?(.character(selected)) }
            return
        }
        guard keys.indices.contains(index) else { return }
        let action = keys[index].action
        if action == .backspace { stopRepeating() }
        if commit, !wasOutside, action != .shift, action != .backspace { onAction?(action) }
    }

    func cancelInteractions() {
        for (touch, index) in Array(activeTouches) { release(touch, index: index, commit: false) }
        stopRepeating()
        holdTimers.values.forEach { $0.invalidate() }
        holdTimers.removeAll()
        syncInteraction()
    }

    private func syncInteraction() {
        let active = !activeTouches.isEmpty
        if active != reportedInteraction {
            reportedInteraction = active
            onInteractionChanged?(active)
        }
    }

    private func startHold(_ touch: UITouch, index: Int, delay: TimeInterval) {
        cancelHold(touch)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self, weak touch] _ in
            guard let self, let touch, activeTouches[touch] == index, keys.indices.contains(index),
                  !outsideTouches.contains(touch) else { return }
            holdTimers.removeValue(forKey: touch)
            popups.removeValue(forKey: touch)?.removeFromSuperview()
            if keys[index].action == .space {
                cursorTouch = touch
                cursorAnchor = touch.location(in: self).x
                caps.forEach { $0.setLabelAlpha(0.25) }
            } else if case .character(let text) = keys[index].action, let variants = Self.variants[text.lowercased()] {
                let upper = text != text.lowercased()
                let values = upper ? variants.map { $0.uppercased() } : variants
                let width = min(bounds.width - 6, CGFloat(values.count) * 34 + 8)
                let key = keys[index].frame
                let x = min(max(3, key.midX - 21), bounds.width - width - 3)
                // The strip belongs to the keyboard too; top-row callouts fit inside its 46 points.
                let y = max(-KeyboardView.stripHeight + 2, key.minY - 52)
                let callout = VariantCallout(values: values, frame: CGRect(x: x, y: y, width: width, height: 46),
                                             dark: traitCollection.userInterfaceStyle == .dark)
                variantTouch = touch
                variantCallout = callout
                addSubview(callout)
            }
        }
        holdTimers[touch] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelHold(_ touch: UITouch) { holdTimers.removeValue(forKey: touch)?.invalidate() }

    private func showPopup(_ text: String, for key: Key, touch: UITouch) {
        let dark = traitCollection.userInterfaceStyle == .dark
        let width = key.frame.width + 14, height: CGFloat = 50
        let x = max(2, min(key.frame.midX - width / 2, bounds.width - width - 2))
        let y = max(-KeyboardView.stripHeight + 1, key.frame.minY - height - 2)
        let popup = KeyCap(frame: CGRect(x: x, y: y, width: width, height: height))
        popup.configure(label: text, symbol: nil, fill: KeyColors.character(dark), highlight: KeyColors.character(dark),
                        shadow: UIColor(white: 0, alpha: 0.25), textColor: .label, fontSize: 32, lift: 1.2)
        popup.isUserInteractionEnabled = false
        addSubview(popup)
        popups[touch]?.removeFromSuperview()
        popups[touch] = popup
    }

    private func startRepeating() {
        stopRepeating()
        repeatStarted = ProcessInfo.processInfo.systemUptime
        repeatTimer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            repeatBackspace()
            let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in self?.repeatBackspace() }
            repeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if let repeatTimer { RunLoop.main.add(repeatTimer, forMode: .common) }
    }

    private func repeatBackspace() {
        onAction?(ProcessInfo.processInfo.systemUptime - repeatStarted >= 1.5 ? .deleteWord : .backspace)
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// A clamped row of alternatives. The original key remains a safe release area while choosing.
private final class VariantCallout: UIView {
    private let values: [String]
    private var labels: [UILabel] = []
    private var selected: Int? = 0

    var selectedText: String? {
        guard let selected, values.indices.contains(selected) else { return nil }
        return values[selected]
    }

    init(values: [String], frame: CGRect, dark: Bool) {
        self.values = values
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = KeyColors.character(dark)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        let width = (bounds.width - 8) / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let label = UILabel(frame: CGRect(x: 4 + CGFloat(index) * width, y: 4, width: width, height: bounds.height - 8))
            label.text = value
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            addSubview(label)
            labels.append(label)
        }
        refreshSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func allows(_ point: CGPoint) -> Bool { frame.insetBy(dx: -24, dy: -56).contains(point) }

    func track(_ point: CGPoint, origin: CGPoint) {
        if !allows(point) {
            selected = nil
        } else if abs(point.x - origin.x) > 7 || point.y < frame.maxY {
            let width = (bounds.width - 8) / CGFloat(values.count)
            selected = min(values.count - 1, max(0, Int((point.x - frame.minX - 4) / width)))
        } else if selected == nil {
            selected = 0
        }
        refreshSelection()
    }

    private func refreshSelection() {
        for (index, label) in labels.enumerated() {
            label.backgroundColor = index == selected ? .systemBlue : .clear
            label.textColor = index == selected ? .white : .label
        }
    }
}

/// One key: rounded rectangle, 1pt bottom shadow, label or SF Symbol.
private final class KeyCap: UIView {
    private let label = UILabel()
    private let imageView = UIImageView()
    private var fillColor: UIColor = .white
    private var highlightColor: UIColor = .white

    var isHighlighted = false {
        didSet { backgroundColor = isHighlighted ? highlightColor : fillColor }
    }

    /// Small grey tag in the bottom-right corner, like the "DA" on Apple's space bar.
    var cornerText: String? {
        didSet {
            cornerLabel.text = cornerText
            cornerLabel.isHidden = cornerText == nil
        }
    }
    private let cornerLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8.5
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8.5).cgPath
        isUserInteractionEnabled = false
        for view in [label, imageView] as [UIView] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
        label.textAlignment = .center
        imageView.contentMode = .center
        label.frame = bounds.offsetBy(dx: 0, dy: -1.2)
        cornerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        cornerLabel.textColor = .secondaryLabel
        cornerLabel.textAlignment = .right
        cornerLabel.frame = CGRect(x: 0, y: bounds.height - 17, width: bounds.width - 8, height: 14)
        cornerLabel.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        cornerLabel.isHidden = true
        addSubview(cornerLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(label text: String?, symbol: String?, fill: UIColor, highlight: UIColor, shadow: UIColor,
                   textColor: UIColor, fontSize: CGFloat, lift: CGFloat) {
        label.frame = bounds.offsetBy(dx: 0, dy: -lift)
        fillColor = fill
        highlightColor = highlight
        backgroundColor = isHighlighted ? highlight : fill
        layer.shadowColor = shadow.cgColor
        label.text = text
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = textColor
        if let symbol {
            imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
            imageView.tintColor = textColor
        } else {
            imageView.image = nil
        }
    }

    func setLabelAlpha(_ alpha: CGFloat) {
        label.alpha = alpha
        imageView.alpha = alpha
    }
}

/// Hosts the UIKit key area inside the SwiftUI keyboard.
struct KeysView: UIViewRepresentable {
    @ObservedObject var model: KeyboardModel

    func makeUIView(context: Context) -> KeysUIView {
        let view = KeysUIView()
        view.onAction = { [weak model] action in model?.handle(action) }
        view.onInteractionChanged = { [weak model] active in model?.keyInteractionChanged(active) }
        return view
    }

    func updateUIView(_ view: KeysUIView, context: Context) {
        view.update(.init(page: model.page, shift: model.shift, showsGlobe: model.showsGlobeKey,
                          returnLabel: model.returnLabel, returnProminent: model.returnIsProminent))
    }

    static func dismantleUIView(_ view: KeysUIView, coordinator: Void) {
        view.cancelInteractions()
        view.onAction = nil
        view.onInteractionChanged = nil
    }
}
