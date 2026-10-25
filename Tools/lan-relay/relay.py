#!/usr/bin/env python3
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
"""Wi-Fi relay so Fixkey on the iPhone can reach Llama.app, which only accepts connections from this Mac.

It serves HTTPS with this Mac's own certificate (relay-cert.pem, made by ./fixkey setup), and the app trusts no other
certificate. It forwards only the two requests Fixkey makes, only with the shared key from key.txt, and logs the
method, path and status, never text. Run it while you use Fixkey (./fixkey relay), or let it start by itself when you
log in (./fixkey autostart on).

  relay.py [address]   listen on the Mac's Wi-Fi address (or the address given) until Ctrl+C
  relay.py --check     call the running relay the way the iPhone does, and report what's wrong if it fails
  relay.py --network-id   print an ID for the Wi-Fi network the Mac is on now, made from its router
  relay.py --on-allowed-network FILE   succeed if that network is one of those listed in FILE

Started by itself (./fixkey autostart on), it runs from ~/Library/Application Support/Fixkey with --port,
--networks (listen only on the Wi-Fi networks listed in that file) and --start-llama (open Llama.app when needed).

Every check uses the model chosen on this Mac (./fixkey model): the relay puts it into each request and names it in
each reply (X-Fixkey-Model), so changing the model needs nothing on the iPhone.
"""
import argparse
import hashlib
import hmac
import http.client
import json
import os
import re
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEY_FILE = HERE / "key.txt"
CERT_FILE = HERE / "relay-cert.pem"
CERT_KEY_FILE = HERE / "relay-key.pem"
LOCAL_CONFIG = HERE.parent.parent / "Config" / "Local.xcconfig"

DEFAULT_PORT = 9932
MAX_BODY = 64 * 1024
MAX_CONNECTIONS = 16
# A client gets this long to connect, finish the TLS handshake and send its whole request.
REQUEST_SECONDS = 15
# Llama.app may need to load the model first.
UPSTREAM_SECONDS = 120
# How long to wait for Llama.app after opening it for a check.
LLAMA_START_SECONDS = 40
ALLOWED = {("POST", "/v1/chat/completions"), ("GET", "/v1/models")}
LENGTH = re.compile(r"[0-9]{1,9}")
SETUP_HINT = "Run ./fixkey setup first."
# Never send the user's text through a proxy, even if the Mac has one configured.
UPSTREAM = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# What --check returns, so ./fixkey can explain the problem.
CHECK_OK, CHECK_UNREACHABLE, CHECK_WRONG_KEY, CHECK_NO_LLAMA, CHECK_CERTIFICATE = 0, 1, 2, 3, 4


def log(line):
    print(time.strftime("%H:%M:%S"), line, flush=True)


def load_key(path=None):
    """The shared key, as bytes. A blank or short key would let anyone in, so the relay refuses to start."""
    path = path or KEY_FILE
    try:
        key = path.read_text().strip()
    except OSError:
        key = ""
    if not re.fullmatch(r"[!-~]{32,}", key):
        sys.exit(f"The relay key in {path.name} is missing or too short. {SETUP_HINT}")
    return key.encode()


def fingerprint(der):
    return hashlib.sha256(der).hexdigest()


def certificate_fingerprint(path=None):
    """SHA-256 of the relay's certificate. The same value is built into the app (FIXKEY_RELAY_CERT_SHA256)."""
    return fingerprint(ssl.PEM_cert_to_DER_cert((path or CERT_FILE).read_text()))


def tls_context(cert=None, cert_key=None):
    cert, cert_key = cert or CERT_FILE, cert_key or CERT_KEY_FILE
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    try:
        context.load_cert_chain(cert, cert_key)
    except (OSError, ssl.SSLError):
        sys.exit(f"The relay's certificate ({cert.name}, {cert_key.name}) is missing or broken. {SETUP_HINT}")
    return context


