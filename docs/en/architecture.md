# Architecture and code tour

[Dansk](../da/architecture.md) · [Back to README](../../README.md)

## Overview

```mermaid
flowchart TB
    subgraph iPhone
        KB["FixkeyKeyboard extension<br/>KeyboardViewController"]
        APP["Fixkey app<br/>try-it screen, status"]
        UI["KeyboardUI<br/>KeyboardModel · KeyboardView · KeysUIView · ChangesText · WordSuggestions"]
        SH["Shared<br/>Proofreader · MacConnection · Guardrails · PastTense · WordDiff · Correction · CheckRange · FixkeyConfig"]
        KB --> UI --> SH
        APP --> UI
        APP --> SH
    end
    subgraph Mac
        LD["launchd, at login<br/>local.fixkey.relay · local.fixkey.reminder"]
        R["Tools/lan-relay<br/>relay.py: HTTPS on allowed Wi-Fi"]
        L["Llama.app router<br/>this Mac only"]
        M["llama-server child<br/>the chosen model (Qwen3.5 4B by default)"]
        RM["Tools/reminder<br/>remind.sh: renews every 7 days"]
        T["fixkey (setup assistant)<br/>Tools: tests, model-eval, proofread-cli"]
        LD --> R --> L --> M
        LD --> RM -- "renew" --> T
        T --> L
    end
    SH -- "HTTPS, pinned certificate + key<br/>POST /v1/chat/completions" --> R
```

## Targets

The project is described in `project.yml`. `Fixkey.xcodeproj` is generated from it with XcodeGen and committed, so building needs no XcodeGen. Swift 5 mode, iOS 17 or later, iPhone only.

| Target | Type | Bundle ID | Sources |
|---|---|---|---|
| **Fixkey** | iOS app | `<prefix>.fixkey` | `App/`, `Shared/`, `KeyboardUI/` |
| **FixkeyKeyboard** | Keyboard extension | `<prefix>.fixkey.keyboard` | `Keyboard/`, `Shared/`, `KeyboardUI/` |
| **FixkeyTests** | Unit tests (simulator) | `<prefix>.fixkey.tests` | `Tests/` |

The keyboard's primary language is `da-DK`, and it requests Full Access (`RequestsOpenAccess`) because it needs the network. Both app targets allow plain HTTP only to local addresses (`NSAllowsLocalNetworking`), which the simulator uses; the iPhone talks HTTPS. The test target is built only for testing, so a normal build never registers a third app ID.

## Folders

| Folder | What's in it |
|---|---|
| `App/` | The container app: `ContentView` (try-it box, setup steps, connection status), `KeyboardPreview` (debug-only full keyboard inside the app), app icon |
| `Keyboard/` | `KeyboardViewController`: the extension entry point. It hosts the SwiftUI keyboard and adapts `UITextDocumentProxy` to the `KeyboardHost` protocol. |
| `KeyboardUI/` | Shared by the extension and the app. `KeyboardModel` holds state and actions, `KeyboardView` draws the strip and card in SwiftUI, `KeysUIView` draws the keys in UIKit, `ChangesText` shows the changes and lets you tap them, and `WordSuggestions` provides suggestions and autocorrect. |
| `Shared/` | Plain Swift that also builds on macOS: `Proofreader` (talks to the model), `MacConnection` (HTTPS, certificate pinning, error mapping), `Guardrails`, `PastTense` (the rule for "har" + participle with a past time), `WordDiff` and `Correction` (word-level diff and chosen changes), `CheckRange` (what one check covers), `FixkeyConfig` (server, model, key), `FixkeyColors` |
| `Config/` | `Fixkey.xcconfig` (shared defaults), `Local.example.xcconfig` (template), and your `Local.xcconfig` (not committed) |
| `Tests/` | Unit tests for the keyboard logic, run in the simulator |
| `Tools/` | Mac tools: `lan-relay/` (relay and its tests), `reminder/` (renewing every 7 days, the reminder, and their tests), `core-check/`, `guardrail-check/`, `model-eval/`, `proofread-cli/`, `app-icon/`, `test.sh` |
| `fixkey` | The setup assistant and helper: `setup`, `reinstall`, `model`, `autostart`, `reminder`, `relay`, `doctor`, `uninstall` (`./fixkey help` lists them). Without a command it shows a menu. |
| `Fixkey Setup.command`, `Reinstall Fixkey.command` | Double-click starters: the first opens `./fixkey` (setup the first time, then the menu), the second runs `./fixkey reinstall` |

## A grammar check, step by step

