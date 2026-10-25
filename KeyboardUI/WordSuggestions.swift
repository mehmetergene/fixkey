// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import NaturalLanguage
import SwiftUI
import UIKit

/// A complete word at the insertion point. Refuse ambiguous tokens and the middle of a word.
struct KeyboardWord: Hashable {
    let text: String
    let sentence: String

    init?(before: String, after: String, hasSelection: Bool) {
        guard !hasSelection, after.first.map({ !Self.isWordCharacter($0) }) ?? true else { return nil }
        let token = String(before.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !token.contains(where: { "@./:\\#".contains($0) }) else { return nil }
        let word = String(token.reversed().prefix(while: Self.isWordCharacter).reversed())
        guard !word.isEmpty, word.count <= 48, word.contains(where: \.isLetter) else { return nil }
        text = word
        sentence = String(before.suffix(300).split(whereSeparator: { ".!?\n".contains($0) }).last ?? "")
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "'-’".contains(character)
    }
}

/// Dictionary calls stay outside touch callbacks; partial-word lookups are debounced.
/// UIKit requires UITextChecker on the main actor, so its input and cache are deliberately bounded.
@MainActor
final class WordSuggestions: ObservableObject {
    struct State: Equatable {
        var typed = ""
        var alternatives: [String] = []
        var automatic: String?
        var isUndo = false
    }

    struct Result {
        var alternatives: [String] = []
        var automatic: String?
    }

    @Published private(set) var state = State()
    private let checker = UITextChecker()
    private let recognizer = NLLanguageRecognizer()
    private lazy var languages = Set(UITextChecker.availableLanguages)
    private var cache: [KeyboardWord: Result] = [:]
    private var learned: Set<String> = []
    private var pendingLearning: Set<String> = []
    private var protectedWords: Set<String> = []
    private var replacements: [String: String] = [:]
    private var lexiconLoaded = false

    func show(_ value: State) {
        if state != value { state = value }
    }

    func loadLexicon(_ entries: [(input: String, text: String)]) {
        for entry in entries {
            if entry.input != entry.text { replacements[entry.input] = entry.text }
            for text in [entry.input, entry.text] {
                protectedWords.insert(text.lowercased())
                text.split(whereSeparator: { !$0.isLetter }).forEach { protectedWords.insert($0.lowercased()) }
            }
        }
        lexiconLoaded = true
        cache.removeAll()
    }

    func replacement(for word: KeyboardWord) -> String? { replacements[word.text] }
    func cached(for word: KeyboardWord) -> Result? { cache[word] }

    func learn(_ word: String) {
        learned.insert(word.lowercased())
        pendingLearning.insert(word)
        cache.removeAll()
    }

    var hasPendingLearning: Bool { !pendingLearning.isEmpty }

    func flushLearning() {
        pendingLearning.forEach { UITextChecker.learnWord($0) }
        pendingLearning.removeAll()
    }

    func lookup(_ word: KeyboardWord) -> Result {
        if let result = cache[word] { return result }
        guard word.text.count >= 2, word.text.allSatisfy(\.isLetter), let language = language(for: word.sentence),
              dictionaryWorks(for: language) else {
            return Result()
        }
        let text = word.text.lowercased()
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let misspelled = checker.rangeOfMisspelledWord(in: text, range: range, startingAt: 0, wrap: false, language: language)
        let guesses = misspelled.location != NSNotFound
            ? checker.guesses(forWordRange: range, in: text, language: language) ?? [] : []
        let completions = checker.completions(forPartialWordRange: range, in: text, language: language) ?? []
        let protected = !lexiconLoaded || learned.contains(text) || protectedWords.contains(text)
            || UITextChecker.hasLearnedWord(word.text) || UITextChecker.hasLearnedWord(text)
        // All capitals are treated as acronyms; explicit suggestions still preserve that pattern.
        let ordinaryCase = word.text == text || word.text == text.prefix(1).uppercased() + text.dropFirst()
        var automatic: String?
        // Short Danish words ("jo", "da", "nu") are easy to mangle: allow only one edit below four letters.
        let maxEdits = text.count <= 3 ? 1 : 2
        // Like the system keyboard, never change the first letter ("hjæl" must not become "sjæl").
        if !protected, ordinaryCase, let first = guesses.first, first.allSatisfy(\.isLetter),
           first.lowercased().first == text.first,
           Self.editDistance(text, first.lowercased(), limit: maxEdits) <= maxEdits {
            automatic = Self.matchCase(first, to: word.text)
        }
        var alternatives: [String] = []
        for candidate in [automatic].compactMap({ $0 }) + completions + guesses {
            let candidate = Self.matchCase(candidate, to: word.text)
            if candidate != word.text, !alternatives.contains(candidate) { alternatives.append(candidate) }
            if alternatives.count == 2 { break }
        }
        let result = Result(alternatives: alternatives, automatic: automatic)
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[word] = result
        return result
    }

    private var dictionaryChecks: [String: Bool] = [:]
    private static let commonWords = [
        "da_DK": ["ikke", "jeg", "det", "og", "hjælp", "morgen", "fordi", "hvad"],
        "en_US": ["the", "because", "morning", "help", "what", "and", "with", "people"],
    ]

    /// A device without the dictionary for a language flags every word as misspelled ("ikke" → "ikte").
    /// Common words must pass before that language may suggest or autocorrect anything.
    private func dictionaryWorks(for language: String) -> Bool {
        if let known = dictionaryChecks[language] { return known }
        let works = (Self.commonWords[language] ?? []).allSatisfy { word in
            let range = NSRange(word.startIndex..<word.endIndex, in: word)
            return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
                .location == NSNotFound
        }
        dictionaryChecks[language] = works
        return works
    }

    private func language(for sentence: String) -> String? {
        recognizer.reset()
        recognizer.processString(sentence)
        let english = sentence.filter(\.isLetter).count >= 12
            && (recognizer.languageHypotheses(withMaximum: 2)[.english] ?? 0) >= 0.8
        let preferred = english ? "en_US" : "da_DK"
        if languages.contains(preferred) { return preferred }
        // Never silently correct Danish with a dictionary for another language.
        return languages.contains("da_DK") ? "da_DK" : nil
    }

    private static func matchCase(_ suggestion: String, to original: String) -> String {
        if original == original.uppercased() { return suggestion.uppercased() }
        if original.first?.isUppercase == true {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst().lowercased()
        }
        return suggestion.lowercased()
    }

    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1))
            }
            if row.min()! > limit { return limit + 1 }
            previous = row
        }
        return previous[b.count]
    }
}
