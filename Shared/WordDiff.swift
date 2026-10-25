// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation

/// Word-level diff used to show what the model changed: removed words struck through, added words highlighted.
/// A run of removed and added words is one change; each can be applied or left out on its own.
enum WordDiff {
    enum Kind { case same, removed, added }

    struct Segment: Equatable {
        let text: String
        let kind: Kind
        /// For removed and added words: the change they belong to, numbered from 0 in reading order.
        var change: Int?
    }

    /// Segments in reading order. Within a change, removals come before additions.
    /// Words keep their trailing whitespace so the `same` and `added` segments rebuild `fixed` exactly.
    static func segments(original: String, fixed: String) -> [Segment] {
        alignment(original: original, fixed: fixed).map(\.segment)
    }

    /// Number of separate changes (a run of removed/added words counts once).
    static func changeCount(original: String, fixed: String) -> Int {
        changeCount(in: segments(original: original, fixed: fixed))
    }

    static func changeCount(in segments: [Segment]) -> Int {
        (segments.compactMap(\.change).max() ?? -1) + 1
    }

    /// The first replacement, for the suggestion chip. Lone punctuation is shown with the word before it ("sætning,").
    static func firstChange(original: String, fixed: String) -> (removed: String, added: String)? {
        firstChange(in: segments(original: original, fixed: fixed))
    }

    static func firstChange(in segments: [Segment]) -> (removed: String, added: String)? {
        var removed = "", added = "", previousWord = ""
        func result() -> (removed: String, added: String) {
            let addedText = trim(added)
            let isPunctuation = !addedText.isEmpty && addedText.allSatisfy { $0.isPunctuation || $0.isSymbol }
            return (trim(removed), isPunctuation ? trim(previousWord) + addedText : addedText)
        }
        for segment in segments {
            switch segment.kind {
            case .same where !removed.isEmpty || !added.isEmpty:
                return result()
            case .same: previousWord = segment.text
            case .removed: removed += segment.text
            case .added: added += segment.text
            }
        }
        return removed.isEmpty && added.isEmpty ? nil : result()
    }

    /// The text with every change applied except those in `rejected`.
    /// Rejecting none gives `fixed` exactly; rejecting all gives `original` exactly.
    static func apply(original: String, fixed: String, rejecting rejected: Set<Int>) -> String {
        if rejected.isEmpty { return fixed }
        let steps = alignment(original: original, fixed: fixed)
        let count = (steps.compactMap(\.change).max() ?? -1) + 1
        if rejected.isSuperset(of: 0..<count) { return original }
        var text = ""
        for (index, step) in steps.enumerated() {
            switch step.kind {
            case .same:
                // Right before an applied change, the fixed text's spacing fits it: "dag" + "." rather than "dag " + ".".
                let next = index + 1 < steps.count ? steps[index + 1].change : nil
                text += next.map { !rejected.contains($0) } == true ? step.fixed : step.original
            case .removed:
                if rejected.contains(step.change ?? -1) { text += step.original }
            case .added:
                if !rejected.contains(step.change ?? -1) { text += step.fixed }
            }
        }
        return text
    }

    /// One aligned token as it reads in each text; a removed token has no fixed text and an added one no original.
    private struct Step {
        let kind: Kind
        let original: String
        let fixed: String
        let change: Int?

        var segment: Segment { Segment(text: kind == .removed ? original : fixed, kind: kind, change: change) }
    }

    private static func alignment(original: String, fixed: String) -> [Step] {
        let a = words(original), b = words(fixed)
        let ka = a.map(key), kb = b.map(key)
        let n = a.count, m = b.count

        // Longest common subsequence on trimmed words.
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = ka[i] == kb[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var steps: [Step] = []
        var i = 0, j = 0, change = -1, inChange = false
        while i < n || j < m {
            if i < n, j < m, ka[i] == kb[j] {
                steps.append(Step(kind: .same, original: a[i], fixed: b[j], change: nil))
                inChange = false
                i += 1; j += 1
                continue
            }
            if !inChange {
                change += 1
                inChange = true
            }
            if i < n, j == m || lcs[i + 1][j] >= lcs[i][j + 1] {
                steps.append(Step(kind: .removed, original: a[i], fixed: "", change: change))
                i += 1
            } else {
                steps.append(Step(kind: .added, original: "", fixed: b[j], change: change))
                j += 1
            }
        }
        return steps
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ word: String) -> String {
        trim(word)
    }

    /// Words and punctuation marks each become a token, keeping their trailing whitespace,
    /// so an added comma shows up as just "," rather than the whole word changing.
    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSpace = false
        var inWord = false
        for ch in text {
            let isSpace = ch.isWhitespace || ch.isNewline
            let isWordChar = ch.isLetter || ch.isNumber || "'’-".contains(ch)
            let startsToken = !isSpace && (inSpace || !inWord || !isWordChar)
            if startsToken && !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(ch)
            if !isSpace { inWord = isWordChar }
            inSpace = isSpace
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
