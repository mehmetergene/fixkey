// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

import Foundation

/// Danish takes the simple past, not "har" + participle, with a fixed time in the past:
/// "Vi har været i Italien sidste sommer" → "Vi var i Italien sidste sommer". Small models keep the "har" form even
/// with a worked example in the prompt, so this rule fixes it after the model. It changes a clause only when the
/// clause has a fixed past time and "har" followed by a participle it knows, and never when the clause also reaches
/// up to now ("siden i går", "i dag", "altid"), where "har" is right.
enum PastTense {
    /// `text` with each such "har" + participle turned into the simple past. Everything else stays as it was.
    static func apply(_ text: String) -> String {
        var tokens = tokenize(text)
        var clauses: [[Int]] = [[]]
        var sentenceOf: [Int: Int] = [:]
        var sentence = 0
        for (index, token) in tokens.enumerated() {
            if token.isWord {
                if clauseWords.contains(token.text.lowercased()), !clauses[clauses.count - 1].isEmpty { clauses.append([]) }
                clauses[clauses.count - 1].append(index)
                sentenceOf[index] = sentence
            } else {
                if token.text.contains(where: sentenceEnds.contains) { sentence += 1 }
                if token.text.contains(where: clauseEnds.contains), !clauses[clauses.count - 1].isEmpty { clauses.append([]) }
            }
        }

        var removed = Set<Int>()
        for clause in clauses {
            let words = clause.map { tokens[$0].text.lowercased() }
            let times = pastTimes(in: words)
            guard !times.isEmpty, !reachesNow(words, times: times) else { continue }
            for position in words.indices where words[position] == "har" {
                guard let participle = participle(after: position, in: words), let past = participles[words[participle]]
                else { continue }
                // A time after the participle must belong to this verb, not to a later subject and its verb.
                guard times.contains(where: { $0.lowerBound < position || !subject(between: participle, and: $0.lowerBound, in: words) })
                else { continue }
                guard !joinedParticiple(after: clause[participle], in: tokens, sentenceOf: sentenceOf) else { continue }
                tokens[clause[position]].text = matchingCase(past, of: tokens[clause[position]].text)
                removed.insert(clause[participle])
            }
        }
        guard !removed.isEmpty else { return text }

        // Each participle goes, together with the space before it.
        var result = ""
        for (index, token) in tokens.enumerated() where !removed.contains(index) {
            if !token.isWord, removed.contains(index + 1), token.text.allSatisfy(\.isWhitespace) { continue }
            result += token.text
        }
        return result
    }

    // MARK: Text

    private struct Token {
        var text: String
        let isWord: Bool
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        for character in text {
            let isWord = character.isLetter || character.isNumber
            if let last = tokens.last, last.isWord == isWord {
                tokens[tokens.count - 1].text.append(character)
            } else {
                tokens.append(Token(text: String(character), isWord: isWord))
            }
        }
        return tokens
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", ";", ":", "…", "\n"]
    private static let clauseEnds: Set<Character> = sentenceEnds.union([",", "(", ")", "–", "—"])
    /// Words that start a new clause. "at", "der" and "og" are left out: they also start infinitives, mean
    /// "there" or join objects, and the checks on subjects and joined participles cover their clauses.
    private static let clauseWords: Set<String> = ["som", "fordi", "når", "hvis", "mens", "selvom", "men", "da"]

    private static func matchingCase(_ word: String, of original: String) -> String {
        if original.count > 1, original == original.uppercased() { return word.uppercased() }
        if original.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }

    // MARK: Time

    private static let periods: Set<String> = [
        "uge", "måned", "år", "sommer", "vinter", "forår", "efterår", "weekend", "gang", "jul", "påske", "nat",
        "semester", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag", "søndag",
    ]
    private static let pastDays: Set<String> = [
        "går", "forgårs", "morges", "aftes", "mandags", "tirsdags", "onsdags", "torsdags", "fredags", "lørdags", "søndags",
    ]

