// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import SwiftUI

/// Fixkey's full keyboard: the strip with the Fixkey icon on top, and either the keys or the suggestion card below.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    static let stripHeight: CGFloat = 42
    /// 4 pt top inset + 4 rows of 43 pt + 3 gaps of 11 pt; the last row ends at the bottom, like Apple's.
    static let keysHeight: CGFloat = 209
    static let height = stripHeight + keysHeight

    var body: some View {
        VStack(spacing: 0) {
            SuggestionStrip(model: model)
                .frame(height: Self.stripHeight)
            Group {
                if model.showsCard, case .result(let correction) = model.check {
                    SuggestionCard(model: model, correction: correction)
                } else {
                    KeysView(model: model)
                }
            }
            .frame(height: Self.keysHeight)
        }
    }
}

// MARK: - Strip

private struct SuggestionStrip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            Button(action: model.iconTapped) {
                FixkeyIcon(check: model.check, showsCard: model.showsCard)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fixkey – tjek teksten")

            status
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch model.check {
        case .idle:
            PredictionBar(suggestions: model.suggestions, choose: model.chooseSuggestion, check: model.iconTapped)

        case .checking:
            Text("Tjekker…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .result(let correction):
            Button { model.showsCard = true } label: {
                SuggestionChip(correction: correction)
            }
            .buttonStyle(.plain)

        case .clean:
            Label("Ser godt ud", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FixkeyColors.green)

        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(FixkeyColors.red)
                .lineLimit(2)
        }
    }
}

/// Only this small view observes per-word updates; the keys and grammar card do not.
private struct PredictionBar: View {
    @ObservedObject var suggestions: WordSuggestions
    let choose: (Int) -> Void
    let check: () -> Void

    var body: some View {
        // Nothing useful to offer (no word, or no dictionary for it): show the grammar-check hint instead.
        if suggestions.state.typed.isEmpty || (suggestions.state.alternatives.isEmpty && !suggestions.state.isUndo) {
            Button(action: check) {
                Text("Tryk for at tjekke teksten")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 0) {
                ForEach(0..<3) { slot in
                    if slot > 0 {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5, height: 22)
                    }
                    let word = word(at: slot)
                    Button { choose(slot) } label: {
                        Text(slot == 0 ? "«\(word)»" : word)
                            .font(.system(size: 17, weight: slot == 1 && suggestions.state.automatic == word ? .bold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(word.isEmpty)
                    .accessibilityLabel(slot == 0 ? "Behold \(word)" : "Indsæt \(word)")
                    .accessibilityHint(slot == 0 && suggestions.state.isUndo ? "Fortryd automatisk rettelse" : "")
                }
            }
        }
    }

    private func word(at slot: Int) -> String {
        if slot == 0 { return suggestions.state.typed }
        let index = slot - 1
        return suggestions.state.alternatives.indices.contains(index) ? suggestions.state.alternatives[index] : ""
    }
}

/// Round Fixkey icon with a red badge counting pending changes, like Grammarly's logo button.
private struct FixkeyIcon: View {
    let check: KeyboardModel.Check
    let showsCard: Bool

    private var changes: Int {
        if case .result(let correction) = check, !showsCard { return correction.appliedCount }
        return 0
    }

    private var isOffline: Bool {
        if case .failed(_, offline: true) = check { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(isOffline ? Color.gray : FixkeyColors.iconGreen)
                .frame(width: 32, height: 32)
                .overlay {
                    if check == .checking {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: isOffline ? "wifi.slash" : "text.badge.checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            if changes > 0 {
                Text("\(changes)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(FixkeyColors.red))
                    .offset(x: 6, y: -4)
            }
        }
        .frame(width: 42, height: 42)
    }
}

/// The first change, shown like Grammarly's chip: a grey label over the replacement in green.
private struct SuggestionChip: View {
    let correction: Correction
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let change = correction.firstChange
        VStack(alignment: .leading, spacing: 0) {
            Text("Ret teksten")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if let change, !change.added.isEmpty {
                Text(change.added)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FixkeyColors.green)
            } else if let change {
                Text(change.removed)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(color: FixkeyColors.red)
                    .foregroundStyle(FixkeyColors.red)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(KeyColors.character(scheme)))
    }
}

// MARK: - Card

/// Grammarly-style card: category line, the text with changes marked, explanation, Accept / Dismiss.
/// Tapping a change in the text turns it off (your own words stay) or back on.
private struct SuggestionCard: View {
    @ObservedObject var model: KeyboardModel
    let correction: Correction
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(FixkeyColors.red)
                Text("Korrekthed: Ret teksten")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            ChangesText(correction: correction, toggle: model.toggleChange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 16) {
                Button(action: model.accept) {
                    Text("Accepter")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(correction.appliedCount > 0 ? FixkeyColors.green : Color.gray))
                }
                .disabled(correction.appliedCount == 0)
                Button(action: model.dismiss) {
                    Text("Afvis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.hideCard) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
                }
                .accessibilityLabel("Tilbage til tastaturet")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(scheme == .dark ? Color(white: 0.17) : .white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private var summary: String {
        let total = correction.changeCount
        if correction.appliedCount < total { return "\(correction.appliedCount) af \(total) rettelser valgt." }
        let found = total == 1 ? "Fixkey fandt 1 rettelse." : "Fixkey fandt \(total) rettelser."
        return found + (total == 1 ? " Tryk på den for at fravælge den." : " Tryk på en for at fravælge den.")
    }
}
