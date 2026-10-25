// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

// Checks the shared code that needs no model: the word diff and accepting some changes, the reply clean-up,
// the part of the text a check covers, and what network errors mean. Usage: Tools/core-check/run.sh
import Foundation

var checks = 0, failures = 0

func expect(_ condition: Bool, _ label: String, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL  \(label)  (line \(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    expect(actual == expected, "\(label): got \(String(reflecting: actual)), expected \(String(reflecting: expected))", line: line)
}

// MARK: Word diff

let pairs: [(original: String, fixed: String)] = [
    ("jeg har ikke mye tid idag", "Jeg har ikke meget tid i dag."),
    ("hej, kommer du komme morgen? jeg har ikke mye tid idag", "Hej, kommer du i morgen? Jeg har ikke meget tid i dag."),
    ("Hej  med  dig", "Hej med dig."),
    ("  hej med dig ", "  Hej med dig. "),
    ("jeg har har tid", "jeg har tid"),
    ("i has went to the store yesterday and buyed three apple", "I went to the store yesterday and bought three apples."),
    ("Hej Anne. Tak for din mail. jeg har læst den", "Hej Anne. Tak for din mail. Jeg har læst den."),
    ("linje et\nlinje to", "Linje et.\nLinje to."),
    ("emoji 👍🏽 her", "Emoji 👍🏽 her."),
    ("Det er rigtigt.", "Det er rigtigt."),
    ("", "Hej."),
]

for (original, fixed) in pairs {
    let segments = WordDiff.segments(original: original, fixed: fixed)
    let count = WordDiff.changeCount(in: segments)
    expectEqual(segments.filter { $0.kind != .removed }.map(\.text).joined(), fixed, "same + added rebuild the fix (\(original))")
    expectEqual(WordDiff.apply(original: original, fixed: fixed, rejecting: []), fixed, "no change left out (\(original))")
    expectEqual(WordDiff.apply(original: original, fixed: fixed, rejecting: Set(0..<count)), original,
                "every change left out (\(original))")
    // Changes are numbered 0, 1, 2… in reading order; same words have none.
    var next = 0, previous: Int?
    var numbered = true
    for segment in segments {
        if segment.kind == .same { numbered = numbered && segment.change == nil; previous = nil; continue }
        guard let change = segment.change else { numbered = false; continue }
        if change != previous {
            numbered = numbered && change == next
            next += 1
        }
        previous = change
    }
    expect(numbered && next == count, "changes numbered in reading order (\(original))")
}

let partial: [(original: String, fixed: String, rejected: Set<Int>, expected: String)] = [
    ("jeg har ikke mye tid idag", "Jeg har ikke meget tid i dag.", [1], "Jeg har ikke mye tid i dag."),
    ("jeg har ikke mye tid idag", "Jeg har ikke meget tid i dag.", [0], "jeg har ikke meget tid i dag."),
    ("jeg har ikke mye tid idag", "Jeg har ikke meget tid i dag.", [2], "Jeg har ikke meget tid idag"),
    ("jeg har ikke mye tid idag", "Jeg har ikke meget tid i dag.", [0, 2], "jeg har ikke meget tid idag"),
    ("  hej med dig ", "  Hej med dig. ", [0], "  hej med dig. "),
    ("  hej med dig ", "  Hej med dig. ", [1], "  Hej med dig "),
    ("jeg har har tid idag", "jeg har tid i dag", [1], "jeg har tid idag"),
    ("linje et\nlinje to", "Linje et.\nLinje to.", [2], "Linje et.\nLinje to"),
]
for test in partial {
    expectEqual(WordDiff.apply(original: test.original, fixed: test.fixed, rejecting: test.rejected), test.expected,
                "\(test.original) without \(test.rejected.sorted())")
}

expectEqual(WordDiff.changeCount(original: "jeg har ikke mye tid idag", fixed: "Jeg har ikke meget tid i dag."), 3, "change count")
expect(WordDiff.firstChange(original: "Det er en sætning", fixed: "Det er en sætning.").map { $0.added == "sætning." } == true,
       "lone punctuation shown with the word before it")

// MARK: Correction

var correction = Correction(original: "jeg har ikke mye tid idag", fixed: "Jeg har ikke meget tid i dag.")
expectEqual(correction.appliedCount, 3, "all changes applied at first")
correction.toggle(1)
expectEqual(correction.appliedCount, 2, "one change turned off")
expect(!correction.applies(1) && correction.applies(0), "applies() follows toggle()")
expectEqual(correction.text, "Jeg har ikke mye tid i dag.", "text without the turned-off change")
correction.toggle(1)
expectEqual(correction.text, correction.fixed, "turned back on")
correction.toggle(7)
expectEqual(correction.appliedCount, 3, "unknown change numbers are ignored")

// MARK: Check range

let sentence = "Hej med dig. "
expect(CheckRange.around(before: "hej med dig", after: "") == ("hej med dig", ""), "short text is checked whole")
let partialStart = "en sætning som iOS skar over. " + String(repeating: sentence, count: 20) + "jeg skriver"
expect(CheckRange.around(before: partialStart, after: "").before.hasPrefix("Hej med dig."), "long text starts at a whole sentence")
let long = CheckRange.around(before: String(repeating: sentence, count: 100) + "nu", after: "")
expect(long.before.count <= CheckRange.maximum && long.before.hasPrefix("Hej") && long.before.hasSuffix("nu"),
       "very long text is capped at a sentence start, keeping the cursor end")
let noStops = CheckRange.around(before: String(repeating: "ord ", count: 300), after: "")
expect(noStops.before.count <= CheckRange.maximum && noStops.before.hasPrefix("ord "), "capped text never starts mid-word")
let longAfter = CheckRange.around(before: "", after: "slut her. " + String(repeating: sentence, count: 100))
expect(longAfter.after.count <= CheckRange.maximum && longAfter.after.hasSuffix("."), "long text after the cursor ends at a sentence")
let unbroken = String(repeating: "ord ", count: 60)
expectEqual(CheckRange.around(before: "", after: unbroken).after, unbroken, "uncapped text without sentence ends stays whole")

// MARK: Reply clean-up

let cleanups: [(reply: String, original: String, expected: String)] = [
    ("<<<\nHej med dig.\n>>>", "hej med dig", "Hej med dig."),
    ("Corrected text: Hej.", "hej", "Hej."),
    ("\"Hej.\"", "hej", "Hej."),
    ("\"Hej.\"", "\"hej\"", "\"Hej.\""),
    ("tænker…</think>\nHej.", "hej", "Hej."),
    ("a </think> b", "a </think> b", "a </think> b"),
]
for test in cleanups {
    expectEqual(Proofreader.clean(test.reply, original: test.original), test.expected, "clean \(String(reflecting: test.reply))")
}

// MARK: Past tense

let pastTense: [(text: String, expected: String)] = [
    ("De har købt en ny bil i sidste uge.", "De købte en ny bil i sidste uge."),
    ("Jeg har boet her for tre år siden.", "Jeg boede her for tre år siden."),
    ("Vi har været i Italien sidste sommer.", "Vi var i Italien sidste sommer."),
    ("Hun har startet på universitetet for to år siden.", "Hun startede på universitetet for to år siden."),
    ("Vi har spist på en ny restaurant i fredags.", "Vi spiste på en ny restaurant i fredags."),
    ("Har du set filmen i går?", "Så du filmen i går?"),
    ("I går har jeg ikke haft tid.", "I går havde jeg ikke tid."),
    ("Jeg har ikke spist noget i går, fordi jeg havde travlt.", "Jeg spiste ikke noget i går, fordi jeg havde travlt."),
    ("Han sagde, at han har købt en bil i går.", "Han sagde, at han købte en bil i går."),
    ("Bogen, som jeg har købt i går, er god.", "Bogen, som jeg købte i går, er god."),
    ("Vi har haft det sjovt i aftes.", "Vi havde det sjovt i aftes."),
    ("I går har der været en fest.", "I går var der en fest."),
    ("Jeg har prøvet at ringe til dig i morges.", "Jeg prøvede at ringe til dig i morges."),
    ("Sidste weekend har vi besøgt min mor.", "Sidste weekend besøgte vi min mor."),
    ("De har flyttet til Aarhus for 3 år siden.", "De flyttede til Aarhus for 3 år siden."),
    ("Jeg har kunnet se det i forgårs.", "Jeg kunne se det i forgårs."),
    ("Hun har forstået det i går.", "Hun forstod det i går."),
    ("Vi har mødt hinanden dengang.", "Vi mødte hinanden dengang."),
    ("Han har vist købt en bil i går.", "Han købte vist en bil i går."),
    ("Butikken har været lukket i mandags.", "Butikken var lukket i mandags."),
    ("HAR DU SET HAM I GÅR?", "SÅ DU HAM I GÅR?"),
    ("Jeg har været syg i går. Nu har jeg det bedre.", "Jeg var syg i går. Nu har jeg det bedre."),
    ("Hej! Vi har været i Rom i sidste måned, og det var dejligt.", "Hej! Vi var i Rom i sidste måned, og det var dejligt."),
    // Unchanged: "har" is right, or the rule can't be sure.
    ("Jeg har ikke set ham siden i går.", "Jeg har ikke set ham siden i går."),
    ("Jeg har boet her i tre år.", "Jeg har boet her i tre år."),
    ("Jeg har boet her det sidste år.", "Jeg har boet her det sidste år."),
    ("Jeg har læst bogen, som jeg købte i går.", "Jeg har læst bogen, som jeg købte i går."),
    ("Jeg har læst bogen som jeg købte i går.", "Jeg har læst bogen som jeg købte i går."),
    ("Jeg har sagt at han kom i går.", "Jeg har sagt at han kom i går."),
    ("Vi har haft travlt hele ugen.", "Vi har haft travlt hele ugen."),
    ("Det har regnet hele dagen i går.", "Det har regnet hele dagen i går."),
    ("I dag har jeg været i byen.", "I dag har jeg været i byen."),
    ("Jeg har spist og drukket i går.", "Jeg har spist og drukket i går."),
    ("I går har vi spist pizza og drukket cola.", "I går har vi spist pizza og drukket cola."),
    ("Har din bror købt en bil i går?", "Har din bror købt en bil i går?"),
    ("Han har en bil i går.", "Han har en bil i går."),
    ("Vi havde spist i går.", "Vi havde spist i går."),
    ("Han er gået i går.", "Han er gået i går."),
    ("Jeg har ladet telefonen op i går.", "Jeg har ladet telefonen op i går."),
    ("Tak for i går, det var en dejlig aften.", "Tak for i går, det var en dejlig aften."),
    ("Jeg har altid boet i Danmark.", "Jeg har altid boet i Danmark."),
    ("I have seen it yesterday.", "I have seen it yesterday."),
    ("Vi ses for", "Vi ses for"),
    ("", ""),
]
for test in pastTense {
    let fixed = PastTense.apply(test.text)
    expectEqual(fixed, test.expected, "past tense \(String(reflecting: test.text))")
    expectEqual(PastTense.apply(fixed), fixed, "past tense twice \(String(reflecting: test.text))")
}
expect(PastTense.participles.count > 200, "past tense: the verb list parses")

// MARK: Network errors

let errors: [(URLError.Code, Bool, Proofreader.Failure)] = [
    (.cannotFindHost, true, .macNotFound),
    (.dnsLookupFailed, true, .macNotFound),
    (.cannotConnectToHost, true, .relayNotRunning),
    (.cannotConnectToHost, false, .llamaNotRunning),
    (.timedOut, true, .timedOut),
    (.notConnectedToInternet, true, .offline),
    (.secureConnectionFailed, true, .untrustedRelay),
    (.serverCertificateUntrusted, true, .untrustedRelay),
    (.networkConnectionLost, true, .unreachable),
    (.cancelled, true, .unreachable),
]
for (code, viaRelay, expected) in errors {
    expectEqual(MacConnection.failure(for: URLError(code), viaRelay: viaRelay), expected, "URLError \(code.rawValue)")
}
expectEqual(MacConnection.failure(for: CocoaError(.fileNoSuchFile), viaRelay: true), .unreachable, "other errors")
expectEqual(MacConnection.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256")

print(failures == 0 ? "All \(checks) core checks pass." : "\(failures) of \(checks) core checks FAILED.")
exit(failures == 0 ? 0 : 1)
