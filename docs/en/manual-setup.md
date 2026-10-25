# Manual setup

[Dansk](../da/manual-setup.md) · [Back to README](../../README.md) · [Guided setup](../../SETUP.md)

Most people should use the guided [SETUP.md](../../SETUP.md): `Fixkey Setup.command` (or `./fixkey setup`) does everything below and checks each step. This page is for developers who want to do it by hand or understand what the assistant does.

## What you need

- A Mac with Apple silicon and at least 8 GB memory. 8 GB is enough for one 4B model at a time.
- Xcode, signed in to an Apple ID (**Settings › Apple Accounts**). A free Personal Team works; its apps stop opening after 7 days.
- [Llama.app](https://llama.app), which includes the `llama` command-line tool.
- An iPhone with iOS 17 or later, with Developer Mode on.

Tested on an iPhone and an M2 MacBook Pro with 8 GB. The Mac and the iPhone must be on the same Wi-Fi network, or the Mac on the iPhone's Personal Hotspot.

## 1. The model

```bash
llama download -hf unsloth/Qwen3.5-4B-GGUF:Q4_K_M --no-mmproj
```

`--no-mmproj` skips the image part of the model, which Fixkey doesn't need. Quit and reopen Llama.app so it lists the model.

On an 8 GB Mac, a short context window keeps memory use low. Add this to `~/.config/llama/models.user.ini` and restart Llama.app:

```ini
[unsloth/Qwen3.5-4B-GGUF:Q4_K_M]
; Fixkey keyboard model: a small context keeps memory low on 8 GB Macs
ctx-size = 4096
```

Check that the model answers:

```bash
Tools/proofread-cli/run.sh "jeg har ikke mye tid idag"
# OUT: Jeg har ikke meget tid i dag.
```

Another model works the same way: download it with its own `owner/repo:QUANT` name and put that name in `FIXKEY_MODEL` (below). `./fixkey model evaluate <name>` scores it against the recommended model's 50/53.

## 2. Key, certificate and settings

Everything personal stays out of the code, in files git ignores:

| File | What it is |
|---|---|
| `Tools/lan-relay/key.txt` | The shared key. The relay requires it on every request. |
| `Tools/lan-relay/relay-cert.pem`, `relay-key.pem` | The relay's own certificate and private key, for HTTPS |
| `Config/Local.xcconfig` | Your team, bundle ID prefix, Mac name, ports, the key and the certificate's fingerprint |

`./fixkey configure` creates all of them (only you can read them). By hand:

```bash
(umask 077
 openssl rand -hex 24 > Tools/lan-relay/key.txt
 openssl ecparam -name prime256v1 -genkey -noout -out Tools/lan-relay/relay-key.pem
 openssl req -new -x509 -key Tools/lan-relay/relay-key.pem -sha256 -days 3650 \
   -subj "/CN=Fixkey relay" -out Tools/lan-relay/relay-cert.pem)
openssl x509 -in Tools/lan-relay/relay-cert.pem -outform der | shasum -a 256   # the fingerprint
```

Then copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and fill it in:

| Setting | Value |
|---|---|
| `DEVELOPMENT_TEAM` | Your team ID. `./fixkey doctor` confirms Xcode knows it. |
| `FIXKEY_BUNDLE_ID_PREFIX` | A reverse-domain name of your own, e.g. `com.yourname`. The app becomes `com.yourname.fixkey`, the keyboard `com.yourname.fixkey.keyboard`. |
| `FIXKEY_MAC_HOST` | The Mac's Bonjour name: `scutil --get LocalHostName` plus `.local` |
| `FIXKEY_RELAY_PORT` | The relay's port, e.g. `9932`. Keep it different from Llama.app's port. |
| `FIXKEY_LLAMA_PORT` | Llama.app's port (`defaults read app.llama.Llama serverPort`, default 9931). Used by the simulator. |
| `FIXKEY_API_KEY` | The contents of `key.txt` |
| `FIXKEY_RELAY_CERT_SHA256` | The fingerprint from above |
| `FIXKEY_MODEL` | The model in Llama.app, by default `unsloth/Qwen3.5-4B-GGUF:Q4_K_M`. The relay puts it into every request, so changing it needs no new build. |

The build copies these values into each target's `Info.plist`. The app trusts only the certificate with that fingerprint.

## 3. Build and install

The Xcode project is committed, so you can open `Fixkey.xcodeproj`, choose your iPhone and press **Run**. Or from Terminal:

```bash
xcrun devicectl list devices          # your iPhone's identifier
xcodebuild -project Fixkey.xcodeproj -scheme Fixkey -configuration Release \
  -destination 'id=<iphone-id>' -derivedDataPath build/device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <iphone-id> build/device/Build/Products/Release-iphoneos/Fixkey.app
```

The first time, trust your Apple ID on the iPhone under **Settings › General › VPN & Device Management**.

## 4. Start the relay

```bash
./fixkey relay          # or: Tools/lan-relay/run.sh
# Fixkey relay is running on https://Your-Mac.local:9932  (Ctrl+C to stop)
```

- It listens on the Mac's Wi-Fi address only (`en0`) and follows it when the address changes. On Ethernet, pass an address: `Tools/lan-relay/run.sh <address>`.
- It reads its port from `Config/Local.xcconfig` and Llama.app's port from Llama.app's own settings.
- The first time, macOS may ask whether Python may accept incoming connections. Allow it.
- To start it at login instead, run `./fixkey autostart on`. It copies the relay, key and certificate to `~/Library/Application Support/Fixkey/relay` and installs the LaunchAgent `local.fixkey.relay`, which listens only on Wi-Fi networks you allowed (`./fixkey autostart add`) and opens Llama.app when needed. [architecture.md](architecture.md#starting-by-itself) has the details.

Check it from the Mac: `./fixkey test`, or `python3 -I Tools/lan-relay/relay.py --check`. It connects the way the iPhone does (HTTPS, certificate fingerprint, key) and says which part fails.

## 5. Turn on the keyboard

On the iPhone:

1. Open the Fixkey app. Allow **Local Network** access when it asks. Under **Your Mac**, **Status** should say **Online**.
2. **Settings › Apps › Fixkey › Keyboards**: turn on **Fixkey** and **Allow Full Access**.
3. In any app, hold 🌐 and choose **Fixkey**.

## Changing settings later

- **New Mac name, or a new key or certificate:** run `./fixkey configure`, then `./fixkey reinstall`. To make a new key, delete `key.txt` first; for a new certificate, delete `relay-key.pem`.
- **Another model:** `./fixkey model`, or change `FIXKEY_MODEL` and restart the relay.
- **Every 7 days** with a free Apple ID: `./fixkey reinstall`, or double-click `Reinstall Fixkey.command`. It sets Fixkey's cached provisioning profiles aside first (and puts them back if the build fails), so each reinstall gives 7 days from that moment; a plain **Run** in Xcode reuses the cached profile until it expires. `./fixkey reminder on` lets the Mac do it by itself over Wi-Fi from 2 days before the end, and reminds you when it can't.

Problems: run `./fixkey doctor`, and see the [FAQ](faq.md#when-something-doesnt-work).