    /// Word ranges of fixed past times: "i går", "i fredags", "(i) sidste uge", "for tre år siden", "dengang".
    private static func pastTimes(in words: [String]) -> [Range<Int>] {
        var times: [Range<Int>] = []
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            switch word {
            case "i" where pastDays.contains(next):
                times.append(index..<index + 2)
            case "sidste" where periods.contains(next):
                // "det sidste år" and "de sidste uger" reach up to now.
                if index == 0 || !["det", "den", "de", "disse", "hele"].contains(words[index - 1]) {
                    times.append(index..<index + 2)
                }
            case "for" where index + 2 < words.count:
                if let end = (index + 2..<min(index + 6, words.count)).first(where: { words[$0] == "siden" }) {
                    times.append(index..<end + 1)
                }
            case "dengang":
                times.append(index..<index + 1)
            default:
                break
            }
        }
        return times
    }

    /// True when the clause also points up to now, where "har" is right: "siden i går", "i dag", "altid", "hele ugen".
    private static func reachesNow(_ words: [String], times: [Range<Int>]) -> Bool {
        for (index, word) in words.enumerated() {
            if ["nu", "endnu", "altid", "aldrig", "nogensinde", "hele"].contains(word) { return true }
            if word == "i", index + 1 < words.count, ["dag", "år"].contains(words[index + 1]) { return true }
            if word == "siden", !times.contains(where: { $0.upperBound - 1 == index && words[$0.lowerBound] == "for" }) {
                return true
            }
        }
        return false
    }

    // MARK: Verbs

    private static let subjects: Set<String> = ["jeg", "du", "han", "hun", "vi", "de", "den", "det", "man", "der"]
    /// Pronouns that can only be subjects. "det", "den" and "de" also are objects and articles ("har haft det sjovt").
    private static let onlySubjects: Set<String> = ["jeg", "du", "han", "hun", "vi", "man"]
    private static let adverbs: Set<String> = [
        "ikke", "også", "lige", "allerede", "faktisk", "desværre", "bare", "kun", "jo", "nok", "vist", "endelig",
        "først", "netop", "egentlig", "heller", "sikkert", "måske",
    ]

    /// The position of the participle that belongs to "har" at `position`: after it, at most one subject (for
    /// "Har du set …?" and "I går har jeg …") and some adverbs.
    private static func participle(after position: Int, in words: [String]) -> Int? {
        var next = position + 1
        if next < words.count, subjects.contains(words[next]) { next += 1 }
        while next < words.count, adverbs.contains(words[next]) { next += 1 }
        return next < words.count && participles[words[next]] != nil ? next : nil
    }

    /// True when a subject and another word come between the participle and the time, as in
    /// "Jeg har sagt, at han kom i går": the time belongs to "kom".
    private static func subject(between participle: Int, and time: Int, in words: [String]) -> Bool {
        guard participle + 1 < time else { return false }
        return (participle + 1..<time).contains { onlySubjects.contains(words[$0]) && $0 + 1 < time }
    }

    /// True for "har spist og drukket": turning only the first participle would leave the second without "har".
    private static func joinedParticiple(after index: Int, in tokens: [Token], sentenceOf: [Int: Int]) -> Bool {
        let words = tokens.indices.filter { $0 > index && tokens[$0].isWord && sentenceOf[$0] == sentenceOf[index] }
            .map { tokens[$0].text.lowercased() }
        for (position, word) in words.enumerated() where word == "og" || word == "eller" {
            var next = position + 1
            while next < words.count, adverbs.contains(words[next]) { next += 1 }
            if next < words.count, participles[words[next]] != nil { return true }
        }
        return false
    }

