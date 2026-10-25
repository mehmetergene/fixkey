// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation

/// A finished check: the text that was checked, the model's correction, and which changes the user keeps.
/// The diff is worked out once here, not on every redraw.
struct Correction: Equatable {
    let original: String
    let fixed: String
    let segments: [WordDiff.Segment]
    let changeCount: Int
    /// Changes the user turned off, by number.
    private(set) var rejected: Set<Int> = []

    init(original: String, fixed: String) {
        self.original = original
        self.fixed = fixed
        segments = WordDiff.segments(original: original, fixed: fixed)
        changeCount = WordDiff.changeCount(in: segments)
    }

    var appliedCount: Int { changeCount - rejected.count }

    func applies(_ change: Int) -> Bool { !rejected.contains(change) }

    mutating func toggle(_ change: Int) {
        guard (0..<changeCount).contains(change) else { return }
        if rejected.remove(change) == nil { rejected.insert(change) }
    }

    /// What Accept writes: the original with the chosen changes applied.
    var text: String { WordDiff.apply(original: original, fixed: fixed, rejecting: rejected) }

    var firstChange: (removed: String, added: String)? { WordDiff.firstChange(in: segments) }
}
