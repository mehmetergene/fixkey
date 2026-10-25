# Set up Fixkey

**English** · [Dansk](SETUP.da.md) · [Back to README](README.md)

This guide puts Fixkey on your iPhone and connects it to a language model on your Mac. You don't need to know programming, and no AI is involved: a setup assistant on your Mac asks you a few questions and does the work. Plan on 30 to 45 minutes, mostly waiting for downloads.

<p align="center"><img src="docs/images/card.png" width="300" alt="What you get: the Fixkey card with suggested changes"></p>

## What you need

- **A Mac with Apple silicon** (M1 or newer) and at least **8 GB** memory, with about **20 GB free** disk space.
- **An iPhone with iOS 17 or later**, and its **cable**.
- **An Apple ID.** The free one you already have is enough; you don't need to pay Apple anything.
- **Wi-Fi.** When you use Fixkey, the Mac and the iPhone must be on the same Wi-Fi network (or the Mac on the iPhone's Personal Hotspot).

Fixkey is tested on an iPhone and an M2 MacBook Pro with 8 GB.

## Two ways to set up

1. **On your own, with the setup assistant** (recommended). You double-click one file; it asks questions and does the rest. Follow the steps below.
2. **With an AI assistant**, such as Claude Code, Codex or Cursor, if you already use one. Open it in the Fixkey folder and say *"Set up Fixkey using SETUP.md"*. It reads the [section for AI assistants](#for-ai-assistants) at the end and guides you through the same steps.

## Step 1: Install three things

| What | Why | How |
|---|---|---|
| **Xcode** | Apple's free tool that builds apps. Fixkey isn't in the App Store, so your Mac builds it for your iPhone. | Install it from the [App Store](https://apps.apple.com/app/xcode/id497799835). Open it once, click **Agree**, and let it install what it suggests. |
| **Your Apple ID in Xcode** | Apple only lets apps onto an iPhone when they're signed with an Apple ID. | In Xcode, open **Xcode › Settings… › Apple Accounts** (just **Accounts** in older versions), click **+**, choose **Apple ID** and sign in. |
| **Llama.app** | Runs the language model on your Mac. | Download it from [llama.app](https://llama.app), move it to **Applications** and open it once. |

## Step 2: Download Fixkey

On the [Fixkey page on GitHub](https://github.com/mehmetergene/fixkey), click the green **Code** button, then **Download ZIP**. Open the downloaded file and move the folder (`fixkey-main`) to your **Documents** folder.

If you use git: `git clone https://github.com/mehmetergene/fixkey.git`

## Step 3: Start the setup assistant

**Double-click `Fixkey Setup.command`** in the Fixkey folder. Terminal opens and the setup starts.

The first time, macOS may say it can't check the file, because it's a script from the internet and not from the App Store. Then:

1. Click **Done**.
2. Open **System Settings › Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to *"Fixkey Setup.command" was blocked to protect your Mac*.
3. Confirm with your Mac password or Touch ID.

From then on it opens with a double-click.

You can also start it from Terminal: press ⌘ Space, type *Terminal*, press Enter, type `cd` and a space, drag the Fixkey folder into the window, press Enter, then type `./fixkey setup` and press Enter.

The assistant speaks Danish if your Mac is set to Danish (`./fixkey setup --lang da` chooses it). It checks your Mac, Xcode and Llama.app, then asks before it does anything big. A run looks like this:

```text
1. This Mac
  ✓ Mac with Apple silicon
  ✓ 8 GB memory
  ✓ 41 GB free disk space

2. Xcode (Apple's free tool that builds the app)
  ✓ Xcode 27.1
  ✓ Xcode is signed in to your Apple ID

3. Llama.app and the language model
  ✓ Llama.app is running (port 9931)
  Use the recommended model, Qwen3.5 4B (tested, about 2.7 GB)? [Y/n]
  ✗ The model (unsloth/Qwen3.5-4B-GGUF:Q4_K_M) isn't downloaded.
  Download the model now (about 2.7 GB)? [Y/n]
  …
  This Mac has 8 GB memory. Keep the model's memory use low (recommended)? [Y/n]
  ✓ The model answered in 6 s: “Jeg har ikke meget tid i dag.”

4. Your settings
  ✓ Signing with team: Your Name (Personal Team)
  Your copy of the app needs its own ID, written like com.yourname.
  App ID (press Enter for the suggestion) [com.yourname]
  ✓ App ID: com.yourname.fixkey
  ✓ Created a new relay key
  ✓ Created the relay's certificate (encrypts the Wi-Fi connection)
  ✓ Saved your settings in Config/Local.xcconfig (only you can read it)

5. The relay (connects the iPhone to this Mac)
  Start the relay by itself when you log in (recommended)? [Y/n]
  ✓ Allowed this Wi-Fi network for the relay
  ✓ The relay now starts by itself when you log in, on the Wi-Fi networks you allow
  ✓ The relay works: encrypted, key accepted, Llama.app answers

6. Your iPhone
  ✓ Found Your iPhone
  ✓ Developer Mode is on
  Building Fixkey for Your iPhone. The first time takes a few minutes.
  ✓ Installed on Your iPhone
  ✓ Fixkey is open on Your iPhone
  ✓ Your iPhone reached this Mac over the encrypted connection
  ✓ Fixkey works on the iPhone until Sat 7 Nov 2026 at 10:00. Reinstalling before then gives 7 days from that moment.

7. Turn on the keyboard (one time, on the iPhone)
  …
  ✓ Your first check worked

8. A reminder every 7 days
  Remind you when that happens (recommended)? [Y/n]
  ✓ Fixkey reminds you the day before the 7 days end, and again when they have
```

Whenever something is missing, it says what to do and waits until you've done it. The questions it may ask:

- **Use the recommended model?** Say yes unless you want to try another; see [Choosing the model](#choosing-the-model).
- **Download the model?** About 2.7 GB, once.
- **Keep the model's memory use low?** Only on 8 GB Macs. Say yes.
- **App ID.** Your own copy of the app needs a name like `com.yourname`. Press Enter to use the suggestion.
- **Start the relay by itself when you log in?** Say yes, and you never have to start anything again. It listens only on Wi-Fi networks you allow, starting with the one the Mac is on now.
- **Remind you when the 7 days end?** Say yes; see [Every 7 days](#every-7-days).
- **Which team or iPhone?** Only if Xcode knows several teams or several iPhones are connected.

## Step 4: On the iPhone

The assistant tells you when to do each of these.

**Developer Mode.** iPhones only run apps you build yourself when Developer Mode is on. Go to **Settings › Privacy & Security › Developer Mode**, turn it on and let the iPhone restart. After the restart, unlock it and tap **Turn On**. (The switch only appears after the iPhone has been connected to a Mac with Xcode.)

**Trust your Apple ID.** The first time, and sometimes after the 7 days are over, the iPhone asks whether you trust the developer, which is you. Go to **Settings › General › VPN & Device Management**, tap your Apple ID under **Developer App**, then **Trust**.

**Allow local network access.** When the Fixkey app opens the first time, it asks to find devices on your local network. Tap **Allow**; that's how it reaches your Mac.

**Turn on the keyboard.** Go to **Settings › Apps › Fixkey › Keyboards**. Turn on **Fixkey**, then **Allow Full Access**, and confirm with **Allow**. iOS only lets keyboards use the network with Full Access; the [FAQ](docs/en/faq.md#why-does-fixkey-need-full-access) explains what that means.

<p align="center">
  <img src="docs/images/iphone-keyboards.png" width="280" alt="Settings › Apps › Fixkey › Keyboards with Fixkey and Allow Full Access switched on">
  &nbsp;
  <img src="docs/images/iphone-full-access.png" width="280" alt="The Allow Full Access question">
</p>

## Step 5: Your first check

1. Open **Notes** (or any app where you write), and tap in a text.
2. Hold the 🌐 key under the letters and choose **Fixkey**.
3. Type `jeg har ikke mye tid idag` and tap the round green Fixkey icon above the keys.
4. The card shows the changes. Tap a change to leave it out, then tap **Accepter** to apply the rest, or **Afvis** to keep your text.

<p align="center">
  <img src="docs/images/strip.png" width="280" alt="After a check: the first change above the keys and a red badge with the number of changes">
  &nbsp;
  <img src="docs/images/card-choice.png" width="280" alt="The card with one change turned off: the original word kept and the suggestion struck out in grey">
</p>

While you type, the strip above the keys shows word suggestions, like Apple's keyboard:

<p align="center"><img src="docs/images/suggestions.png" width="280" alt="Word suggestions above the keys"></p>

The setup assistant notices your first check and says so.

## Every day

If the relay starts by itself (you said yes when the assistant asked), there's nothing to do. Keep the Mac on and awake, on Wi-Fi. The relay starts when you log in, opens Llama.app when a check needs it, and listens only on Wi-Fi networks you allowed.

- **Another network of yours** (at work, at a friend's, or your iPhone's Personal Hotspot): while the Mac is on it, double-click **Fixkey Setup** and choose **Allow this Wi-Fi network for the relay**, or run `./fixkey autostart add`. On a network you haven't allowed, macOS shows a notification saying so.
- **Without automatic start:** open Llama.app, double-click **Fixkey Setup** and choose **Run the relay in this window**, and keep that window open while you use Fixkey.

## Every 7 days

With a free Apple ID, apps you build yourself stop opening after 7 days. Nothing is lost: each reinstall gives 7 new days from that moment, so you can do it whenever it suits you, before or after the end.

1. Connect the iPhone with its cable and unlock it.
2. **Double-click `Reinstall Fixkey.command`** in the Fixkey folder. That's all; it takes a minute or two.

The reminder tells you the day before the end (and again after it), with a **Reinstall** button that does the same. `./fixkey doctor` shows the exact date. If the iPhone asks you to trust your Apple ID again, see Step 4.

## Choosing the model

Fixkey recommends the model it was tested with, **Qwen3.5 4B** (45 of 53 test cases right, a second or two per check on an 8 GB M2). You can use any other model that Llama.app runs:

1. Double-click **Fixkey Setup** and choose **Choose the language model**, or run `./fixkey model`.
2. Pick a model you already have in Llama.app, or choose **Download another model** and write its Hugging Face name with the quantization after a colon, for example `unsloth/Qwen3.5-4B-GGUF:Q4_K_M`.
3. The assistant tests it with a sentence and offers to score it on Fixkey's 53 test cases, next to the recommended model's 45.

The choice is stored on the Mac and the relay applies it, so the iPhone needs nothing. On an 8 GB Mac, stay at about 4B parameters with 4-bit quantization (Q4); bigger Macs can try larger models. [model-evaluation.md](docs/en/model-evaluation.md) explains how Fixkey's tests work.

## If something doesn't work

Double-click **Fixkey Setup** and choose **Check everything**, or run `./fixkey doctor`. It checks everything (Mac, Xcode, Llama.app, the model, your settings, the relay and the iPhone) and says what to fix. The [FAQ](docs/en/faq.md) explains each message, including the ones the keyboard shows.

To remove what Fixkey set up on the Mac, run `./fixkey uninstall`.

## For AI assistants

These instructions are for an AI coding assistant (Claude Code, Codex, Cursor or similar) that a person asked to set up Fixkey. The person may not be a developer. Everything below can also be done without an assistant (see above); you only guide.

**How to work**

- Speak plainly. Before each step, say in one sentence what it does and why.
- Ask one question at a time and wait for the answer. Ask before downloading the model (about 2.7 GB), before installing anything, and before anything that needs the Mac password.
- Never print, copy or commit the contents of `Tools/lan-relay/key.txt`, `Tools/lan-relay/relay-key.pem`, `Config/Local.xcconfig` or `~/Library/Application Support/Fixkey`. Never commit or push anything.
- Run the `./fixkey` commands with `--yes` from the repository root. With `--yes` they never wait for input: they use the suggested answers and stop with a ✗ and a hint when something is missing. Don't run `./fixkey` without a command: the menu needs a person at the keyboard.
- Some steps only the person can do: installing apps from the App Store or a website, signing in to Xcode with their Apple ID, allowing `Fixkey Setup.command` under Privacy & Security, and anything on the iPhone (unlocking, Trust, Developer Mode, Full Access). Explain those steps, wait until the person says they're done, then check again.

**Steps**

1. Run `./fixkey doctor`. It changes nothing. Work through its ✗ lines from the top.
2. **Xcode.** If it's missing or not set up, ask the person to install it from the App Store, open it once and accept the license. If `xcode-select` points elsewhere, ask before running `sudo xcode-select -s /Applications/Xcode.app`.
3. **Apple ID.** If Xcode isn't signed in, ask the person to open Xcode › Settings › Apple Accounts (Accounts in older Xcode) and add their Apple ID.
4. **Model.** Recommend the tested model (Qwen3.5 4B, about 2.7 GB). Ask, then run `./fixkey model --yes`: it starts Llama.app, downloads the model, limits memory on 8 GB Macs and tests the model. If the person wants another model, run `./fixkey model use <owner/model-GGUF:QUANT> --yes` instead, and offer `./fixkey model evaluate` (a few minutes) to compare it with the recommended model's 45/53.
5. **Settings.** Suggest an app ID prefix such as `com.<their first name>` in lower case and ask the person to confirm it. Then run `./fixkey configure --yes --prefix <prefix>`. If Xcode knows several teams, also pass `--team <ID>` after asking which one.
6. **Relay.** Ask whether the relay should start by itself when they log in (recommended; it listens only on the current Wi-Fi network until they allow others). If yes, run `./fixkey autostart on --yes`. If no, start `./fixkey relay` as a long-running process in a separate terminal. Either way, run `./fixkey test` afterwards: it must say that the relay works.
7. **iPhone.** Ask the person to connect the iPhone with a cable and unlock it, then run `./fixkey install --yes`. If it stops with a ✗, read the hint aloud, help the person do it on the iPhone (Developer Mode, Trust, unlocking), and run the command again.
8. **Keyboard.** Guide the person through Settings › Apps › Fixkey › Keyboards: turn on Fixkey and Allow Full Access. Then have them type `jeg har ikke mye tid idag` in Notes with the Fixkey keyboard and tap the green icon. The relay's log (`~/Library/Logs/Fixkey/relay.log` with automatic start, otherwise the relay's terminal) shows `POST /v1/chat/completions  200` when the check reaches the Mac.
9. **Reminder.** Ask whether they want a reminder when the 7 days are over (recommended). If yes, run `./fixkey reminder on --yes`.
10. **Finish.** Tell the person: on another Wi-Fi network of theirs, run `./fixkey autostart add` (or use the menu in Fixkey Setup); every 7 days, connect the iPhone and double-click `Reinstall Fixkey.command` (each reinstall gives 7 new days); `./fixkey doctor` checks everything. Point them to `docs/en/faq.md` for questions.
