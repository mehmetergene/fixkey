# Status og køreplan

[English](../en/roadmap.md) · [Tilbage til README](../../README.da.md)

## Hvor står det (oktober 2026, version 0.4)

Fixkey er en fungerende prototype til personligt brug:

- Tastaturet, ordforslag og autokorrektur, grammatiktjekket, sikkerhedsreglerne og det krypterede Wi-Fi-relæ virker alle på en rigtig iPhone.
- Den anbefalede model klarer 45 af 53 testtilfælde med en mediantid på 0,9 sek. pr. tjek. Du kan vælge en anden.
- Den er testet på en iPhone og en MacBook Pro M2 med 8 GB.

## Milepæle indtil nu

1. **Prototype i simulatoren:** app og tastaturudvidelse, `Proofreader` mod Llama.app og prøv-det-skærmen.
2. **Valg af model:** testværktøjet og testsættet. Gemma 3 4B, Qwen3.5 4B (med og uden tænkning) og DFM-Mimir blev sammenlignet, og Qwen3.5 4B uden tænkning vandt.
3. **Sikkerhedsregler:** regler i koden, der blokerer svar, oversættelser og omskrivninger, plus testsættet til reglerne.
4. **På iPhonen:** Wi-Fi-relæet med delt nøgle, opslag via Bonjour-navn, bjælke og kort i Grammarly-stil og tjek kun ved tryk.
5. **Hjælp til skrivningen:** ordforslag, autokorrektur med fortryd, accenter ved langt tryk, markør via mellemrumstasten, sletning af hele ord og teksterstatninger.
6. **Rettelser efter gennemgang:** en kodegennemgang fandt 12 problemer; 11 var reelle, og de blev alle rettet (markeret tekst, markørpositioner med emoji, beskæring af lang tekst, forældede resultater, afbrudte svar og mere).
7. **Taster som Apples:** tasternes størrelse, afstande, farver og bogstavernes placering målt på Apples tastatur.
8. **Klar til offentliggørelse:** personlige værdier og nøglen flyttet ud af koden og dokumentation på engelsk og dansk.
9. **Version 0.4:**
   - **Guidet opsætning:** dobbeltklik på `Fixkey Setup.command`; `./fixkey` stiller spørgsmål og klarer opsætningen, geninstallerer og tjekker det hele (`doctor`), og en nyere udgave i en ny mappe overtager de tidligere indstillinger. [SETUP.da.md](../../SETUP.da.md) virker for mennesker og for AI-assistenter, med [spørgsmål og svar](faq.md) i et enkelt sprog.
   - **Kører af sig selv:** relæet starter, når du logger ind, lytter kun på Wi-Fi-netværk, du tillader (gemt som hashes), og åbner Llama.app, når et tjek har brug for den. En påmindelse dagen før de 7 dage slutter tilbyder at geninstallere med ét klik (`Reinstall Fixkey.command`), og hver geninstallation giver 7 nye dage.
   - **Dit valg af model:** `./fixkey model` vælger enhver model i Llama.app eller fra Hugging Face (den testede anbefales), `./fixkey model evaluate` giver den point på testsættet, og relæet bruger Macens valg, så iPhonen behøver intet.
   - **Sikkerhed:** relæet er krypteret med et certifikat, som appen låser sig til, og fem svagheder i relæet, som en gennemgang fandt, er rettet (se [privacy-and-security.md](privacy-and-security.md#sikkerhedsgennemgang-oktober-2026)).
   - **Vælg dine ændringer:** tryk på en ændring i kortet for at springe den over.
   - **Tydelige fejl:** appen og tastaturet siger, om problemet er Macen, relæet, Llama.app, nøglen eller certifikatet.
   - **Bogstaver som Apples:** målt på iPhonen i lys og mørk tilstand; små bogstaver er nu større og sidder højere, ligesom på Apples tastatur.
   - **Test:** test af relæet, tjek af den fælles kode, enhedstest af tastaturet, 10 nye danske modeltilfælde og én testkommando (`Tools/test.sh`).
   - **Ingen XcodeGen nødvendig** for at bygge: Xcode-projektet er committed.

## Kendte begrænsninger

- **Kun samme netværk.** Tastaturet når Macen på samme Wi-Fi-netværk eller over iPhonens internetdeling, ikke over internettet.
- **Macen skal være tændt og vågen** og på et Wi-Fi-netværk, du har tilladt. Det første tjek efter 5 minutter uden brug tager et par sekunder ekstra.
- **Modellens fejl.** Mest dansk datid med tidsudtryk for fortid og nogle faste udtryk; modellen ændrer af og til betydningen (se [model-evaluation.md](model-evaluation.md)). Læs altid kortet, før du accepterer.
- **Gratis Apple-id.** Appen skal geninstalleres hver 7. dag med iPhonen forbundet med kabel (dobbeltklik på `Reinstall Fixkey.command`).
- **Ingen emoji-tast.** Brug globustasten til at skifte til Apples tastatur for at skrive emoji.
- **Et tjek dækker teksten omkring markøren:** op til cirka 800 tegn på hver side, i hele sætninger.

## Idéer til næste skridt

| Idé | Hvorfor |
|---|---|
| Et tjek af datid ved tidsudtryk for fortid (*i går*, *sidste uge*, *for … siden*) | Modellens hyppigste fejl |
| Nå Macen, når du ikke er hjemme (for eksempel over Tailscale) | Brug Fixkey overalt |
| Forny fra iPhonen: en knap i appen, der beder Macen geninstallere over Wi-Fi, før de 7 dage slutter | Intet kabel nødvendigt |
| Serveradresse og nøgle sat i appen i stedet for ved build | Ingen ny build, når Macen eller nøglen skifter |
| Forklaring pr. ændring (*hvorfor* det er forkert) | Mere som Grammarly. Kræver et pålideligt format fra en lille model. |
| Prøv nye små modeller, når de kommer | Kør dem gennem `Tools/model-eval` |
| Emoji-tast | Som på Apples tastatur |