class Relay(BaseHTTPRequestHandler):
    server_version = "Fixkey"
    sys_version = ""
    # One request per connection, so no client can hold a connection open between requests.
    protocol_version = "HTTP/1.0"

    def setup(self):
        # The whole request must arrive within REQUEST_SECONDS. This also closes idle or trickling connections
        # from other devices on the network, which never get as far as the key check.
        self.watchdog = threading.Timer(REQUEST_SECONDS, self.abort)
        self.watchdog.daemon = True
        self.watchdog.start()
        try:
            self.request.settimeout(REQUEST_SECONDS)
            self.request = self.server.context.wrap_socket(self.request, server_side=True,
                                                           do_handshake_on_connect=False)
            self.request.do_handshake()
            super().setup()
        except BaseException:
            self.watchdog.cancel()
            self.request.close()
            raise

    def abort(self):
        try:
            self.request.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def finish(self):
        self.watchdog.cancel()
        try:
            super().finish()
        finally:
            self.request.close()

    def forward(self):
        length = self.headers.get("Content-Length", "0").strip()
        length = int(length) if LENGTH.fullmatch(length) else None
        if (self.command, self.path) not in ALLOWED:
            return self.refuse(404, "Not found", length)
        # Header values arrive as Latin-1 text; compare bytes so odd characters can't crash the check.
        sent = self.headers.get("Authorization", "").encode("latin-1", "replace")
        if not hmac.compare_digest(sent, b"Bearer " + self.server.key):
            return self.refuse(401, "Missing or wrong key", length)
        if length is None:
            return self.reply(400, "Bad Content-Length")
        if length > MAX_BODY:
            return self.reply(413, "Text too long")
        if self.command == "POST" and length == 0:
            return self.reply(411, "Content-Length required")
        body = self.rfile.read(length) if length else None
        if body is not None and len(body) < length:
            return
        # The request is complete; answering may take as long as the model needs.
        self.watchdog.cancel()
        body = use_model(body, self.server.model)
        for attempt in range(2):
            request = urllib.request.Request(self.server.upstream + self.path, data=body, method=self.command,
                                             headers={"Content-Type": "application/json"})
            try:
                with UPSTREAM.open(request, timeout=UPSTREAM_SECONDS) as response:
                    return self.send(response.status, response.read())
            except urllib.error.HTTPError as error:
                return self.send(error.code, error.read())
            except OSError as error:
                # urllib wraps a timeout in URLError.reason; a timeout while reading the reply comes unwrapped.
                if isinstance(getattr(error, "reason", error), (socket.timeout, TimeoutError)):
                    return self.reply(504, "Llama.app took too long to answer")
                # Llama.app isn't running: started by itself, the relay opens it once and tries again.
                if attempt == 0 and self.server.start_llama and self.server.wake_llama():
                    continue
                return self.reply(502, "Llama.app is not reachable on this Mac")

    do_GET = do_POST = forward

    def refuse(self, status, message, length):
        # Read a small body first: closing a connection with unread data resets it, and the client could miss
        # the answer (for example a wrong key, which the app would then show as an unreachable Mac).
        if length and length <= MAX_BODY:
            self.rfile.read(length)
        self.reply(status, message)

    def reply(self, status, message):
        self.send(status, json.dumps({"error": {"message": message}}).encode())

    def send(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        if self.server.model:
            self.send_header("X-Fixkey-Model", self.server.model)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_request(self, code="-", size="-"):
        # Only Fixkey's own requests are named. Anything else is untrusted text and stays out of the terminal.
        request = (getattr(self, "command", None), getattr(self, "path", None))
        what = " ".join(request) if request in ALLOWED else "other request"
        log(f"{self.client_address[0]}  {what}  {int(code) if isinstance(code, int) else code}")

    def log_message(self, format, *args):
        pass


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, key, context, upstream, start_llama=False, model=None):
        self.key, self.context, self.upstream, self.start_llama, self.model = key, context, upstream, start_llama, model
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        self.llama_lock = threading.Lock()
        self.open_llama = open_llama
        super().__init__(address, Relay)

    def wake_llama(self):
        """Opens Llama.app (one check at a time) and waits until it answers. True if it does."""
        with self.llama_lock:
            if llama_answers(self.upstream):
                return True
            log("Opening Llama.app for a check…")
            self.open_llama()
            deadline = time.monotonic() + LLAMA_START_SECONDS
            while time.monotonic() < deadline:
                time.sleep(0.5)
                if llama_answers(self.upstream):
                    return True
            log("Llama.app didn't start.")
            return False

    def process_request(self, request, client_address):
        # Beyond MAX_CONNECTIONS at once, new connections are closed right away instead of piling up.
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        # Not TLS, a failed handshake, a timeout or a dropped connection: one line, no traceback.
        log(f"{client_address[0]}  connection closed ({type(sys.exc_info()[1]).__name__})")


def use_model(body, model):
    """The request with the model chosen on this Mac. A body that isn't a JSON object goes on unchanged."""
    if not body or not model:
        return body
    try:
        request = json.loads(body)
        request["model"] = model
        return json.dumps(request).encode()
    except (ValueError, TypeError):
        return body


def run(command):
    return subprocess.run(command, capture_output=True, text=True).stdout.strip()


def llama_port():
    # Llama.app keeps its server port in its own settings (default 9931).
    port = run(["defaults", "read", "app.llama.Llama", "serverPort"])
    return port if port.isdigit() else "9931"


