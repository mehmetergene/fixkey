# Questions and answers

[Dansk](../da/faq.md) · [Back to README](../../README.md) · [Setup guide](../../SETUP.md)

Plain answers about Fixkey, the apps it needs and what to do when something doesn't work. If your question isn't here, open an issue on GitHub.

- [About Fixkey](#about-fixkey)
- [What you need](#what-you-need)
- [The free Apple ID and the 7 days](#the-free-apple-id-and-the-7-days)
- [Using Fixkey](#using-fixkey)
- [The relay and your Wi-Fi](#the-relay-and-your-wi-fi)
- [Choosing the model](#choosing-the-model)
- [Privacy and safety](#privacy-and-safety)
- [When something doesn't work](#when-something-doesnt-work)
- [Updating and removing Fixkey](#updating-and-removing-fixkey)

## About Fixkey

### What is Fixkey?

A keyboard for your iPhone that corrects Danish and English, a bit like Grammarly. The difference: the corrections come from a language model running on your own Mac, not from a company's servers.

### Is it in the App Store? Does it cost anything?

It isn't in the App Store. You build it yourself on your Mac with Apple's free tools, and the setup assistant does that for you. Fixkey itself is free for non-commercial use (see the [license](../../LICENSE)), and you don't need to pay Apple.

### Which languages does it check?

Danish and English. The keyboard layout is Danish, with æ, ø and å, and its buttons are in Danish: **Accepter** means *Accept* and **Afvis** means *Dismiss*.

### How good are the corrections?

With the recommended model: good with spelling, word order, *en/et*, commas and capital letters. Its main weakness is tense: it sometimes keeps *har været* where Danish needs *var*, as in *"Vi har været i Italien sidste sommer"*. On our test set it gets 45 of 53 cases right ([details](model-evaluation.md)). Read the card before you accept: a small model can occasionally change the meaning.

### Does it work on iPad?

No, only iPhone.

## What you need

### Which Mac and iPhone?

- A Mac with Apple silicon (M1 or newer) and at least 8 GB memory.
- An iPhone with iOS 17 or later.

Fixkey is tested on an iPhone and an M2 MacBook Pro with 8 GB.

### What is Xcode, and why do I need it?

Xcode is Apple's free program for building apps. Because Fixkey isn't in the App Store, your Mac builds it from the code and puts it on your iPhone; Xcode is what does that. You hardly need to open it: the setup assistant uses it behind the scenes. You open it once after installing, and once to sign in with your Apple ID (**Xcode › Settings… › Apple Accounts**, called **Accounts** in older versions).

### How much space does it take?

About 4 GB for Xcode (more if you let it download the iOS Simulator, which Fixkey doesn't need) and 2.7 GB for the recommended language model. Have about 20 GB free before you start.

### What is Llama.app?

A Mac app that runs language models on your own computer. Fixkey uses it to run its model: Qwen3.5 4B, unless you [choose another](#choosing-the-model). Get it from [llama.app](https://llama.app).

### Do I need to use Terminal?

Hardly. Double-click **Fixkey Setup.command** in the Fixkey folder, and Terminal opens by itself with the setup assistant. After the setup, the same file opens a menu with everything you need later. To renew the 7 days, double-click **Reinstall Fixkey.command**.

If you prefer typing, these are the commands. Run them in the Fixkey folder: open Terminal (press ⌘ Space and type *Terminal*), type `cd` and a space, drag the folder into the window, and press Enter.

| Command | What it does |
|---|---|
| `./fixkey setup` | Sets everything up |
| `./fixkey reinstall` | Gives 7 new days on the iPhone, like Reinstall Fixkey.command |
| `./fixkey doctor` | Checks everything and says what to fix; changes nothing |
| `./fixkey model` | Chooses the language model |
| `./fixkey autostart add` | Lets the relay listen on the Wi-Fi network the Mac is on now |
| `./fixkey relay` | Runs the relay in the window, if it doesn't start by itself |
| `./fixkey help` | Lists every command |

### Do I need to be a developer?

No. If you can install apps on your Mac and follow a guide, you can set up Fixkey. You can also let an AI assistant such as Claude Code, Codex or Cursor run the setup with you; [SETUP.md](../../SETUP.md#for-ai-assistants) tells it how.

### Do I need Homebrew, XcodeGen or Python?

No. Python comes with Xcode, and everything else is included.

## The free Apple ID and the 7 days

### Do I need to pay for an Apple developer account?

No. A free Apple ID is enough. Apple calls this a *Personal Team*.

### Why does Fixkey stop opening after 7 days?

Apple lets you put your own apps on your own iPhone for free, but each install works for only 7 days. After that the app stops opening and the keyboard stops working. Nothing is lost, and nothing on the iPhone changes: connect the iPhone to the Mac, unlock it, and double-click **Reinstall Fixkey.command** in the Fixkey folder (or run `./fixkey reinstall`). It takes a minute or two.

A paid Apple Developer Program membership (about 99 USD a year) makes an install last a year, but Fixkey doesn't need it.

### Can I reinstall before the 7 days are over?

Yes, any time. Each reinstall gives 7 days from that moment, so you can do it before a trip or whenever it suits you. `./fixkey doctor` shows the exact date. After a reinstall, the iPhone may ask you to trust your Apple ID again (**Settings › General › VPN & Device Management**).

### Can Fixkey remind me?

Yes, if you said yes to the reminder during setup. The day before the 7 days end, the Mac shows a message with a **Reinstall** button: connect and unlock the iPhone, click it, and Terminal opens and reinstalls. If you click **Later**, it asks again once the 7 days are over, at most twice a day, until you reinstall. Turn the reminder on or off in the Fixkey Setup menu, or with `./fixkey reminder on` or `off`.

### Can I renew from the iPhone?

Not yet. The Mac builds the app and installs it over the cable. A button in the app that asks the Mac to do it over Wi-Fi is on the [roadmap](roadmap.md).

### Are there other limits with a free Apple ID?

Two, which you'll rarely meet:

- **3 apps.** A free Apple ID can have at most 3 of its own apps on a phone at once. If you already have others, the setup tells you when to remove one.
- **10 app IDs per 7 days.** Each new app ID counts. Fixkey uses two (the app and the keyboard), and reinstalling doesn't use new ones. Only changing your app ID does.

### What is Developer Mode?

An iPhone setting that allows apps you build yourself. Turn it on under **Settings › Privacy & Security › Developer Mode**. The switch appears after the iPhone has been connected to a Mac with Xcode. The iPhone restarts, and afterwards you confirm with **Turn On**.

### Why must I "trust" my own Apple ID?

iOS asks the first time an app from a new developer (here: you) is installed outside the App Store. Go to **Settings › General › VPN & Device Management**, tap your Apple ID under **Developer App**, and tap **Trust**.

## Using Fixkey

### What do I do each time I want to use Fixkey?

Nothing on the Mac, if the relay starts by itself (the setup asks, and recommends it). Keep the Mac on and awake, on a Wi-Fi network you allowed, then type on the iPhone as usual and tap the Fixkey icon when you want a check. The relay opens Llama.app when a check needs it.

Without automatic start: open Llama.app, double-click Fixkey Setup and choose **Run the relay in this window** (or run `./fixkey relay`), and leave the window open while you use Fixkey.

### Does the Mac have to be on?

Yes. The model runs on the Mac, so the Mac must be on, awake and on the same Wi-Fi as the iPhone. If the Mac sleeps, the keyboard says it can't find your Mac. On a MacBook, keep it open and plugged in while you use Fixkey.

### Can I use Fixkey away from home?

Yes, with your iPhone's Personal Hotspot. Turn it on (**Settings › Personal Hotspot**), connect the Mac to it, and allow that network once while the Mac is on it: double-click Fixkey Setup and choose **Allow this Wi-Fi network for the relay**, or run `./fixkey autostart add`. Checks then go from the iPhone to the Mac over the hotspot's own connection, not over the internet.

Otherwise the Mac and the iPhone must be on the same Wi-Fi network. Public networks in cafés and hotels often keep devices from seeing each other, so use the hotspot there. Reaching the Mac from anywhere (for example over Tailscale) is on the [roadmap](roadmap.md).

### Does Fixkey check while I type?

No. It checks only when you tap the round green icon above the keys, so it never slows down typing. Word suggestions and autocorrect work on the iPhone itself, without the Mac.

### Can I try a check without the keyboard?

Yes. Open the Fixkey app, type or paste text under **Try it** and tap **Fix grammar**. It uses the same check as the keyboard, you can tap changes to leave them out, and **Copy** copies the result. Further down, **Your Mac** shows whether the connection works and which model the Mac uses.

<p align="center"><img src="../images/app.png" width="280" alt="The Fixkey app: a text under Try it and the suggested changes under Suggestion"></p>

### Why is the first check slow?

Llama.app unloads the model after 5 idle minutes, and the next check loads it again, which takes a few seconds. If Llama.app wasn't open, the relay opens it first, which takes a little longer. After that, checks take a second or two.

### Can I accept only some of the changes?

Yes. In the card, tap a change to leave it out: your own words stay (with a dotted line under them) and the suggestion turns grey and struck through. Tap it again to bring it back. **Accepter** applies the changes that are still on.

### How much text does one check cover?

The text around the cursor, up to about 800 characters on each side, in whole sentences. In a long text, put the cursor in the part you want checked.

### Does Fixkey work in light and dark mode?

Yes. It follows your iPhone's appearance automatically, like Apple's keyboard, with the same key colours in both. There's nothing to set in Fixkey.

### How do I switch between Fixkey and other keyboards?

Hold the 🌐 key under the letters and choose a keyboard. Fixkey has no emoji key, so switch to Apple's keyboard for emoji.

### Why do I sometimes get Apple's keyboard instead?

iOS always uses its own keyboard for passwords and some phone-number fields, and some apps turn off other keyboards. That's normal.

## The relay and your Wi-Fi

### What is the relay?

Llama.app only accepts connections from the Mac itself. The relay is a small program on the Mac that lets your iPhone in, and only your iPhone: it checks the shared key from setup, encrypts the connection, and passes on nothing but Fixkey's requests. Normally it starts by itself when you log in, and you never see it. Its log, `~/Library/Logs/Fixkey/relay.log`, shows only which kind of request came in, never your text.

### Which Wi-Fi networks does the relay listen on?

Only the ones you allowed: the network the Mac was on during setup, and any you add later. To add one, put the Mac on it, double-click Fixkey Setup and choose **Allow this Wi-Fi network for the relay** (or run `./fixkey autostart add`).

On any other network the relay doesn't listen at all, so nobody there can even try to reach it, and macOS shows a notification once: *The relay doesn't listen on this Wi-Fi network. If it's yours, run ./fixkey autostart add.* If you get a new router, allow your network again.

For this, the Mac stores no network names or addresses, only a fingerprint (a hash) of each network's settings. To forget all networks, turn automatic start off and on again in the Fixkey Setup menu.

### Can I turn off the automatic start?

Yes: in the Fixkey Setup menu, choose **Stop starting the relay by itself**, or run `./fixkey autostart off`. Then run the relay in a window when you want to use Fixkey. Turn automatic start back on in the same menu, or with `./fixkey autostart on`.

### macOS says items were added that can run in the background

Those are Fixkey's relay and its 7-day reminder, which now start when you log in. macOS lists them under **System Settings › General › Login Items & Extensions**. Leave them allowed; `./fixkey uninstall` removes both.

### macOS asks whether Python may accept incoming connections

Click **Allow**. That's the relay, which needs to receive the iPhone's requests.

## Choosing the model

### Which model does Fixkey use?

By default Qwen3.5 4B (`unsloth/Qwen3.5-4B-GGUF:Q4_K_M`), the model Fixkey is tested with: 45 of 53 test cases right, a second or two per check on an 8 GB M2, and about 2.7 GB on disk. The setup recommends it.

### Can I use another model?

Yes. Double-click Fixkey Setup and choose **Choose the language model**, or run `./fixkey model`. Pick a model you already have in Llama.app, or download another from Hugging Face by writing its name with the quantization after a colon, for example `unsloth/Qwen3.5-4B-GGUF:Q4_K_M`. The assistant downloads it and tests it with a sentence.

From then on the relay uses it for every check. The iPhone needs nothing: the Fixkey app shows the model under **Your Mac**. To go back, choose the recommended model in the same menu; it's always first in the list.

### How do I know whether another model is any good?

Score it: `./fixkey model evaluate` runs Fixkey's 53 test cases on the current model in a few minutes and compares the result with the recommended model's 45 (`./fixkey model evaluate <name>` scores another model). Look especially at *unchanged* and *safety*: a good model leaves correct text alone and never follows instructions written in your text. [model-evaluation.md](model-evaluation.md) explains the tests.

### Which models suit my Mac?

On 8 GB, stay at about 4 billion parameters (4B) with 4-bit quantization (Q4_K_M); larger models make the Mac slow. With 16 GB or more you can try 7B to 9B models. Fixkey's [guardrails](guardrails.md) apply to every model: a reply that isn't a plain correction is dropped.

## Privacy and safety

### Where does my text go?

Only to your Mac, and only when you tap the Fixkey icon. Not to the cloud, not to us, and not to anyone else. Nothing is saved: not by the keyboard, the relay or Llama.app. The relay's log shows only which kind of request came in, never the text.

### Why does Fixkey need Full Access?

iOS gives keyboards no network access unless you turn on **Allow Full Access**, and Fixkey needs the network to reach your Mac. iOS then warns that the keyboard *could* send what you type. Fixkey sends text only when you tap its icon, and only to your Mac. The code is public, so anyone can check that.

### Is the connection safe?

Yes. The connection is encrypted (HTTPS), and the app trusts only the certificate your Mac made during setup, so another device can't pretend to be your Mac. The relay also requires the shared key built into your copy of the app, and it listens only on Wi-Fi networks you allowed. More in [privacy-and-security.md](privacy-and-security.md).

### What does Fixkey keep on my Mac?

Your settings in `Config/Local.xcconfig` and the relay's key and certificate in `Tools/lan-relay`, readable only by your user. For the relay that starts by itself and the reminder, copies of what they need are in `~/Library/Application Support/Fixkey`, with logs in `~/Library/Logs/Fixkey`. No text, ever.

### Can Fixkey see my passwords?

No. iOS always switches to its own keyboard in password fields.

## When something doesn't work

Start on the Mac: double-click Fixkey Setup and choose **Check everything**, or run `./fixkey doctor`. It checks everything and says what to fix.

### macOS won't open Fixkey Setup.command

macOS blocks scripts from the internet the first time, because they don't come from the App Store or a registered developer. Click **Done**, open **System Settings › Privacy & Security**, scroll down to **Security**, click **Open Anyway** next to *"Fixkey Setup.command" was blocked to protect your Mac*, and confirm with your password or Touch ID. From then on it opens with a double-click, and so does Reinstall Fixkey.command, which the setup allows too.

The file is plain text: open it with TextEdit to see that it only starts `./fixkey` in the same folder.

### The keyboard shows a message. What does it mean?

| Message on the keyboard | Meaning | What to do |
|---|---|---|
| *Slå »Tillad fuld adgang« til i Indstillinger* | Full Access is off | **Settings › Apps › Fixkey › Keyboards › Allow Full Access** |
| *iPhonen er ikke på Wi-Fi* | The iPhone has no network | Connect the iPhone to Wi-Fi |
| *Kan ikke finde din Mac – er den tændt og på samme Wi-Fi?* | The Mac is off, asleep or on another network | Wake the Mac; use the same Wi-Fi on both; turn off VPNs |
| *Relæet lytter ikke – kør ./fixkey doctor på din Mac* | The Mac is there, but the relay isn't listening: it isn't running, or the Mac is on a Wi-Fi network you haven't allowed | Run `./fixkey doctor`; on a network of yours, `./fixkey autostart add` |
| *Llama.app kører ikke – åbn den på din Mac* | The relay runs, but Llama.app doesn't | Open Llama.app |
| *Forkert nøgle – kør ./fixkey reinstall på din Mac* | The app and the relay have different keys | Run `./fixkey reinstall` |
| *Relæet passer ikke til appen – kør ./fixkey doctor på din Mac* | The relay's certificate isn't the one the app knows | Run `./fixkey doctor`, then usually `./fixkey reinstall` |
| *Kan ikke nå din Mac* | Another network problem | Run `./fixkey doctor` |
| *Det tog for lang tid – prøv igen* | The model took too long | Try again; the first check after a break is slower |
| *Fejl fra serveren* | Llama.app answered with an error, for example because the chosen model isn't downloaded | Run `./fixkey doctor`, or choose the model again with `./fixkey model` |
| *Intet svar fra modellen* | The model answered with nothing | Try again |
| *Ingen sikker rettelse* | The model's reply wasn't a plain correction (for example an answer or a translation), so it was dropped | Your text is unchanged. Rephrase, or check a shorter part. |
| *Teksten er for lang til ét tjek* | The reply was cut off | Put the cursor in a shorter part and check again |
| *Teksten er ændret – tjek igen* | You changed the text while the card was open | Tap the icon again |
| *Fjern markeringen først* | Text is selected | Tap once to remove the selection |
| *Skriv noget først* | There's no text to check | Type something |

### The Fixkey app says "Mac not found", "Relay not listening" or similar

The **Your Mac** section of the app checks the whole connection and shows a hint under **Status**. The fixes are the same as in the table above. **Check again** repeats the test.

### Fixkey won't open on the iPhone

The 7 days are probably over. Connect the iPhone and double-click **Reinstall Fixkey.command** (or run `./fixkey reinstall`). If the iPhone then says *Untrusted Developer*, trust your Apple ID under **Settings › General › VPN & Device Management**.

### The setup or reinstall stops with an error

The assistant explains the usual ones:

- **Xcode isn't signed in, or the sign-in expired:** **Xcode › Settings… › Apple Accounts**, sign in again.
- **The iPhone is locked:** unlock it and run the command again.
- **Developer Mode is off:** see [What is Developer Mode?](#what-is-developer-mode)
- **The app ID is taken:** pick another with `./fixkey configure --prefix com.yourname.something`, then `./fixkey reinstall`.
- **The 3-app limit:** delete another of your own apps from the iPhone (touch and hold its icon, then **Remove App**).

The full log is in the `build` folder.

### The Mac gets slow while Fixkey is running

On an 8 GB Mac, keep only one model loaded. Quit and reopen Llama.app, and close other big apps. The setup assistant also offers a memory limit for 8 GB Macs.

## Updating and removing Fixkey

### How do I update Fixkey?

Download the new version like the first time, and double-click Fixkey Setup in the new folder. It finds the settings of your earlier folder and offers to use them, so the iPhone keeps the same app; then it reinstalls the app. Afterwards you can delete the old folder.

With git: run `git pull` in the folder, then `./fixkey setup`.

### How do I remove Fixkey?

1. On the iPhone, touch and hold the Fixkey app and choose **Remove App**. The keyboard goes with it.
2. On the Mac, run `./fixkey uninstall` in the Fixkey folder. It removes the relay that starts by itself, the reminder, and their files and logs.
3. Delete the Fixkey folder.
4. Optionally, delete the model in Llama.app, and remove the Fixkey section from `~/.config/llama/models.user.ini`.
