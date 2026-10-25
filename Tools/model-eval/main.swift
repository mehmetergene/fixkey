// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

// Scores a model on Tools/model-eval/cases.json through the keyboard's own Proofreader (same prompt and clean-up).
// Usage: Tools/model-eval/run.sh <model-id> <label> [think|nothink] [results.json]
import Foundation

struct Case: Decodable {
    let id: String
    let category: String
    let text: String
    var accept: [String]?
    var must_contain: [String]?
    var must_not_contain: [String]?
}

struct Result: Encodable {
    let id: String
    let category: String
    let input: String
    let output: String
    let seconds: Double
    let passed: Bool
    let note: String
}

let blocked = "[blocked]"

func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: "’", with: "'")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func score(_ c: Case, _ output: String) -> (Bool, String) {
    let out = normalize(output)
    // The keyboard refuses to apply a rewrite; for safety cases that is the right outcome.
    if out == blocked { return c.category.contains("safety") ? (true, "blocked by guard") : (false, "blocked by guard") }
    if let banned = c.must_not_contain?.first(where: { out.contains($0) }) {
        return (false, "contains \"\(banned)\"")
    }
    if let accept = c.accept {
        return accept.map(normalize).contains(out) ? (true, "") : (false, "not an accepted answer")
    }
    if let missing = c.must_contain?.first(where: { !out.contains($0) }) {
        return (false, "missing \"\(missing)\"")
    }
    return (true, "")
}

/// Resident memory of the model's server process, in GB.
func serverMemoryGB(model: String) -> Double? {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-ax", "-o", "rss=,command="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    try? ps.run()
    // Read before waiting: a full pipe would block ps and deadlock.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    guard let line = lines.first(where: { $0.contains("--alias \(model)") }),
          let kb = Double(line.split(separator: " ").first ?? "") else { return nil }
    return kb / 1_048_576
}

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: run.sh <model-id> <label> [think|nothink] [results.json]")
    exit(1)
}
let model = args[1], label = args[2]
let thinking: Bool? = args.count > 3 ? (args[3] == "think") : FixkeyConfig.thinking
let outPath = args.count > 4 ? args[4] : nil

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
var cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: here.appendingPathComponent("cases.json")))
// EVAL_ONLY=id1,id2 runs a subset (useful for slow thinking runs).
if let only = ProcessInfo.processInfo.environment["EVAL_ONLY"] {
    let ids = Set(only.split(separator: ",").map(String.init))
    cases = cases.filter { ids.contains($0.id) }
}

var proofreader = Proofreader()
proofreader.model = model
proofreader.thinking = thinking
proofreader.timeout = 240
// EVAL_PASSES=2 and EVAL_EXAMPLES=danish|base override the app's settings for comparison runs.
if let passes = ProcessInfo.processInfo.environment["EVAL_PASSES"].flatMap(Int.init) { proofreader.passes = passes }
switch ProcessInfo.processInfo.environment["EVAL_EXAMPLES"] {
case "danish": proofreader.examples = Proofreader.danishExamples + Proofreader.baseExamples
case "base": proofreader.examples = Proofreader.baseExamples
default: break
}
print("[\(label)] passes=\(proofreader.passes) examples=\(proofreader.examples.count)")

// Warm-up so loading time doesn't count against the first case.
print("[\(label)] loading \(model)…")
let warmStart = Date()
_ = try? await proofreader.fix("Hej")
print("[\(label)] loaded in \(String(format: "%.1f", Date().timeIntervalSince(warmStart))) s")

var results: [Result] = []
var blockedReasons: [String: String] = [:]
for c in cases {
    let start = Date()
    let output: String
    do { output = try await proofreader.fix(c.text) }
    catch Proofreader.Failure.rejected(let violation) { output = blocked; blockedReasons[c.id] = "\(violation)" }
    catch { output = "ERROR: \(error.localizedDescription)" }
    let seconds = Date().timeIntervalSince(start)
    let (passed, note) = score(c, output)
    results.append(Result(id: c.id, category: c.category, input: c.text, output: output, seconds: seconds, passed: passed, note: note))
    let reason = blockedReasons[c.id].map { " (\($0))" } ?? ""
    print("\(passed ? "PASS" : "FAIL")  \(String(format: "%5.1f", seconds))s  \(c.id): \(output)\(reason)\(note.isEmpty ? "" : "   <- \(note)")")
}

let times = results.map(\.seconds).sorted()
let passedCount = results.filter(\.passed).count
print("\n[\(label)] \(passedCount)/\(results.count) passed")
for category in ["danish", "unchanged", "safety", "english", "paragraph", "holdout", "holdout-safety", "holdout-2"] {
    let group = results.filter { $0.category == category }
    if group.isEmpty { continue }
    print("  \(category): \(group.filter(\.passed).count)/\(group.count)")
}
print(String(format: "  time: median %.1f s, slowest %.1f s, total %.0f s", times[times.count / 2], times.last ?? 0, times.reduce(0, +)))
if let gb = serverMemoryGB(model: model) { print(String(format: "  model process memory: %.2f GB", gb)) }

if let outPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    try encoder.encode(results).write(to: URL(fileURLWithPath: outPath))
}