def local_setting(setting):
    """A value from Config/Local.xcconfig, or None."""
    try:
        for line in LOCAL_CONFIG.read_text().splitlines():
            name, _, value = line.partition("=")
            if name.strip() == setting and value.strip():
                return value.strip()
    except OSError:
        pass
    return None


def relay_port():
    """FIXKEY_RELAY_PORT from Config/Local.xcconfig, the same value that is built into the app."""
    port = local_setting("FIXKEY_RELAY_PORT")
    return int(port) if port and port.isdigit() else DEFAULT_PORT


def wifi_address():
    return run(["ipconfig", "getifaddr", "en0"])


def open_llama():
    # In the background: no window comes to the front.
    subprocess.run(["open", "-g", "-b", "app.llama.Llama"], capture_output=True)


def parse_arp(text):
    """The hardware address in a line of `arp -n` output, written with two digits per part, or None."""
    match = re.search(r" at ([0-9a-fA-F]{1,2}(?::[0-9a-fA-F]{1,2}){5}) ", text)
    return ":".join(part.zfill(2) for part in match.group(1).lower().split(":")) if match else None


def router_hardware(router):
    """The router's hardware address if the Mac knows it. A VPN can keep the Mac from asking, so it may be None."""
    address = parse_arp(run(["arp", "-n", router]))
    if not address:
        # An empty entry fills in after one packet to the router.
        subprocess.run(["ping", "-c", "1", "-t", "1", router], capture_output=True)
        address = parse_arp(run(["arp", "-n", router]))
    return address


def digest(text):
    return hashlib.sha256(f"fixkey-network:{text}".encode()).hexdigest()[:16]


def network_id(settings=None, hardware=None):
    """An ID for the Wi-Fi network the Mac is on: "<settings>" or "<settings>+<router>".

    <settings> hashes the router, subnet, DHCP server and DNS addresses from the Mac's Wi-Fi lease, which macOS
    always has. <router> hashes the router's hardware address when the Mac knows it, which tells apart networks
    that happen to use the same addresses. Only these hashes are ever stored."""
    if settings is None:
        settings = [run(["ipconfig", "getoption", "en0", option])
                    for option in ("router", "subnet_mask", "server_identifier", "domain_name_server")]
        hardware = router_hardware(settings[0]) if settings[0] else None
    if not settings or not settings[0]:
        return None
    return digest("settings:" + "|".join(settings)) + (f"+{digest('router:' + hardware)}" if hardware else "")


def network_allowed(current, allowed):
    """True when the current network is one of the allowed ones. The router part decides when both IDs have one;
    otherwise the settings part does."""
    if not current:
        return False
    settings, _, router = current.partition("+")
    for entry in allowed:
        entry_settings, _, entry_router = entry.partition("+")
        if entry_settings == settings and (not entry_router or not router or entry_router == router):
            return True
    return False


def read_networks(path):
    try:
        return [line.strip() for line in Path(path).read_text().splitlines() if line.strip() and line[0] != "#"]
    except OSError:
        return []


LANGUAGE = "en"
NOT_ALLOWED = {
    "en": "The relay doesn't listen on this Wi-Fi network. If it's yours, run ./fixkey autostart add.",
    "da": "Relæet lytter ikke på dette Wi-Fi-netværk. Er det dit, så kør ./fixkey autostart add.",
}


def notify(message):
    """A macOS notification, for things that need attention while the relay runs on its own."""
    subprocess.run(["osascript", "-e", f'display notification "{message}" with title "Fixkey"'], capture_output=True)


def trim_log(limit=1_000_000):
    """Started by itself, the relay writes to a log file; keep that file small."""
    try:
        if not sys.stdout.isatty() and os.fstat(sys.stdout.fileno()).st_size > limit:
            os.ftruncate(sys.stdout.fileno(), 0)
    except (OSError, ValueError):
        pass


def mac_name():
    name = run(["scutil", "--get", "LocalHostName"])
    return f"{name}.local" if name else "this Mac"


def llama_answers(upstream):
    try:
        with UPSTREAM.open(upstream + "/v1/models", timeout=3):
            return True
    except OSError:
        return False


