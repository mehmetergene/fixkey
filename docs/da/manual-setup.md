# Manuel opsætning

[English](../en/manual-setup.md) · [Tilbage til README](../../README.da.md) · [Guidet opsætning](../../SETUP.da.md)

De fleste bør bruge den guidede [SETUP.da.md](../../SETUP.da.md): `Fixkey Setup.command` (eller `./fixkey setup`) gør alt herunder og tjekker hvert trin. Denne side er til udviklere, der vil gøre det i hånden eller forstå, hvad assistenten gør.

## Det skal du bruge

- En Mac med Apple silicon og mindst 8 GB hukommelse. 8 GB er nok til én 4B-model ad gangen.
- Xcode, logget ind med et Apple-id (**Settings › Apple Accounts**). Et gratis Personal Team virker; dets apps holder op med at åbne efter 7 dage.
- [Llama.app](https://llama.app), som har kommandolinjeværktøjet `llama` med.
- En iPhone med iOS 17 eller nyere, med Udviklertilstand slået til.

Testet på en iPhone og en MacBook Pro M2 med 8 GB. Macen og iPhonen skal være på samme Wi-Fi-netværk, eller Macen på iPhonens internetdeling.

## 1. Modellen

```bash
llama download -hf unsloth/Qwen3.5-4B-GGUF:Q4_K_M --no-mmproj
```

`--no-mmproj` springer modellens billeddel over, som Fixkey ikke bruger. Luk og åbn Llama.app, så den viser modellen.

På en Mac med 8 GB holder et kort kontekstvindue hukommelsesforbruget nede. Tilføj dette i `~/.config/llama/models.user.ini`, og genstart Llama.app:

```ini
[unsloth/Qwen3.5-4B-GGUF:Q4_K_M]
; Fixkey keyboard model: a small context keeps memory low on 8 GB Macs
ctx-size = 4096
```

Tjek, at modellen svarer:

```bash
Tools/proofread-cli/run.sh "jeg har ikke mye tid idag"
# OUT: Jeg har ikke meget tid i dag.
```

En anden model virker på samme måde: hent den med dens eget navn, `ejer/repo:KVANT`, og skriv navnet i `FIXKEY_MODEL` (nedenfor). `./fixkey model evaluate <navn>` giver den point ved siden af den anbefalede models 45/53.

## 2. Nøgle, certifikat og indstillinger

Alt personligt holdes ude af koden, i filer som git ignorerer:

| Fil | Hvad det er |
|---|---|
| `Tools/lan-relay/key.txt` | Den delte nøgle. Relæet kræver den ved hver forespørgsel. |
| `Tools/lan-relay/relay-cert.pem`, `relay-key.pem` | Relæets eget certifikat og private nøgle til HTTPS |
| `Config/Local.xcconfig` | Dit team, bundle-id-præfiks, Mac-navn, porte, nøglen og certifikatets fingeraftryk |

`./fixkey configure` laver dem alle (kun du kan læse dem). I hånden:

```bash
(umask 077
 openssl rand -hex 24 > Tools/lan-relay/key.txt
 openssl ecparam -name prime256v1 -genkey -noout -out Tools/lan-relay/relay-key.pem
 openssl req -new -x509 -key Tools/lan-relay/relay-key.pem -sha256 -days 3650 \
   -subj "/CN=Fixkey relay" -out Tools/lan-relay/relay-cert.pem)
openssl x509 -in Tools/lan-relay/relay-cert.pem -outform der | shasum -a 256   # fingeraftrykket
```

Kopiér så `Config/Local.example.xcconfig` til `Config/Local.xcconfig`, og udfyld den:

| Indstilling | Værdi |
|---|---|
| `DEVELOPMENT_TEAM` | Dit team-id. `./fixkey doctor` bekræfter, at Xcode kender det. |
| `FIXKEY_BUNDLE_ID_PREFIX` | Et omvendt domænenavn, der er dit eget, f.eks. `com.ditnavn`. Appen bliver `com.ditnavn.fixkey`, tastaturet `com.ditnavn.fixkey.keyboard`. |
| `FIXKEY_MAC_HOST` | Macens Bonjour-navn: `scutil --get LocalHostName` plus `.local` |
| `FIXKEY_RELAY_PORT` | Relæets port, f.eks. `9932`. Hold den forskellig fra Llama.apps port. |
| `FIXKEY_LLAMA_PORT` | Llama.apps port (`defaults read app.llama.Llama serverPort`, standard 9931). Bruges af simulatoren. |
| `FIXKEY_API_KEY` | Indholdet af `key.txt` |
| `FIXKEY_RELAY_CERT_SHA256` | Fingeraftrykket fra ovenfor |
| `FIXKEY_MODEL` | Modellen i Llama.app, som standard `unsloth/Qwen3.5-4B-GGUF:Q4_K_M`. Relæet sætter den ind i hver forespørgsel, så et skift kræver ingen ny build. |

Build-processen kopierer værdierne ind i hvert targets `Info.plist`. Appen stoler kun på certifikatet med det fingeraftryk.

## 3. Byg og installer

Xcode-projektet er committed, så du kan åbne `Fixkey.xcodeproj`, vælge din iPhone og trykke **Run**. Eller fra Terminal:

```bash
xcrun devicectl list devices          # din iPhones id
xcodebuild -project Fixkey.xcodeproj -scheme Fixkey -configuration Release \
  -destination 'id=<iphone-id>' -derivedDataPath build/device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <iphone-id> build/device/Build/Products/Release-iphoneos/Fixkey.app
```

Første gang skal du stole på dit Apple-id på iPhonen under **Indstillinger › Generelt › VPN og enhedsadministration**.

## 4. Start relæet

```bash
./fixkey relay          # eller: Tools/lan-relay/run.sh
# Fixkey relay is running on https://Din-Mac.local:9932  (Ctrl+C to stop)
```

- Det lytter kun på Macens Wi-Fi-adresse (`en0`) og følger med, når adressen skifter. Bruger du kabel, så angiv en adresse: `Tools/lan-relay/run.sh <adresse>`.
- Det læser sin port fra `Config/Local.xcconfig` og Llama.apps port fra Llama.apps egne indstillinger.
- Første gang spørger macOS måske, om Python må tage imod indgående forbindelser. Tillad det.
- Vil du hellere have, at det starter ved login, så kør `./fixkey autostart on`. Den kopierer relæet, nøglen og certifikatet til `~/Library/Application Support/Fixkey/relay` og installerer LaunchAgent'en `local.fixkey.relay`, som kun lytter på Wi-Fi-netværk, du har tilladt (`./fixkey autostart add`), og åbner Llama.app efter behov. [architecture.md](architecture.md#når-det-starter-af-sig-selv) har detaljerne.

Tjek det fra Macen: `./fixkey test` eller `python3 -I Tools/lan-relay/relay.py --check`. Den forbinder på samme måde som iPhonen (HTTPS, certifikatets fingeraftryk, nøgle) og siger, hvilken del der fejler.

## 5. Slå tastaturet til

På iPhonen:

1. Åbn Fixkey-appen. Tillad **Lokalt netværk**, når den spørger. Under **Your Mac** skal **Status** sige **Online**.
2. **Indstillinger › Apps › Fixkey › Tastaturer**: slå **Fixkey** og **Tillad fuld adgang** til.
3. Hold 🌐 nede i en hvilken som helst app, og vælg **Fixkey**.

## Ændring af indstillinger senere

- **Nyt Mac-navn, ny nøgle eller nyt certifikat:** kør `./fixkey configure` og derefter `./fixkey reinstall`. Vil du have en ny nøgle, så slet først `key.txt`; for et nyt certifikat sletter du `relay-key.pem`.
- **En anden model:** `./fixkey model`, eller ret `FIXKEY_MODEL`, og genstart relæet.
- **Hver 7. dag** med et gratis Apple-id: `./fixkey reinstall`, eller dobbeltklik på `Reinstall Fixkey.command`. Den sletter først Fixkeys gemte provisioneringsprofiler, så hver geninstallation giver 7 dage fra det øjeblik; et almindeligt **Run** i Xcode genbruger den gemte profil, til den udløber. `./fixkey reminder on` minder dig om det dagen før.

Problemer: kør `./fixkey doctor`, og se [spørgsmål og svar](faq.md#når-noget-ikke-virker).
