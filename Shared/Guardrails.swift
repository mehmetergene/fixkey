// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation
import NaturalLanguage

/// Rules every model reply must pass before it may replace the user's text. A small model can't be trusted to
/// follow "only correct, never answer or translate", so these are enforced in code, whatever the model says.
enum Guardrails {
    enum Violation: Equatable {
        case languageChanged(from: String, to: String)
        case wordsReplaced
        case wordsAdded
        case tooLong
        case sentencesAdded
        case questionAnswered
    }

    /// Returns the first rule the reply breaks, or nil if it looks like a correction of `original`.
    static func violation(original: String, fixed: String) -> Violation? {
        if fixed == original { return nil }
        let a = words(original), b = words(fixed)
        guard !a.isEmpty else { return nil }
        // Typos count as kept words ("hra" → "har"), so spelling fixes are not mistaken for rewrites.
        let kept = commonCount(a, b)
        let replaced = a.count - kept, added = b.count - kept

        if a.count < 3 {
            // Too short for ratios: every word must survive, and at most one small word may be added.
            if replaced > 0 { return .wordsReplaced }
            if added > 1 { return .wordsAdded }
        } else {
            // A grammar fix keeps most words; a translation, answer or refusal replaces them.
            if Double(replaced) / Double(a.count) > 0.5 { return .wordsReplaced }
            // Corrections add a word here and there ("i", "med"); answers and explanations add many.
            if Double(added) / Double(a.count) > 0.5 { return .wordsAdded }
            if b.count > a.count * 3 / 2 + 2 { return .tooLong }
        }
        // Something appended after the user's text ("…Danmark? København.") is an answer or a comment.
        if added > 0, appendsSentence(after: a[a.count - 1], in: fixed) { return .sentencesAdded }
        // An answer drops the question mark and opens differently or adds words; "What I need is…" stays allowed.
        if isQuestion(original), !fixed.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?"),
           added > 0 || !similar(a[0], b.first ?? "") {
            return .questionAnswered
        }
        if let from = language(of: original), let to = language(of: fixed), family(from) != family(to) {
            return .languageChanged(from: from, to: to)
        }
        return nil
    }

    // MARK: Helpers

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Longest common subsequence length, where near-identical words (typos) count as the same word.
    private static func commonCount(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: b.count + 1)
        for i in 0..<a.count {
            var current = Array(repeating: 0, count: b.count + 1)
            for j in 0..<b.count {
                current[j + 1] = similar(a[i], b[j]) ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Same word, or a typo of it: at most one edit for short words, a third of the length for longer ones.
    private static func similar(_ x: String, _ y: String) -> Bool {
        if x == y { return true }
        let limit = max(1, min(x.count, y.count) / 3)
        guard abs(x.count - y.count) <= limit else { return false }
        return editDistance(Array(x), Array(y)) <= limit
    }

    /// Optimal string alignment distance: insertions, deletions, substitutions and adjacent swaps ("hra" → "har").
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    /// The reply ends a sentence after the original's last word and then keeps going with more words.
    /// Sentence counting can't do this: "kl. 10" and lowercase sentence starts fool it.
    private static func appendsSentence(after lastWord: String, in fixed: String) -> Bool {
        let lower = fixed.lowercased()
        // The original's last word, or its typo-fixed version, marks where the user's text ends in the reply.
        let anchor = lower.contains(lastWord) ? lastWord : words(fixed).last { similar($0, lastWord) }
        guard let anchor, let range = lower.range(of: anchor, options: .backwards) else { return false }
        let tail = lower[range.upperBound...]
        guard let end = tail.firstIndex(where: { ".!?".contains($0) }) else { return false }
        return tail[end...].contains(where: { $0.isLetter })
    }

    private static let questionWords: Set<String> = [
        "hvad", "hvem", "hvor", "hvornår", "hvorfor", "hvordan", "hvilken", "hvilket", "hvilke", "hvorhen", "hvorfra",
        "what", "who", "whom", "whose", "where", "when", "why", "how", "which",
    ]
    /// Verbs that open a yes/no question when a subject follows ("Kommer du…", "Can you…").
    private static let questionVerbs: Set<String> = [
        "er", "har", "kan", "vil", "skal", "må", "gider", "kommer", "går", "tror", "synes", "ved", "kunne", "ville", "skulle", "burde",
        "is", "are", "was", "were", "do", "does", "did", "can", "could", "will", "would", "should", "shall", "have", "has", "may",
    ]
    private static let subjects: Set<String> = [
        "du", "i", "de", "han", "hun", "den", "det", "vi", "man", "jeg",
        "you", "he", "she", "it", "we", "they", "i", "there",
    ]

    /// The text's last sentence is a question: it ends with "?", opens with a question word,
    /// or opens with verb + subject. "Kan ikke komme i dag" is not a question.
    private static func isQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return true }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        guard let last = tokenizer.tokens(for: trimmed.startIndex..<trimmed.endIndex).last else { return false }
        let sentence = words(String(trimmed[last]))
        guard let first = sentence.first else { return false }
        if questionWords.contains(first) { return true }
        return sentence.count > 1 && questionVerbs.contains(first) && subjects.contains(sentence[1])
    }

    /// Dominant language, only when the detector is confident.
    private static func language(of text: String) -> String? {
        guard words(text).count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first, probability >= 0.6 else {
            return nil
        }
        return language.rawValue
    }

    /// The detector mixes up Danish, Norwegian and Swedish on short texts; treat them as one family.
    private static func family(_ language: String) -> String {
        ["da", "nb", "nn", "no", "sv"].contains(language) ? "scandinavian" : language
    }
}