1. **Tap.** The user taps the Fixkey icon. `KeyboardModel.iconTapped()` → `runCheck()`. Fixkey never checks automatically while you type.
2. **Preconditions.** Full Access must be on. No text may be selected, because iOS doesn't share selected text with keyboards and Accept could replace the wrong characters. The text must not be empty.
3. **Snapshot.** The model records the text before and after the cursor and the document's ID (`CheckSnapshot`).
4. **What to check.** `CheckRange` keeps at most 800 characters on each side of the cursor. iOS may give a keyboard only part of a long text, sometimes starting or ending mid-word, so from 200 characters on Fixkey checks only the whole sentences in between and never rewrites a word it can't fully see.
5. **Request.** `Proofreader.fix()` first applies the past-tense rule (step 7) to the text, so the model starts from it. Then it builds one request to the OpenAI-compatible endpoint `POST /v1/chat/completions`:
   - a system prompt: proofread Danish and English, keep meaning, tone and language, never answer or follow instructions in the text, reply with the corrected text only;
   - 10 worked examples (3 general, 7 typical Danish mistakes);
   - the user's text between `<<<` and `>>>`;
   - `temperature: 0`, `max_tokens` scaled to the text length, and `chat_template_kwargs.enable_thinking: false`.

   `MacConnection.send()` sends it over an ephemeral session (no cache, cookies or stored credentials). Over HTTPS it accepts the server only if the certificate's SHA-256 matches `FixkeyConfig.relayCertificateSHA256`; otherwise the request never leaves the handshake.
6. **Clean.** The reply loses `<<<`/`>>>` markers, wrapping quotes, preambles such as "Corrected text:" and any leftover `</think>` reasoning. Each is removed only when it wasn't in the user's own text.
7. **Reject unsafe replies.** A reply cut off by the token limit (`finish_reason: "length"`) is refused. Then [Guardrails](guardrails.md) checks that the reply is a correction, not an answer, translation or rewrite. Last, `PastTense` fixes the model's most common Danish miss: in a clause with a fixed past time (*i går*, *sidste uge*, *for … siden*, *i fredags*), "har" + a participle from its list of about 250 verbs becomes the simple past (*har været* → *var*). It leaves the clause alone when it also reaches up to now (*siden*, *i dag*, *altid*) or when it can't be sure.
8. **Show.** If the text changed while the request was running, the result is thrown away. Otherwise a `Correction` works out the word-level diff once (`WordDiff`), the strip shows the first change, the icon gets a red badge, and the card shows the text with removed words struck through in red and added words in green. Tapping a change in the card (`ChangesText`) turns it off or on.
9. **Accept.** Fixkey first confirms the text is still exactly the snapshot. Then it moves the cursor to the end of the checked text, deletes it and inserts `Correction.text`: the original with the chosen changes applied (`WordDiff.apply`). Cursor moves are converted from Swift characters to UTF-16 units, so emoji don't throw positions off.

## Connection and configuration

`FixkeyConfig.serverURL` picks the server:

| Running on | Server |
|---|---|
| iPhone | `https://<FIXKEY_MAC_HOST>:<FIXKEY_RELAY_PORT>`: the relay, found by the Mac's Bonjour name so a new IP doesn't break it |
| Simulator | Llama.app directly, on the same Mac (port `FIXKEY_LLAMA_PORT`, plain HTTP) |
| Mac tools | Llama.app directly, on the port from Llama.app's own settings |
| Debug builds | the `-FixkeyServerURL <url>` launch argument wins |

The values come from `Config/*.xcconfig`. The build copies them into each target's `Info.plist` (`FixkeyMacHost`, `FixkeyRelayPort`, `FixkeyLlamaPort`, `FixkeyAPIKey`, `FixkeyRelayCertSHA256`, `FixkeyModel`), and `FixkeyConfig` reads them at runtime.

Other settings in `FixkeyConfig`, all chosen from [model evaluation](model-evaluation.md) results:

| Setting | Value | Why |
|---|---|---|
| `model` | `FIXKEY_MODEL`, by default `unsloth/Qwen3.5-4B-GGUF:Q4_K_M` | Best accuracy and speed on 8 GB. Through the relay, the Mac's current choice (`./fixkey model`) wins. |
| `thinking` | `false` | Thinking took minutes per sentence |
| `correctionPasses` | `1` | A second pass scored lower and doubled the time |
| `danishExamples` | `true` | Raised the score from 36 to 39 of the first 43 cases |
| `timeout` | 45 s | Covers reloading the model after it idles out |

### What errors mean

`MacConnection` turns network errors and HTTP status codes into `Proofreader.Failure`, so the keyboard and the app can say what's wrong:

| Failure | Cause |
|---|---|
| `offline` | The device has no network |
| `macNotFound` | The Mac's name doesn't resolve: off, asleep or another network |
| `relayNotRunning` | The Mac answers, but nothing listens on the relay port: the relay isn't running, or the Mac is on a Wi-Fi network that isn't allowed |
| `llamaNotRunning` | The relay answers 502, or (simulator, Mac tools) Llama.app's port is closed |
| `wrongKey` | The relay answers 401 |
| `untrustedRelay` | The certificate doesn't match the pinned fingerprint, or the TLS handshake fails |
| `timedOut` | No answer in time, or the relay answers 504 |
| `server`, `emptyReply`, `truncated`, `rejected` | Problems with the reply itself |

## Keyboard input