def serve(fixed_address=None, port=None, networks=None, start_llama=False, model=None):
    key, context, port = load_key(), tls_context(), port or relay_port()
    model = model or local_setting("FIXKEY_MODEL")
    upstream = f"http://127.0.0.1:{llama_port()}"
    trim_log()
    if not start_llama and not llama_answers(upstream):
        log(f"Llama.app isn't answering on port {upstream.rsplit(':', 1)[1]} yet. Open Llama.app; the relay waits.")
    waiting, told = None, set()
    while True:
        address = fixed_address or wifi_address()
        current = network_id() if networks and address else None
        reason = None
        if not address:
            reason = "This Mac has no Wi-Fi address. Waiting for Wi-Fi…"
        elif networks and not network_allowed(current, read_networks(networks)):
            reason = "This Wi-Fi network isn't one you allowed, so the relay doesn't listen here. Waiting…"
            settings = (current or "").partition("+")[0]
            if settings not in told:
                told.add(settings)
                notify(NOT_ALLOWED.get(LANGUAGE, NOT_ALLOWED["en"]))
        if reason:
            if reason != waiting:
                log(reason)
                waiting = reason
            time.sleep(15 if networks else 5)
            continue
        waiting = None
        try:
            server = Server((address, port), key, context, upstream, start_llama=start_llama, model=model)
        except OSError as error:
            sys.exit(f"Can't use port {port} ({error.strerror}). Is the relay already running in another window?")
        print(f"Fixkey relay is running on https://{mac_name()}:{port}  (Ctrl+C to stop)", flush=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            # A new Wi-Fi address (another network, or a new address from the router) needs a new listener,
            # and Llama.app's port may change in its settings.
            ticks = 0
            while fixed_address or wifi_address() == address:
                time.sleep(5)
                upstream = server.upstream = f"http://127.0.0.1:{llama_port()}"
                ticks += 1
                if networks and ticks % 6 == 0 and not network_allowed(network_id(), read_networks(networks)):
                    log("The Mac is no longer on a Wi-Fi network you allowed. The relay stops listening.")
                    break
            else:
                log("The Mac's Wi-Fi address changed. Restarting the relay…")
        finally:
            server.shutdown()
            server.server_close()


def check(host=None, port=None):
    """Calls GET /v1/models through the relay like the iPhone does. Returns one of the CHECK_ codes.
    By default it uses the Wi-Fi address, which is what the iPhone reaches. On the Mac itself, its own name can
    also mean 127.0.0.1, where Llama.app may listen on the same port."""
    host, port = host or wifi_address() or mac_name(), port or relay_port()
    key, expected = load_key(), certificate_fingerprint()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    # The certificate is checked against the fingerprint below, the same way the app checks it.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    connection = http.client.HTTPSConnection(host, port, timeout=10, context=context)
    try:
        connection.connect()
        if fingerprint(connection.sock.getpeercert(binary_form=True)) != expected:
            print("The relay answered with a different certificate than the one in relay-cert.pem.")
            return CHECK_CERTIFICATE
        connection.request("GET", "/v1/models", headers={"Authorization": "Bearer " + key.decode()})
        status = connection.getresponse().status
    except (OSError, http.client.HTTPException) as error:
        print(f"Can't reach the relay on {host}:{port} ({error}). Is it running? Start it with ./fixkey relay")
        return CHECK_UNREACHABLE
    finally:
        connection.close()
    if status == 200:
        print(f"The relay on {host}:{port} works: secure connection, key accepted, Llama.app answers.")
        return CHECK_OK
    if status == 401:
        print("The relay refused the key. Run ./fixkey setup to make the key and the app match again.")
        return CHECK_WRONG_KEY
    print(f"The relay works, but Llama.app doesn't answer (HTTP {status}). Open Llama.app on this Mac.")
    return CHECK_NO_LLAMA


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fixkey's Wi-Fi relay to Llama.app")
    parser.add_argument("address", nargs="?", help="address to listen on (default: the Mac's Wi-Fi address)")
    parser.add_argument("--port", type=int, help="port (default: FIXKEY_RELAY_PORT in Config/Local.xcconfig)")
    parser.add_argument("--networks", help="listen only on the Wi-Fi networks listed in this file (see --network-id)")
    parser.add_argument("--start-llama", action="store_true", help="open Llama.app when a check needs it")
    parser.add_argument("--language", choices=["en", "da"], default="en", help="language of notifications")
    parser.add_argument("--model", help="model for every check (default: FIXKEY_MODEL in Config/Local.xcconfig)")
    parser.add_argument("--network-id", action="store_true", help="print the ID of the Mac's Wi-Fi network, then exit")
    parser.add_argument("--on-allowed-network", metavar="FILE",
                        help="exit with 0 if the Mac's Wi-Fi network is one of those listed in FILE")
    parser.add_argument("--check", action="store_true", help="check a running relay, then exit")
    args = parser.parse_args()
    LANGUAGE = args.language
    try:
        if args.network_id:
            current = network_id()
            print(current or "")
            sys.exit(0 if current else 1)
        if args.on_allowed_network:
            sys.exit(0 if network_allowed(network_id(), read_networks(args.on_allowed_network)) else 1)
        if args.check:
            sys.exit(check(args.address, args.port))
        serve(args.address, args.port, args.networks, args.start_llama, args.model)
    except KeyboardInterrupt:
        print("\nRelay stopped.")