    /// Participle → simple past for common verbs. Only these are changed. Left out on purpose: "vist" and "lidt"
    /// (also adverbs), "bestemt" (also "certainly"), "ladet" and "hængt" (two verbs with different past forms).
    static let participles: [String: String] = {
        let table = """
        været:var haft:havde blevet:blev gået:gik fået:fik stået:stod set:så sagt:sagde gjort:gjorde lagt:lagde
        sat:satte taget:tog kommet:kom givet:gav kunnet:kunne villet:ville skullet:skulle måttet:måtte turdet:turde
        burdet:burde vidst:vidste spurgt:spurgte valgt:valgte solgt:solgte fortalt:fortalte talt:talte bragt:bragte
        tænkt:tænkte holdt:holdt faldt:faldt slået:slog nået:nåede leet:lo bedt:bad bidt:bed brudt:brød budt:bød
        båret:bar drukket:drak fundet:fandt fløjet:fløj frosset:frøs grebet:greb grædt:græd hjulpet:hjalp
        krøbet:krøb ligget:lå løbet:løb løjet:løj lydt:lød nydt:nød redet:red revet:rev røget:røg siddet:sad
        skreget:skreg skrevet:skrev skudt:skød skåret:skar sluppet:slap smidt:smed sovet:sov sprunget:sprang
        steget:steg stjålet:stjal strøget:strøg stukket:stak sunget:sang sunket:sank svoret:svor truffet:traf
        trukket:trak tvunget:tvang vundet:vandt bundet:bandt forsvundet:forsvandt
        forstået:forstod bestået:bestod opstået:opstod foregået:foregik undgået:undgik modtaget:modtog
        overtaget:overtog deltaget:deltog foretaget:foretog vedtaget:vedtog optaget:optog ankommet:ankom
        opgivet:opgav udgivet:udgav beskrevet:beskrev underskrevet:underskrev tilbudt:tilbød forbudt:forbød
        fortsat:fortsatte oversat:oversatte udsat:udsatte ansat:ansatte planlagt:planlagde foreslået:foreslog
        fortrudt:fortrød forladt:forlod
        arbejdet:arbejdede boet:boede startet:startede sluttet:sluttede flyttet:flyttede lavet:lavede danset:dansede
        spillet:spillede snakket:snakkede grinet:grinede smilet:smilede regnet:regnede sneet:sneede hentet:hentede
        åbnet:åbnede lukket:lukkede vasket:vaskede ryddet:ryddede handlet:handlede inviteret:inviterede
        studeret:studerede reserveret:reserverede ændret:ændrede fejret:fejrede lovet:lovede svaret:svarede
        kigget:kiggede vandret:vandrede cyklet:cyklede sejlet:sejlede fisket:fiskede malet:malede tegnet:tegnede
        bygget:byggede repareret:reparerede installeret:installerede skiftet:skiftede tjekket:tjekkede
        printet:printede afleveret:afleverede erstattet:erstattede afsluttet:afsluttede vækket:vækkede
        vågnet:vågnede giftet:giftede forlovet:forlovede fyret:fyrede scoret:scorede trænet:trænede landet:landede
        lejet:lejede støvsuget:støvsugede husket:huskede mistet:mistede skadet:skadede brækket:brækkede
        ringet:ringede ventet:ventede prøvet:prøvede mailet:mailede diskuteret:diskuterede troet:troede
        elsket:elskede hadet:hadede savnet:savnede ønsket:ønskede håbet:håbede klaret:klarede fejlet:fejlede
        dumpet:dumpede stoppet:stoppede glædet:glædede moret:morede kedet:kedede barberet:barberede
        hvisket:hviskede lyttet:lyttede mærket:mærkede lugtet:lugtede trykket:trykkede klikket:klikkede
        slettet:slettede postet:postede forklaret:forklarede passet:passede reddet:reddede smeltet:smeltede
        styrtet:styrtede vokset:voksede overlevet:overlevede dukket:dukkede skinnet:skinnede opdaget:opdagede
        overvejet:overvejede oplevet:oplevede overrasket:overraskede besluttet:besluttede ledet:ledede
        købt:købte spist:spiste rejst:rejste læst:læste brugt:brugte betalt:betalte besøgt:besøgte begyndt:begyndte
        glemt:glemte gemt:gemte sendt:sendte tabt:tabte kørt:kørte hørt:hørte mødt:mødte lært:lærte kogt:kogte
        stegt:stegte bagt:bagte tjent:tjente lånt:lånte aftalt:aftalte ment:mente følt:følte drømt:drømte
        råbt:råbte smagt:smagte rørt:rørte delt:delte fulgt:fulgte stemt:stemte nævnt:nævnte hilst:hilste
        tændt:tændte brændt:brændte sket:skete hændt:hændte født:fødte skyndt:skyndte klædt:klædte
        undervist:underviste forsøgt:forsøgte aflyst:aflyste bestilt:bestilte forberedt:forberedte ledt:ledte
        trådt:trådte
        """
        var map: [String: String] = [:]
        for pair in table.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: ":")
            map[String(parts[0])] = String(parts[1])
        }
        return map
    }()
}
