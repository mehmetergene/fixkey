# Development and tests

[Dansk](../da/development.md) · [Back to README](../../README.md)

## The Xcode project

`project.yml` is the source of truth. `Fixkey.xcodeproj` is generated from it with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so people who only build the app need no XcodeGen. After changing `project.yml`, or adding or removing files:

```bash
xcodegen generate
```

and commit `project.yml` and `Fixkey.xcodeproj` together.

The code in `Shared/` must also build on macOS, because the Mac tools compile it. Keep UIKit out of it.

## Tests

```bash
Tools/test.sh               # quick: guardrails, shared code, relay, reminder, setup scripts (no model, no simulator)
Tools/test.sh --simulator   # also the keyboard unit tests in the iOS simulator
Tools/test.sh --model       # also the model evaluation (needs Llama.app with the model)
```

It prints one line per suite; the full output is in `build/test-*.log`.

| Suite | What it covers | Needs |
|---|---|---|
| `Tools/guardrail-check/run.sh` | 26 hand-written replies that the [guardrails](guardrails.md) must allow or block | Nothing |
| `Tools/core-check/run.sh` | The word diff and accepting some changes (including spacing, line breaks and emoji), the reply clean-up, the check range, the past-tense rule (44 sentences that must change or stay), and what network errors mean | Nothing |
| `python3 -I Tools/lan-relay/test_relay.py` | The relay against a fake Llama.app: HTTPS and the certificate, the key, paths, sizes, slow and idle clients, the connection limit, logs, the chosen model, opening Llama.app on demand, network IDs and allowed networks, `--check` | Nothing |
| `Tools/reminder/test.sh` | Renewing and the reminder with a fake clock, dialog and `./fixkey`: renewing from 2 days before, at most every 3 hours, a notification when renewed, the sign-in message once, the reminder when renewing fails (the day before, then every 12 hours), **Reinstall** opens the command, Danish texts | Nothing |
| `FixkeyTests` (Xcode) | The keyboard model with a plain-string text field: accepting all, some or no changes, text that changed meanwhile, typing, capitalisation, deleting words, messages, and the tappable change text | iOS simulator |
| `Tools/model-eval/run.sh` | The model on 53 cases, see [model-evaluation.md](model-evaluation.md) | Llama.app with the model |

## Mac tools

All tools run from the repository root. The Swift tools compile `Shared/` together with their own `main.swift` into a temporary folder, so they always test the same code the keyboard uses.

| Command | What it does | Needs the model |
|---|---|---|
| `./fixkey setup` | The guided setup ([SETUP.md](../../SETUP.md)) | Yes |
| `./fixkey doctor` | Checks everything and says what to fix | No |
| `./fixkey configure` | Creates the key, certificate and `Config/Local.xcconfig`, or takes them over from the folder set up before | No |
| `./fixkey reinstall` | Builds a release build with a fresh 7-day profile and installs it on the iPhone | No |
| `./fixkey model [use <id> \| evaluate [<id>]]` | Chooses the model (a list, or the given Hugging Face `owner/repo:QUANT`), or scores it like `Tools/model-eval` | Yes |
| `./fixkey autostart on\|off\|add` | Starts the relay at login on allowed networks, stops doing that, or allows the current network | No |
| `./fixkey reminder on\|off` | Renewing by itself over Wi-Fi, with the reminder when it can't | No |
| `./fixkey renew` | Builds and installs over Wi-Fi with no questions, as renewing does. Exit code 0 renewed, 3 iPhone not reachable, 4 Xcode needs the Apple ID, 1 other. | No |
| `./fixkey relay` | Runs the Wi-Fi relay in the window, when it doesn't start by itself. Stop it with Ctrl+C. | Yes |
| `./fixkey test` | Checks the running relay the way the iPhone connects | Yes |
| `./fixkey uninstall` | Removes the LaunchAgents and their files and logs | No |
| `Tools/proofread-cli/run.sh ["text" …]` | Proofreads sample or given sentences and prints the result, a word diff and the time | Yes |
| `Tools/model-eval/run.sh <model> <label> [think\|nothink] [out.json]` | Scores a model on the test cases | Yes |
| `swift Tools/app-icon/make-icon.swift <out.png>` | Renders the 1024 × 1024 app icon. Remove the alpha channel afterwards with `magick <out.png> -alpha off <out.png>`. | No |

