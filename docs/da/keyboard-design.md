# Tastaturets design

[English](../en/keyboard-design.md) · [Tilbage til README](../../README.da.md)

Fixkey skal føles som iPhonens eget tastatur med én ekstra knap. iOS tillader ikke en tastaturudvidelse at indlejre Apples tastatur, så Fixkey genskaber det ud fra mål taget på skærmbilleder af Apples danske tastatur.

## Layout

Fixkey er 251 pt højt: en bjælke på 42 pt og et tasteområde på 209 pt.

```text
┌─────────────────────────────────────────────┐
│ (✓)  Ret teksten · ordforslag                │  bjælke, 42 pt
├─────────────────────────────────────────────┤
│  q  w  e  r  t  y  u  i  o  p  å            │
│  a  s  d  f  g  h  j  k  l  æ  ø            │  taster, 209 pt
│  ⇧     z  x  c  v  b  n  m     ⌫            │
│ 123  (🌐)  ________ mellemrum ______  ↵      │
└─────────────────────────────────────────────┘
```

- **Bogstaver:** dansk QWERTY med å sidst i øverste række og æ og ø sidst i midterste række.
- **Tredje række:** smalle skift- og slettetaster (41 pt) i kanterne. Z–M står i de samme kolonner som E–O, ligesom på Apples tastatur.
- **Nederste række:** 123/ABC, globus (kun når iOS beder om den), mellemrum og retur. Der er ingen emoji-tast; mellemrumstasten er bredere i stedet.
- **Tal- og symbolsider:** dansk talrække med `kr` og en ekstra symbolside med `£ € $`.
- **Returtasten:** som standard symbolet `return.left`. Beder tekstfeltet om en særlig tekst, vises ordet på dansk: *søg, send, gå, næste, færdig, tilmeld, rute, fortsæt*.
- **Mellemrumstasten:** uden tekst, men med et lille gråt "DA" ligesom på Apples.

## Målte værdier

Målt på 3×-skærmbilleder af Apples tastatur på en iPhone. I version 0.4 blev målingen gentaget automatisk på iPhonen i lys og mørk tilstand (en UI-test skifter udseende og tastatur), og Fixkeys bogstaver passer nu med Apples ned til pixlen.

| Mål | Værdi |
|---|---|
| Tastehøjde | 43 pt |
| Afstand mellem taster | 6 pt |
| Afstand mellem rækker | 11 pt |
| Sidemargen | 6,5 pt |
| Topmargen | 4 pt |
| Bredde på skift og slet | 41 pt |
| Bredde på 123-tasten | 43,3 pt |
| Bredde på returtasten | 93 pt |
| Hjørneradius | 8,5 pt, bløde (continuous) hjørner |
| Små bogstaver | 24,5 pt, løftet 2,4 pt over tastens midte. Apple tegner små bogstaver større end store. |
| Store bogstaver | 21,3 pt, løftet 1,2 pt over tastens midte (et centreret bogstav ser for lavt ud) |
| Tal og tegn | 22 pt, løftet 1,2 pt |
| Tekststørrelse (123, ord) | 18 pt |
| Symbolstørrelse (skift, slet, retur) | 20 pt |
| Tastefarve, mørk tilstand | #444444 (Apples måles til #444444–#464646), ens for bogstaver og funktionstaster, ingen skygge |
| Trykket tast, mørk tilstand | #6B6B6B |
| Tastefarve, lys tilstand | #FFFFFF, ens for bogstaver og funktionstaster, ingen skygge; trykket ≈ #BDC2C9 (anslået) |

## Skriveadfærd

| Handling | Adfærd |
|---|---|
| Tryk på en tast | Lyser op ved berøring og skriver, når du slipper. En popup viser bogstavet. |
| To tommelfingre | Rollover med flere fingre, så hurtig skrivning ikke taber bogstaver |
| Hold et bogstav (0,4 sek.) | Accenter: a → æ å ä á à…, o → ø ö ó…, e → é è ê… med flere |
| Skift | Ét tryk giver ét stort bogstav, dobbelttryk giver caps lock |
| Automatisk stort bogstav | Følger tekstfeltets indstilling (sætninger, ord, alt eller intet) |
| Dobbelt mellemrum | Skriver ". " ligesom Apples tastatur |
| Hold slet | Gentager og sletter derefter hele ord |
| Træk på mellemrumstasten | Flytter markøren |
| Feedback | Kun systemets tasteklik (følger **Indstillinger › Lyde og haptik › Tastaturfeedback**). Ingen vibration. |

## Fixkey-bjælken og kortet

Fixkeys tjek-brugerflade følger Grammarlys tastatur:

- **Ikonet** (`text.badge.checkmark`) sidder yderst til venstre i bjælken. Tryk på det for at tjekke. Et rødt mærke viser, hvor mange ændringer der venter.
- **Bjælkens tilstande:** *Tryk for at tjekke teksten* (hvile) → *Tjekker…* → den første ændring som en chip (*Ret teksten* over erstatningen i grønt), *Ser godt ud*, når der intet er at rette, eller en kort fejlbesked.
- **Ordforslag** overtager bjælken, mens du skriver et ord, ligesom QuickType-bjælken. Trykker du på et forslag, erstatter det ordet; første plads beholder det, du skrev.
- **Kortet** erstatter tasterne:
  - overskrift: *Korrekthed: Ret teksten*;
  - din tekst med ændringerne markeret: fjernede ord i rødt og overstreget, tilføjede ord i grønt;
  - tryk på en ændring for at slå den fra: dine egne ord bliver stående med en prikket understregning, og forslaget bliver gråt og overstreget. Tryk igen for at slå den til;
  - en opsummering: *Fixkey fandt 3 rettelser. Tryk på en for at fravælge den.*, eller *2 af 3 rettelser valgt.*, når du har slået en fra;
  - **Accepter** (grøn) bruger de ændringer, der er slået til, **Afvis** kasserer dem alle, og ⌨ går tilbage til tasterne og gemmer forslaget bag mærket. Mærket tæller de ændringer, der er slået til.

Al tekst på tastaturet er på dansk. Selve appen er på engelsk.

## App-ikon

En grøn afrundet firkant med et hvidt tekst-og-flueben-symbol. Den laves af `Tools/app-icon/make-icon.swift` (se [development.md](development.md)).
