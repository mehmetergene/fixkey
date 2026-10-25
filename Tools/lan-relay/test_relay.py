#!/usr/bin/env python3
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
"""Tests for relay.py: TLS and the certificate, the key, request limits, timeouts and logging.
A fake Llama.app stands in, so no model is needed. Usage: python3 -I Tools/lan-relay/test_relay.py
"""
import contextlib
import http.client
import importlib.util
import io
import json
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("relay", HERE / "relay.py")
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)

KEY = "0123456789abcdef" * 3
TEXT = "jeg har ikke mye tid idag, hemmelig tekst"


def make_certificate(folder, name):
    key, cert = folder / f"{name}-key.pem", folder / f"{name}-cert.pem"
    subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key], check=True)
    subprocess.run(["openssl", "req", "-new", "-x509", "-key", key, "-sha256", "-days", "30",
                    "-subj", "/CN=Fixkey relay", "-out", cert], check=True, capture_output=True)
    return cert, key


class FakeLlama(BaseHTTPRequestHandler):
    delay = 0

    def do_GET(self):
        self.answer({"data": [{"id": "model"}]})

    def do_POST(self):
        time.sleep(FakeLlama.delay)
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.answer({"echo": body.decode()})

    def answer(self, value):
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def unverified():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


class RelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp())
        cls.cert, cls.cert_key = make_certificate(cls.folder, "relay")
        cls.other_cert, cls.other_key = make_certificate(cls.folder, "other")
        (cls.folder / "key.txt").write_text(KEY + "\n")
        relay.KEY_FILE, relay.CERT_FILE, relay.CERT_KEY_FILE = cls.folder / "key.txt", cls.cert, cls.cert_key
        cls.llama = HTTPServer(("127.0.0.1", 0), FakeLlama)
        threading.Thread(target=cls.llama.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.llama.shutdown()

    def setUp(self):
        self.logs = []
        relay.log = self.logs.append
        relay.REQUEST_SECONDS, relay.UPSTREAM_SECONDS, relay.MAX_CONNECTIONS = 1, 2, 4
        relay.LLAMA_START_SECONDS = 2
        FakeLlama.delay = 0
        self.start(f"http://127.0.0.1:{self.llama.server_address[1]}")

    def start(self, upstream, cert=None, cert_key=None):
        self.server = relay.Server(("127.0.0.1", 0), KEY.encode(), relay.tls_context(cert, cert_key), upstream)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def request(self, method, path, key=KEY, body=None, headers=None):
        connection = http.client.HTTPSConnection("127.0.0.1", self.port, timeout=5, context=unverified())
        headers = dict(headers or {})
        if key is not None:
            headers["Authorization"] = f"Bearer {key}"
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def raw(self, data, wait=3.0):
        """Sends bytes over TLS and returns the status line ('' if the relay closed the connection)."""
        with socket.create_connection(("127.0.0.1", self.port), timeout=wait) as sock:
            with unverified().wrap_socket(sock) as tls:
                tls.sendall(data)
                try:
                    return tls.recv(200).split(b"\r\n")[0].decode()
                except (OSError, ssl.SSLError):
                    return ""

    # The requests Fixkey makes

    def test_models_with_key(self):
        status, data = self.request("GET", "/v1/models")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)["data"][0]["id"], "model")

    def test_chat_body_is_forwarded(self):
        body = json.dumps({"text": TEXT}).encode()
        status, data = self.request("POST", "/v1/chat/completions", body=body)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(json.loads(data)["echo"])["text"], TEXT)

    # The key

    def test_missing_or_wrong_key(self):
        self.assertEqual(self.request("GET", "/v1/models", key=None)[0], 401)
        self.assertEqual(self.request("GET", "/v1/models", key="wrong")[0], 401)
        self.assertEqual(self.request("GET", "/v1/models", key=KEY + "x")[0], 401)
        self.assertEqual(self.request("GET", "/v1/models", key="")[0], 401)

    def test_wrong_key_with_text_is_answered_every_time(self):
        # The app shows "wrong key" only if the 401 arrives; an unread body would reset the connection instead.
        body = json.dumps({"text": TEXT * 50}).encode()
        for _ in range(20):
            self.assertEqual(self.request("POST", "/v1/chat/completions", key="wrong", body=body)[0], 401)

    def test_non_ascii_key_is_refused_not_crashed(self):
        line = self.raw(b"GET /v1/models HTTP/1.0\r\nAuthorization: Bearer \xe6\xf8\xe5\r\n\r\n")
        self.assertIn("401", line)

    def test_blank_short_or_missing_key_file_stops_the_relay(self):
        for content in ["", "\n", "   \n", "short-key"]:
            path = self.folder / "bad-key.txt"
            path.write_text(content)
            with self.assertRaises(SystemExit):
                relay.load_key(path)
        with self.assertRaises(SystemExit):
            relay.load_key(self.folder / "missing.txt")
        self.assertEqual(relay.load_key(), KEY.encode())

    # Only Fixkey's two requests

    def test_other_paths_and_methods(self):
        self.assertEqual(self.request("GET", "/v1/models?x=1")[0], 404)
        self.assertEqual(self.request("GET", "/props")[0], 404)
        self.assertEqual(self.request("POST", "/v1/models", body=b"{}")[0], 404)
        self.assertEqual(self.request("GET", "/v1/chat/completions")[0], 404)
        self.assertEqual(self.request("DELETE", "/v1/models")[0], 501)

    # Request size

    def test_bad_content_lengths(self):
        start = b"POST /v1/chat/completions HTTP/1.0\r\nAuthorization: Bearer " + KEY.encode()
        for length, expected in [(b"abc", "400"), (b"-1", "400"), (b"1e3", "400"), (b"\xb2", "400"),
                                 (str(relay.MAX_BODY + 1).encode(), "413")]:
            line = self.raw(start + b"\r\nContent-Length: " + length + b"\r\n\r\n{}")
            self.assertIn(expected, line, length)
        self.assertIn("411", self.raw(start + b"\r\n\r\n"))

    # TLS and the certificate

    def test_plain_http_gets_no_answer(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=3) as sock:
            sock.sendall(b"GET /v1/models HTTP/1.0\r\nAuthorization: Bearer " + KEY.encode() + b"\r\n\r\n")
            try:
                answer = sock.recv(200)
            except ConnectionResetError:
                answer = b""
            self.assertNotIn(b"HTTP/", answer)

    def test_certificate_is_the_one_from_setup(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=3) as sock:
            with unverified().wrap_socket(sock) as tls:
                served = relay.fingerprint(tls.getpeercert(binary_form=True))
                self.assertGreaterEqual(tls.version(), "TLSv1.2")
        self.assertEqual(served, relay.certificate_fingerprint(self.cert))
        self.assertNotEqual(served, relay.certificate_fingerprint(self.other_cert))

    def test_old_tls_versions_are_refused(self):
        context = unverified()
        context.minimum_version = ssl.TLSVersion.MINIMUM_SUPPORTED
        context.maximum_version = ssl.TLSVersion.TLSv1_1
        with socket.create_connection(("127.0.0.1", self.port), timeout=3) as sock:
            with self.assertRaises((ssl.SSLError, OSError)):
                context.wrap_socket(sock).close()

    # Slow or idle clients

    def test_idle_connection_is_closed(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            start = time.monotonic()
            self.assertEqual(sock.recv(10), b"")
            self.assertLess(time.monotonic() - start, relay.REQUEST_SECONDS + 1.5)

    def test_trickling_request_is_closed(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            with unverified().wrap_socket(sock) as tls:
                start = time.monotonic()
                with self.assertRaises((OSError, ssl.SSLError)):
                    for byte in b"GET /v1/models HTTP/1.0\r\nX-Slow: " + b"a" * 40:
                        tls.sendall(bytes([byte]))
                        time.sleep(0.2)
                    tls.recv(10) or (_ for _ in ()).throw(ConnectionError("closed"))
                self.assertLess(time.monotonic() - start, relay.REQUEST_SECONDS + 2)

    def test_connection_limit(self):
        idle = [socket.create_connection(("127.0.0.1", self.port), timeout=5) for _ in range(relay.MAX_CONNECTIONS)]
        time.sleep(0.2)
        try:
            with socket.create_connection(("127.0.0.1", self.port), timeout=5) as extra:
                start = time.monotonic()
                self.assertEqual(extra.recv(10), b"")
                self.assertLess(time.monotonic() - start, 0.5)
        finally:
            for sock in idle:
                sock.close()
        time.sleep(relay.REQUEST_SECONDS + 0.5)
        self.assertEqual(self.request("GET", "/v1/models")[0], 200)

    # Llama.app problems

    def test_llama_not_running(self):
        self.tearDown()
        with socket.socket() as closed:
            closed.bind(("127.0.0.1", 0))
            port = closed.getsockname()[1]
        self.start(f"http://127.0.0.1:{port}")
        self.assertEqual(self.request("GET", "/v1/models")[0], 502)

    def test_llama_too_slow(self):
        FakeLlama.delay = relay.UPSTREAM_SECONDS + 1
        self.assertEqual(self.request("POST", "/v1/chat/completions", body=b"{}")[0], 504)

    # Logs

    def test_logs_hold_no_text_and_no_control_characters(self):
        self.request("POST", "/v1/chat/completions", body=json.dumps({"text": TEXT}).encode())
        self.raw(b"GET /\x1b[31mred\x1b[0m HTTP/1.0\r\n\r\n")
        self.raw(b"GET /v1/models HTTP/1.0\r\nAuthorization: Bearer " + KEY.encode() + b"\r\n\r\n")
        joined = "\n".join(self.logs)
        self.assertIn("POST /v1/chat/completions  200", joined)
        self.assertIn("other request", joined)
        for secret in ["hemmelig", "\x1b", "red", KEY]:
            self.assertNotIn(secret, joined)

    # The model chosen on the Mac

    def test_the_chosen_model_is_used_and_named(self):
        self.server.model = "chosen/model-GGUF:Q4_K_M"
        body = json.dumps({"model": "something/else", "messages": []}).encode()
        connection = http.client.HTTPSConnection("127.0.0.1", self.port, timeout=5, context=unverified())
        connection.request("POST", "/v1/chat/completions", body=body, headers={"Authorization": f"Bearer {KEY}"})
        response = connection.getresponse()
        forwarded = json.loads(json.loads(response.read())["echo"])
        connection.close()
        self.assertEqual(forwarded["model"], "chosen/model-GGUF:Q4_K_M")
        self.assertEqual(response.getheader("X-Fixkey-Model"), "chosen/model-GGUF:Q4_K_M")

    def test_a_body_that_isnt_json_goes_on_unchanged(self):
        self.assertEqual(relay.use_model(b"not json", "m"), b"not json")
        self.assertEqual(relay.use_model(b"[1, 2]", "m"), b"[1, 2]")
        self.assertEqual(relay.use_model(None, "m"), None)
        self.assertEqual(relay.use_model(b'{"model": "a"}', None), b'{"model": "a"}')

    # Started by itself: Llama.app on demand

    def test_llama_is_opened_when_a_check_needs_it(self):
        self.tearDown()
        with socket.socket() as closed:
            closed.bind(("127.0.0.1", 0))
            port = closed.getsockname()[1]
        relay.LLAMA_START_SECONDS = 5
        self.server = relay.Server(("127.0.0.1", 0), KEY.encode(), relay.tls_context(),
                                   f"http://127.0.0.1:{port}", start_llama=True)
        self.port = self.server.server_address[1]
        opened = []

        def open_llama():
            opened.append(True)
            llama = HTTPServer(("127.0.0.1", port), FakeLlama)
            threading.Thread(target=llama.serve_forever, daemon=True).start()
            self.addCleanup(llama.server_close)
            self.addCleanup(llama.shutdown)

        self.server.open_llama = open_llama
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.assertEqual(self.request("GET", "/v1/models")[0], 200)
        self.assertEqual(opened, [True])
        self.assertIn("Opening Llama.app for a check…", self.logs)
        self.assertEqual(self.request("POST", "/v1/chat/completions", body=b"{}")[0], 200)
        self.assertEqual(opened, [True], "opened once")

    # Started by itself: only on allowed Wi-Fi networks

    def test_router_hardware_address_from_arp(self):
        self.assertEqual(relay.parse_arp("? (router) at 0:1a:b:3c:4d:5e on en0 ifscope [ethernet]"),
                         "00:1a:0b:3c:4d:5e")
        self.assertIsNone(relay.parse_arp("router (router) -- no entry"))

    def test_network_ids(self):
        home = ["router-a", "mask", "server-a", "dns-a"]
        plain = relay.network_id(home)
        with_router = relay.network_id(home, "00:11:22:33:44:55")
        self.assertRegex(plain, r"^[0-9a-f]{16}$")
        self.assertEqual(with_router.partition("+")[0], plain)
        self.assertRegex(with_router, r"^[0-9a-f]{16}\+[0-9a-f]{16}$")
        self.assertEqual(relay.network_id(home), plain, "the same network gives the same ID")
        self.assertNotEqual(relay.network_id(["router-b", "mask", "server-a", "dns-a"]), plain)
        self.assertIsNone(relay.network_id(["", "", "", ""]))
        for value in [plain, with_router]:
            self.assertNotIn("router-a", value)

    def test_allowed_networks(self):
        home = relay.network_id(["router-a", "mask", "server-a", "dns-a"], "00:11:22:33:44:55")
        same_settings_other_router = relay.network_id(["router-a", "mask", "server-a", "dns-a"], "66:77:88:99:aa:bb")
        home_behind_vpn = home.partition("+")[0]
        cafe = relay.network_id(["router-c", "mask", "server-c", "dns-c"])
        self.assertTrue(relay.network_allowed(home, [home]))
        self.assertTrue(relay.network_allowed(home_behind_vpn, [home]), "router unknown now: the settings decide")
        self.assertTrue(relay.network_allowed(home, [home_behind_vpn]), "router unknown when allowed")
        self.assertFalse(relay.network_allowed(same_settings_other_router, [home]), "same addresses, other router")
        self.assertFalse(relay.network_allowed(cafe, [home]))
        self.assertFalse(relay.network_allowed(None, [home]))
        self.assertFalse(relay.network_allowed(home, []))

    def test_networks_file(self):
        path = self.folder / "networks.txt"
        path.write_text("# allowed networks\n\nabc\n  def+123  \n")
        self.assertEqual(relay.read_networks(path), ["abc", "def+123"])
        self.assertEqual(relay.read_networks(self.folder / "missing.txt"), [])

    # relay.py --check

    def test_check_reports_each_problem(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.check_each_problem()

    def check_each_problem(self):
        self.assertEqual(relay.check("127.0.0.1", self.port), relay.CHECK_OK)
        relay.CERT_FILE = self.other_cert
        try:
            self.assertEqual(relay.check("127.0.0.1", self.port), relay.CHECK_CERTIFICATE)
        finally:
            relay.CERT_FILE = self.cert
        (self.folder / "other-key.txt").write_text("f" * 48)
        relay.KEY_FILE = self.folder / "other-key.txt"
        try:
            self.assertEqual(relay.check("127.0.0.1", self.port), relay.CHECK_WRONG_KEY)
        finally:
            relay.KEY_FILE = self.folder / "key.txt"
        port = self.port
        self.tearDown()
        self.assertEqual(relay.check("127.0.0.1", port), relay.CHECK_UNREACHABLE)
        self.start("http://127.0.0.1:9")
        self.assertEqual(relay.check("127.0.0.1", self.port), relay.CHECK_NO_LLAMA)


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0]], exit=False, verbosity=1).result
    print("All relay tests pass." if result.wasSuccessful() else "Relay tests FAILED.")
    sys.exit(0 if result.wasSuccessful() else 1)