`./fixkey` takes `--yes` (use the suggested answers and never wait for Enter; also automatic when there's no terminal) and `--lang en|da`. That's how an AI assistant or a script drives it. Without a command it shows a menu, which does nothing without a terminal; `./fixkey help` lists every command.

Example:

```bash
$ Tools/proofread-cli/run.sh "i has went to the store yesterday and buyed three apple"
IN : i has went to the store yesterday and buyed three apple
OUT: I went to the store yesterday and bought three apples.
DIF: [-i-] [-has-] {+I+} went to the store yesterday and [-buyed-] {+bought+} three [-apple-]{+apples+}{+.+}
     2348 ms
```

## Debug launch arguments

Debug builds of the app accept these launch arguments. Set them in Xcode under **Product › Scheme › Edit Scheme › Run › Arguments**, or pass them to `simctl launch` and `devicectl … process launch`.

| Argument | Effect |
|---|---|
| `-FixkeyKeyboardPreview letters` | Opens the full keyboard inside the app instead of the normal screen. Other modes: `capitals` (an empty field, so the keys show capitals), `numbers`, `strip` (a result in the strip), `card` (the suggestion card), `card-choice` (the card with one change turned off), `suggestions` (word suggestions for "hjæl"). |
| `-FixkeyDemoText "text"` | Puts the text in the try-it box and fixes it right away |
| `-FixkeyFocusInput YES` | Focuses the try-it box so the current keyboard appears. Useful for screenshots of Apple's keyboard for comparison. |
| `-FixkeyServerURL https://host:port` | Uses a different server |

## Simulator

The simulator talks to Llama.app on the same Mac directly, so the relay isn't needed.

```bash
xcodebuild -project Fixkey.xcodeproj -scheme Fixkey \
  -destination 'platform=iOS Simulator,name=<simulator>' -derivedDataPath build/sim build
xcrun simctl boot "<simulator>"
xcrun simctl install booted build/sim/Build/Products/Debug-iphonesimulator/Fixkey.app
xcrun simctl launch booted com.yourname.fixkey -FixkeyKeyboardPreview card
xcrun simctl io booted screenshot preview.png
```

`xcrun simctl list devices available` lists the simulators you have.

- Xcode 27 has no Simulator window app. `simctl` works headless.
- The simulator usually lacks a Danish dictionary. Fixkey detects this and turns off Danish suggestions and autocorrect there. Test them on a real iPhone.
- On an 8 GB Mac, shut the simulator down (`xcrun simctl shutdown all`) before running model tests.

## Device

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device <id> build/device/Build/Products/Release-iphoneos/Fixkey.app
xcrun devicectl device process launch --terminate-existing --device <id> com.yourname.fixkey
xcrun devicectl device capture screenshot --device <id> --destination shot.png
```

The app's **Your Mac › Status** row is a quick end-to-end check: it calls `GET /v1/models` through the relay with the key and the pinned certificate, and names the part that fails.

## The relay and the reminder in the background

```bash
launchctl print gui/$(id -u)/local.fixkey.relay | grep -E 'state|pid'   # is it running?
tail -f ~/Library/Logs/Fixkey/relay.log                                    # what it does
python3 -I Tools/lan-relay/relay.py --network-id                           # this network's ID
python3 -I Tools/lan-relay/relay.py --on-allowed-network ~/Library/Application\ Support/Fixkey/networks.txt && echo allowed
```

To try the reminder without waiting for the date, run its script against a test folder with a fake clock; `FIXKEY_DRY_RUN` prints the dialog instead of showing it and acts as if its value was clicked:

```bash
FIXKEY_SUPPORT_DIR=/tmp/fixkey-test FIXKEY_NOW=$(date +%s) FIXKEY_DRY_RUN=Later bash Tools/reminder/remind.sh
```

The folder needs an `expiry` file (seconds since 1970) and a `reminder.conf`, as `Tools/reminder/test.sh` shows. `FIXKEY_RENEW_COMMAND` puts a stand-in in place of `./fixkey renew`.

To renew right now the way the reminder does, from the copy in Application Support: `~/Library/Application\ Support/Fixkey/source/fixkey renew`. Its log is `~/Library/Logs/Fixkey/renew.log`.

## Before a commit

1. `Tools/test.sh --simulator`: every suite must pass.
2. If the prompt, examples, guardrails or model changed: `Tools/test.sh --model`, and compare with 50/53.
3. Build for the device and try a check in a real app (Notes, Messages).
4. `git status`: make sure `Config/Local.xcconfig`, `Tools/lan-relay/key.txt` and the `relay-*.pem` files are not listed.
