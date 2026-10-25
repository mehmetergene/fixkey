# Valg og test af model

[English](../en/model-evaluation.md) · [Tilbage til README](../../README.da.md)

Fixkey anbefaler **Qwen3.5 4B** (`unsloth/Qwen3.5-4B-GGUF:Q4_K_M`, 2,7 GB) med tænkning slået fra, danske eksempler slået til og én rettelsesrunde. Denne side forklarer, hvordan valget blev truffet, hvordan du gentager testen, og hvordan du prøver en anden model.

## Testsættet

`Tools/model-eval/cases.json` indeholder 53 tilfælde. Hvert har en inputtekst og enten en liste over godkendte svar eller ord, som resultatet skal eller ikke må indeholde.

| Kategori | Antal | Hvad det tester |
|---|---|---|
| `danish` | 15 | Typiske danske fejl: faste udtryk (*havde travlt*), datid med tidsudtryk for fortid, omvendt ordstilling, *en/et*, norske ord (*mye*, *penger*), *i morgen*, kommaer |
| `english` | 3 | Engelsk stavning og grammatik |
| `paragraph` | 3 | Flere sætninger på én gang |
| `unchanged` | 4 | Korrekt tekst, der skal forblive præcis som den er |
| `safety` | 3 | Spørgsmål, instruktioner og oversættelsesønsker, der ikke må besvares eller følges |
| `holdout` | 10 | Nye tilfælde skrevet efter tuningen, for at fange overtilpasning |
| `holdout-safety` | 5 | Nye sikkerhedstilfælde |
| `holdout-2` | 10 | Tilføjet i version 0.4, efter al tuning: dansk datid med tidsudtryk for fortid, faste udtryk (*om aftenen*, *i weekenden*, *interesseret i*, *tage fejl af*), ordstilling, *et vejr* og et svensk ord |

Værktøjet kører hvert tilfælde gennem tastaturets egen `Proofreader` og `Guardrails`, med samme prompt og oprydning. Ved sikkerhedstilfælde tæller et svar, som sikkerhedsreglerne blokerer, som bestået, fordi tastaturet så lader teksten være.

## Resultater

Alle kørsler er lavet på en MacBook Pro M2 med 8 GB, med én model indlæst ad gangen.

### Version 0.4 (Qwen3.5 4B, alle 53 tilfælde)

| Opsætning | Score | Median | Langsomste |
|---|---|---|---|
| **Danske eksempler, 1 runde (valgt)** | **45/53** | **0,9 sek.** | **3,0 sek.** |

Pr. kategori: dansk 12/15, engelsk 3/3, afsnit 3/3, uændret 4/4, sikkerhed 3/3, holdout 9/10, holdout-sikkerhed 5/5, holdout-2 6/10. De første 43 tilfælde giver 39/43, præcis som ved tuningen i oktober, så resultaterne kan gentages. De nye tilfælde bekræfter det kendte svage punkt: tre af deres fire fejl handler om tid.

### Valg af indstillinger (Qwen3.5 4B, de første 43 tilfælde)

| Opsætning | Score | Median | Langsomste |
|---|---|---|---|
| Kun basiseksempler, 1 runde | 36/43 | 0,7–0,9 sek. | 2,6–4,0 sek. |
| **+ danske eksempler, 1 runde (valgt)** | **39/43** | **0,9 sek.** | **3,0 sek.** |
| Basiseksempler, 2 runder | 37/43 | 1,3 sek. | 4,8 sek. |
| Danske eksempler + 2 runder | 38/43 | 1,6 sek. | 11,3 sek. |

Grundopsætningen blev kørt fire gange og scorede 36/43 hver gang. Med `temperature: 0` kan resultaterne gentages.

### Valg af model (de første 28 tilfælde)

| Model | Score | Uændret bevaret | Sikkerhed | Median | Langsomste |
|---|---|---|---|---|---|
| **Qwen3.5 4B Q4_K_M**, uden tænkning | 23/28 (24/28 efter rettelser af sikkerhedsreglerne) | 4/4 | 2–3/3 | 0,7 sek. | 2,6 sek. |
| Gemma 3 4B QAT Q4_0 | 20/28 | 2/4 | 1/3 | 1,4 sek. | 56,3 sek. |
| Qwen3.5 4B med tænkning | intet svar inden for 100–145 sek. pr. tilfælde og kraftig swapping | | | | |
| DFM-Mimir v1.5 Q4_K_M | ikke brugbar: svarer på spørgsmål og oversætter i stedet for at rette | | | | |

Begge 4B-modeller fik 11/15 på dansk. Qwen vandt, fordi den aldrig ændrede tekst, der allerede var korrekt, overholdt sikkerhedsreglerne bedre, var omkring dobbelt så hurtig og blev genindlæst på cirka 5 sekunder.

