# Status and roadmap

[Dansk](../da/roadmap.md) · [Back to README](../../README.md)

## Where it stands (October 2026, version 0.4)

Fixkey is a working prototype for personal use:

- The keyboard, word suggestions and autocorrect, the grammar check, guardrails and the encrypted Wi-Fi relay all work on a real iPhone.
- The recommended model scores 45 of 53 test cases, with a median check time of 0.9 s. You can choose another.
- It's tested on an iPhone and an M2 MacBook Pro with 8 GB.

## Milestones so far

1. **Simulator prototype:** app and keyboard extension, the `Proofreader` against Llama.app, and the try-it screen.
2. **Model selection:** the evaluation tool and test set. Gemma 3 4B, Qwen3.5 4B (thinking on and off) and DFM-Mimir were compared, and Qwen3.5 4B with thinking off won.
3. **Guardrails:** rules in code that block answers, translations and rewrites, plus the guardrail test suite.
4. **On the iPhone:** the Wi-Fi relay with a shared key, Bonjour name lookup, a Grammarly-style strip and card, and checks only on tap.
5. **Typing aids:** word suggestions, autocorrect with undo, long-press accents, space-bar cursor, word delete, and text replacements.
6. **Review fixes:** a code review found 12 issues; 11 were real, and all of those were fixed (selection handling, emoji cursor offsets, long-context trimming, stale results, truncated replies and more).
7. **Apple-accurate keys:** key sizes, gaps, colours and letter position measured from Apple's keyboard.
8. **Public release prep:** personal values and the key moved out of the code, and documentation in English and Danish.
9. **Version 0.4:**
   - **Guided setup:** double-click `Fixkey Setup.command`; `./fixkey` asks questions and does the setup, reinstalls and checks everything (`doctor`), and a newer version in a new folder takes over the earlier settings. [SETUP.md](../../SETUP.md) works for people and for AI assistants, with a plain-language [FAQ](faq.md).
   - **Runs by itself:** the relay starts when you log in, listens only on Wi-Fi networks you allow (stored as hashes), and opens Llama.app when a check needs it. A reminder the day before the 7 days end offers a one-click reinstall (`Reinstall Fixkey.command`), and every reinstall gives 7 new days.
   - **Your choice of model:** `./fixkey model` picks any model in Llama.app or from Hugging Face (the tested one is recommended), `./fixkey model evaluate` scores it on the test set, and the relay applies the Mac's choice, so the iPhone needs nothing.
   - **Security:** the relay is encrypted with a certificate the app pins, and five relay weaknesses found in a review are fixed (see [privacy-and-security.md](privacy-and-security.md#security-review-october-2026)).
   - **Choose your changes:** tap a change in the card to leave it out.
   - **Clear errors:** the app and keyboard say whether the Mac, the relay, Llama.app, the key or the certificate is the problem.
   - **Letters like Apple's:** measured on the iPhone in light and dark mode; lowercase letters are now larger and higher, as on Apple's keyboard.
   - **Tests:** relay tests, shared-code checks, keyboard unit tests, 10 new Danish model cases, and one test command (`Tools/test.sh`).
   - **No XcodeGen needed** to build: the Xcode project is committed.

## Known limitations

- **Same network only.** The keyboard reaches the Mac on the same Wi-Fi network or over the iPhone's Personal Hotspot, not over the internet.
- **The Mac must be on and awake,** on a Wi-Fi network you allowed. The first check after 5 idle minutes takes a few extra seconds.
- **Model misses.** Mostly Danish tense with past-time words, and some idioms; the model sometimes changes meaning (see [model-evaluation.md](model-evaluation.md)). Always read the card before accepting.
- **Free Apple ID.** The app must be reinstalled every 7 days, with the iPhone connected by cable (double-click `Reinstall Fixkey.command`).
- **No emoji key.** Use the globe key to switch to Apple's keyboard for emoji.
- **One check covers the text around the cursor:** up to about 800 characters on each side, in whole sentences.

## Ideas for next steps

| Idea | Why |
|---|---|
| A tense check for past-time words (*i går*, *sidste uge*, *for … siden*) | The model's most common miss |
| Reach the Mac away from home (for example over Tailscale) | Use Fixkey anywhere |
| Renew from the iPhone: a button in the app that asks the Mac to reinstall over Wi-Fi before the 7 days end | No cable needed |
| Server address and key set in the app instead of at build time | No rebuild when the Mac or key changes |
| Explanations per change (*why* it's wrong) | More like Grammarly. Needs a reliable format from a small model. |
| Try newer small models as they appear | Run them through `Tools/model-eval` |
| Emoji key | Parity with Apple's keyboard |