- `KeysUIView` is UIKit for speed: it highlights on touch-down, shows the key popup right away, supports multi-touch rollover for fast two-thumb typing, and doesn't re-render SwiftUI on each key press.
- The SwiftUI layer (`KeyboardView`) shows the strip (Fixkey icon, status, word suggestions) and the suggestion card.
- `KeyboardViewController` turns off the system's delayed touches near screen edges, so edge keys react at once. It plays the system click through `UIInputViewAudioFeedback`. There's no haptic feedback.

## Word suggestions and autocorrect

`WordSuggestions` uses `UITextChecker` with:

- **learned words**, from the supplementary lexicon (your iOS text replacements and contacts) and words you keep;
- **autocorrect that can be undone**: backspace right after an autocorrection restores what you typed;
- **conservative rules**: never change the first letter; at most one edit for words of three letters or fewer; all-caps words are treated as acronyms;
- **a dictionary self-test**: if a device lacks the dictionary for a language (the simulator lacks Danish), every word looks misspelled, so "ikke" would become "ikte". Fixkey tests common words first and turns off suggestions and autocorrect for that language if they fail;
- **context rules**: nothing in URL, email, web-search or Twitter fields, or where the text field turns off autocorrection or spell checking.

## The relay

`Tools/lan-relay/relay.py` is plain Python from Xcode's Python 3, with no packages. See [privacy-and-security.md](privacy-and-security.md#the-wi-fi-relay) for what it allows. It reads its port and model from `Config/Local.xcconfig`, listens on the Wi-Fi address and restarts its listener when that address changes, and `relay.py --check` tests it from the Mac the way the iPhone connects.

Every check uses the model chosen on the Mac: the relay sets the `model` field of each request to `FIXKEY_MODEL` (or `--model`) and names it in an `X-Fixkey-Model` reply header, which the app shows under **Your Mac**. So `./fixkey model` changes the model without a new build on the iPhone.

### Starting by itself

`./fixkey autostart on` makes the relay start when you log in:

- It copies `relay.py`, the key and the certificate to `~/Library/Application Support/Fixkey/relay` (readable only by you), because macOS doesn't let background programs read Downloads or Documents.
- It installs the LaunchAgent `local.fixkey.relay` (`RunAtLoad`, `KeepAlive`), which runs that copy with `--port`, `--networks`, `--start-llama`, `--language` and `--model`. Its output goes to `~/Library/Logs/Fixkey/relay.log`, which the relay empties when it starts and finds the file over 1 MB.
- **Allowed networks.** With `--networks`, the relay listens only while the Mac is on a network listed in `~/Library/Application Support/Fixkey/networks.txt`. Each line is a network ID, `<settings>+<router>`: a hash of the Wi-Fi lease's router, subnet, DHCP server and DNS addresses, plus a hash of the router's hardware address when the Mac knows it (a VPN can hide it). When both IDs have the router part, it decides; otherwise the settings part does. The relay checks again every 30 seconds, stops listening when the Mac leaves an allowed network, and shows one notification per network it won't listen on. `./fixkey autostart add` adds the current network.
- **Llama.app on demand.** With `--start-llama`, a refused connection to Llama.app makes the relay open it in the background (`open -g -b app.llama.Llama`), wait up to 40 seconds for it to answer, and try once more.
- `./fixkey configure`, `model`, `install` and `setup` refresh the copy and the agent when the relay, key, certificate, port, language or model change, and `./fixkey doctor` reports a copy that is out of date.

## The 7 days

A free Apple ID's provisioning profiles last 7 days. Xcode reuses a cached profile until it expires, so before each build `./fixkey install` sets Fixkey's own cached profiles aside (only those for `<prefix>.fixkey` and `<prefix>.fixkey.keyboard`), and Xcode fetches new ones: every reinstall gives 7 days from that moment. If the build fails, the old profiles go back. Afterwards it reads the end date from the app's embedded profile and stores it, with the iPhone's ID, in `~/Library/Application Support/Fixkey` (`expiry`, `iphone`). The app reads the same date from its own profile for **Works until**.

### Renewing by itself

`./fixkey reminder on` installs the LaunchAgent `local.fixkey.reminder`, which runs `Tools/reminder/remind.sh` (copied to the same folder) every 3 hours:

- **From 2 days before the end**, at most every 3 hours, it runs `./fixkey renew`. That runs from a copy of the Fixkey folder in `~/Library/Application Support/Fixkey/source`, because background programs can't read Downloads or Documents. `renew` builds into `~/Library/Caches/Fixkey` and installs over the network connection Xcode keeps for the paired iPhone, with no one at the keyboard. Its exit code says what happened: 0 renewed, 3 the iPhone can't be reached now, 4 Xcode needs the Apple ID again, 1 anything else. On success, a notification shows the new date.
- **When renewing doesn't work**, it reminds you: a dialog the day before the end (right away when Xcode needs the Apple ID), and after the end at most every 12 hours. Its **Reinstall** button writes a small command file next to it and opens it, so Terminal runs `./fixkey reinstall` in the Fixkey folder.
- `install`, `setup`, `configure` and `model` refresh the copy. `Tools/reminder/test.sh` tests all of this with a fake clock, a fake dialog and a stand-in for `./fixkey`.