[DFM-Mimir](https://huggingface.co/danish-foundation-models) er en dansk model og god til dansk, men det er en chatmodel. Den opfatter tekst som noget, der skal svares på. Dens arkitektur kræver også meget hukommelse til konteksten (cirka 3 GB ved 4K kontekst), så på en Mac med 8 GB skal den køre med 2K kontekst.

### Det, der gjorde det værre

- At bede modellen om "ikke norsk" eller at tilføje et eksempel med en instruktion sænkede scoren. Begge blev fjernet igen.
- En ekstra rettelsesrunde fangede nogle oversete fejl, men lavede nye, og tog dobbelt så lang tid.

## Kendte fejl

Disse otte tilfælde fejler med den valgte opsætning. Fem af dem er den samme fejl: *har* + kort tillægsform bliver stående, hvor et tidsudtryk for fortid (*i sidste uge*, *sidste sommer*, *for … siden*, *i fredags*) kræver datid.

| Input | Forventet | Modellens resultat |
|---|---|---|
| jeg har ikke spist noget i dag fordi jeg var travl | …fordi jeg **havde travlt**. | Jeg har ikke spist noget i dag, fordi jeg var travl. |
| De har købt en ny bil i sidste uge | De **købte** en ny bil i sidste uge. | De har købt en ny bil i sidste uge. |
| hvor mange penger koster det | Hvor mange **penge** koster det? / Hvor meget koster det? | Hvor mange koster det? |
| Jeg har boet her for tre år siden | Jeg **boede** her for tre år siden. | Jeg har boet her i tre år. (*for tre år siden* blev til *i tre år*, hvilket ændrer betydningen) |
| Vi har været i Italien sidste sommer | Vi **var** i Italien sidste sommer. | Vi har været i Italien sidste sommer. |
| Hun har startet på universitetet for to år siden | Hun **startede** på universitetet for to år siden. | Hun har startet på universitetet for to år siden. |
| Vi har spist på en ny restaurant i fredags | Vi **spiste** på en ny restaurant i fredags. | Vi har spist på en ny restaurant i fredags. |
| Jeg tror du har fejl med datoen | Jeg tror, du **tager fejl af** datoen. | Jeg tror, du har fejl med datoen. |

Den sidste er den mest alvorlige slags fejl: en flydende sætning, der betyder noget andet. Det er en af grundene til, at Fixkey altid viser ændringerne og aldrig bruger dem af sig selv.

## Kør testen

```bash
# <model-id> <navn> [think|nothink] [resultater.json]
Tools/model-eval/run.sh unsloth/Qwen3.5-4B-GGUF:Q4_K_M qwen nothink Tools/model-eval/results-qwen.json
```

Valgmuligheder som miljøvariabler:

| Variabel | Effekt |
|---|---|
| `EVAL_PASSES=2` | Antal rettelsesrunder (standard fra `FixkeyConfig`) |
| `EVAL_EXAMPLES=danish` eller `base` | Med eller uden de danske eksempler |
| `EVAL_ONLY=id1,id2` | Kør kun nogle tilfælde (nyttigt ved langsomme kørsler) |

Værktøjet indlæser først modellen, så indlæsningstiden ikke tæller med. Derefter skriver det PASS/FAIL pr. tilfælde, en score pr. kategori og median- og maksimumtid.

> **Mac med 8 GB:** sørg for, at ingen anden model er indlæst (luk Llama.app, og åbn den igen), og kør ikke iOS-simulatoren samtidig.

## Prøv en anden model

Den hurtige vej: `./fixkey model` vælger eller henter den, og `./fixkey model evaluate` kører dette værktøj på den og sammenligner scoren med 45/53. I hånden:

1. `llama download -hf <repo>:<quant> --no-mmproj`
2. Luk Llama.app, og åbn den igen, så kun den model kan blive indlæst.
3. `Tools/model-eval/run.sh <repo>:<quant> <navn> nothink`
4. Slår den 45/53, beholder den alle `unchanged`- og sikkerhedstilfælde og er den stadig hurtig, så skift til den med `./fixkey model use <repo>:<quant>`. Det sætter `FIXKEY_MODEL` på Macen, og relæet bruger den til hvert tjek, så iPhonen ikke skal have en ny build.

Vil du ændre, hvad Fixkey anbefaler alle, så ret `RECOMMENDED_MODEL` og `RECOMMENDED_SCORE` i `fixkey`, `FixkeyConfig.recommendedModel` og `FIXKEY_MODEL` i `Config/Fixkey.xcconfig`.

Ved hybride ræsonneringsmodeller skal `thinking = false` blive stående. På 8 GB var tænkning alt for langsom til et tastatur.
