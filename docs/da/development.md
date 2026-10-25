# Udvikling og test

[English](../en/development.md) · [Tilbage til README](../../README.da.md)

## Xcode-projektet

`project.yml` er kilden til sandheden. `Fixkey.xcodeproj` genereres ud fra den med [XcodeGen](https://github.com/yonaskolb/XcodeGen) og er committed, så dem, der bare bygger appen, ikke behøver XcodeGen. Når du har ændret `project.yml` eller tilføjet eller fjernet filer:

```bash
xcodegen generate
```

og commit `project.yml` og `Fixkey.xcodeproj` sammen.

Koden i `Shared/` skal også kunne bygges på macOS, fordi Mac-værktøjerne kompilerer den. Hold UIKit ude af den.

## Test

```bash
Tools/test.sh               # hurtigt: sikkerhedsregler, fælles kode, relæ, påmindelse, opsætningsscripts (ingen model, ingen simulator)
Tools/test.sh --simulator   # også tastaturets enhedstest i iOS-simulatoren
Tools/test.sh --model       # også modeltesten (kræver Llama.app med modellen)
```

Den skriver én linje pr. testsæt; hele outputtet ligger i `build/test-*.log`.

| Testsæt | Hvad det dækker | Kræver |
|---|---|---|
| `Tools/guardrail-check/run.sh` | 26 håndskrevne svar, som [sikkerhedsreglerne](guardrails.md) skal tillade eller blokere | Intet |
| `Tools/core-check/run.sh` | Forskellen ord for ord og accept af nogle ændringer (også mellemrum, linjeskift og emoji), oprydning af svaret, hvad et tjek dækker, datidsreglen (44 sætninger, der skal ændres eller blive som de er), og hvad netværksfejl betyder | Intet |
| `python3 -I Tools/lan-relay/test_relay.py` | Relæet mod en falsk Llama.app: HTTPS og certifikatet, nøglen, stier, størrelser, langsomme og passive klienter, grænsen for forbindelser, logs, den valgte model, åbning af Llama.app efter behov, netværks-id'er og tilladte netværk, `--check` | Intet |
| `Tools/reminder/test.sh` | Fornyelsen og påmindelsen med et falsk ur, en falsk dialog og en erstatning for `./fixkey`: fornyelse fra 2 dage før, højst hver 3. time, en notifikation, når den er fornyet, beskeden om login én gang, påmindelsen, når fornyelsen fejler (dagen før, derefter hver 12. time), **Geninstaller** åbner kommandoen, danske tekster | Intet |
| `FixkeyTests` (Xcode) | Tastaturmodellen med et tekstfelt af almindelig tekst: accept af alle, nogle eller ingen ændringer, tekst der er ændret imens, skrivning, store bogstaver, sletning af ord, beskeder og den tekst med ændringer, man kan trykke på | iOS-simulator |
| `Tools/model-eval/run.sh` | Modellen på 53 tilfælde, se [model-evaluation.md](model-evaluation.md) | Llama.app med modellen |

## Mac-værktøjer

Alle værktøjer køres fra repositoryets rod. Swift-værktøjerne kompilerer `Shared/` sammen med deres egen `main.swift` i en midlertidig mappe, så de altid tester den samme kode, som tastaturet bruger.

| Kommando | Hvad den gør | Kræver modellen |
|---|---|---|
| `./fixkey setup` | Den guidede opsætning ([SETUP.da.md](../../SETUP.da.md)) | Ja |
| `./fixkey doctor` | Tjekker det hele og siger, hvad der skal rettes | Nej |
| `./fixkey configure` | Laver nøglen, certifikatet og `Config/Local.xcconfig` eller overtager dem fra mappen, der blev sat op før | Nej |
| `./fixkey reinstall` | Bygger en release-udgave med en ny 7-dages profil og installerer den på iPhonen | Nej |
| `./fixkey model [use <id> \| evaluate [<id>]]` | Vælger modellen (en liste eller den angivne `ejer/repo:KVANT` fra Hugging Face) eller giver den point som `Tools/model-eval` | Ja |
| `./fixkey autostart on\|off\|add` | Starter relæet ved login på tilladte netværk, holder op med det eller tillader det nuværende netværk | Nej |
| `./fixkey reminder on\|off` | Fornyelse af sig selv over Wi-Fi med påmindelsen, når den ikke kan | Nej |
| `./fixkey renew` | Bygger og installerer over Wi-Fi uden spørgsmål, som fornyelsen gør. Slutkode 0 fornyet, 3 iPhonen kan ikke nås, 4 Xcode skal have Apple-id'et, 1 andet. | Nej |
| `./fixkey relay` | Kører Wi-Fi-relæet i vinduet, når det ikke starter af sig selv. Stop det med Ctrl+C. | Ja |
| `./fixkey test` | Tjekker det kørende relæ på samme måde, som iPhonen forbinder | Ja |
| `./fixkey uninstall` | Fjerner LaunchAgents og deres filer og logs | Nej |
| `Tools/proofread-cli/run.sh ["tekst" …]` | Retter eksempelsætninger eller dine egne og viser resultatet, forskellen ord for ord og tiden | Ja |
| `Tools/model-eval/run.sh <model> <navn> [think\|nothink] [ud.json]` | Giver en model point på testtilfældene | Ja |
| `swift Tools/app-icon/make-icon.swift <ud.png>` | Tegner app-ikonet i 1024 × 1024. Fjern alfakanalen bagefter med `magick <ud.png> -alpha off <ud.png>`. | Nej |

`./fixkey` tager `--yes` (brug de foreslåede svar, og vent aldrig på Enter; sker også automatisk, når der ingen terminal er) og `--lang en|da`. Sådan styrer en AI-assistent eller et script den. Uden en kommando viser den en menu, som intet gør uden en terminal; `./fixkey help` viser alle kommandoer.

Eksempel:

```bash
$ Tools/proofread-cli/run.sh "i has went to the store yesterday and buyed three apple"
IN : i has went to the store yesterday and buyed three apple
OUT: I went to the store yesterday and bought three apples.
DIF: [-i-] [-has-] {+I+} went to the store yesterday and [-buyed-] {+bought+} three [-apple-]{+apples+}{+.+}
     2348 ms
```

## Startargumenter til debug

Debug-builds af appen tager imod disse startargumenter. Sæt dem i Xcode under **Product › Scheme › Edit Scheme › Run › Arguments**, eller giv dem til `simctl launch` og `devicectl … process launch`.

| Argument | Effekt |
|---|---|
| `-FixkeyKeyboardPreview letters` | Åbner det fulde tastatur inde i appen i stedet for den normale skærm. Andre tilstande: `capitals` (et tomt felt, så tasterne viser store bogstaver), `numbers`, `strip` (et resultat i bjælken), `card` (forslagskortet), `card-choice` (kortet med én ændring slået fra), `suggestions` (ordforslag til "hjæl"). |
| `-FixkeyDemoText "tekst"` | Sætter teksten ind i prøv-det-feltet og retter den med det samme |
| `-FixkeyFocusInput YES` | Sætter fokus i prøv-det-feltet, så det aktuelle tastatur vises. Nyttigt til skærmbilleder af Apples tastatur til sammenligning. |
| `-FixkeyServerURL https://vært:port` | Bruger en anden server |

## Simulator

Simulatoren taler direkte med Llama.app på samme Mac, så relæet er ikke nødvendigt.

```bash
xcodebuild -project Fixkey.xcodeproj -scheme Fixkey \
  -destination 'platform=iOS Simulator,name=<simulator>' -derivedDataPath build/sim build
xcrun simctl boot "<simulator>"
xcrun simctl install booted build/sim/Build/Products/Debug-iphonesimulator/Fixkey.app
xcrun simctl launch booted com.ditnavn.fixkey -FixkeyKeyboardPreview card
xcrun simctl io booted screenshot skaermbillede.png
```

`xcrun simctl list devices available` viser de simulatorer, du har.

- Xcode 27 har ikke noget Simulator-vindue. `simctl` virker uden.
- Simulatoren mangler som regel en dansk ordbog. Fixkey opdager det og slår danske ordforslag og autokorrektur fra der. Test dem på en rigtig iPhone.
- På en Mac med 8 GB skal du lukke simulatoren (`xcrun simctl shutdown all`), før du kører modeltest.

## Enhed

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device <id> build/device/Build/Products/Release-iphoneos/Fixkey.app
xcrun devicectl device process launch --terminate-existing --device <id> com.ditnavn.fixkey
xcrun devicectl device capture screenshot --device <id> --destination skaermbillede.png
```

Appens række **Your Mac › Status** er et hurtigt tjek hele vejen igennem: den kalder `GET /v1/models` gennem relæet med nøglen og det låste certifikat og siger, hvilken del der fejler.

## Relæet og påmindelsen i baggrunden

```bash
launchctl print gui/$(id -u)/local.fixkey.relay | grep -E 'state|pid'   # kører det?
tail -f ~/Library/Logs/Fixkey/relay.log                                    # hvad det gør
python3 -I Tools/lan-relay/relay.py --network-id                           # dette netværks id
python3 -I Tools/lan-relay/relay.py --on-allowed-network ~/Library/Application\ Support/Fixkey/networks.txt && echo tilladt
```

Vil du prøve påmindelsen uden at vente på datoen, så kør dens script mod en testmappe med et falsk ur; `FIXKEY_DRY_RUN` skriver dialogen ud i stedet for at vise den og gør, som om der blev klikket på dens værdi:

```bash
FIXKEY_SUPPORT_DIR=/tmp/fixkey-test FIXKEY_NOW=$(date +%s) FIXKEY_DRY_RUN=Later bash Tools/reminder/remind.sh
```

Mappen skal have en `expiry`-fil (sekunder siden 1970) og en `reminder.conf`, som `Tools/reminder/test.sh` viser. `FIXKEY_RENEW_COMMAND` sætter en erstatning i stedet for `./fixkey renew`.

Vil du forny nu, som påmindelsen gør, fra kopien i Application Support: `~/Library/Application\ Support/Fixkey/source/fixkey renew`. Dens log er `~/Library/Logs/Fixkey/renew.log`.

## Før et commit

1. `Tools/test.sh --simulator`: alle testsæt skal bestå.
2. Er prompten, eksemplerne, sikkerhedsreglerne eller modellen ændret: `Tools/test.sh --model`, og sammenlign med 50/53.
3. Byg til enheden, og prøv et tjek i en rigtig app (Noter, Beskeder).
4. `git status`: sørg for, at `Config/Local.xcconfig`, `Tools/lan-relay/key.txt` og `relay-*.pem`-filerne ikke står på listen.
