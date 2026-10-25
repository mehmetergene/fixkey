// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation

/// Which part of the text around the cursor one check covers.
enum CheckRange {
    /// From this length on, iOS may have cut a side mid-word, so only whole sentences are checked.
    static let sentenceLimit = 200
    /// At most this many characters on each side of the cursor, so one check stays quick and small.
    static let maximum = 800

    /// iOS can hand a keyboard only part of a long text, possibly starting or ending mid-word. In long contexts,
    /// check only the whole sentences in between, so Accept never rewrites a word it can't fully see.
    static func around(before: String, after: String) -> (before: String, after: String) {
        var before = before[...], after = after[...]
        let cutBefore = before.count > maximum, cutAfter = after.count > maximum
        if cutBefore { before = before.suffix(maximum) }
        if cutAfter { after = after.prefix(maximum) }
        if before.count >= sentenceLimit {
            if let end = before.firstIndex(where: isSentenceEnd) {
                before = before[before.index(after: end)...]
            } else if cutBefore, let space = before.firstIndex(where: \.isWhitespace) {
                // One long sentence: at least never start inside a word.
                before = before[space...]
            }
            while before.first?.isWhitespace == true { before.removeFirst() }
        }
        if after.count >= sentenceLimit {
            if let end = after.lastIndex(where: isSentenceEnd) {
                after = after[...end]
            } else if cutAfter, let space = after.lastIndex(where: \.isWhitespace) {
                after = after[..<space]
            }
        }
        return (String(before), String(after))
    }

    private static func isSentenceEnd(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?" || character.isNewline
    }
}
