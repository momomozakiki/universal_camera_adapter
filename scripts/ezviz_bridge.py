#!/usr/bin/env python3
"""Local EZVIZ Open Platform bridge: devices + account-config REST API.

Diagnostic/testing tool only, not part of the CameraAdapter contract. Wraps
EZVIZ's official Open Platform cloud API (https://open.ezvizlife.com) behind
a tiny local REST API, so any HTTP client (Flutter, curl) can list an
account's cameras, without embedding any EZVIZ-specific protocol logic
itself.

This replaces an earlier version of this script that spoke EZVIZ's
proprietary *local* SDK protocol (via the third-party `pyezvizapi` library,
ports 9010/9020). That path was abandoned after tracing it all the way
through login -> device discovery -> local connection -> decryption-key
retrieval, only to hit a hard limitation in `pyezvizapi`'s parser: this
camera's local stream uses an "IDMX" packet container the library doesn't
decode, independent of whether the device's video encryption is on or off.
The official cloud API below needs no local-protocol parsing at all.

This bridge is tied to ONE EZVIZ Open Platform app (one developer account),
configured via environment variables (never hardcoded, never accepted from
the Flutter client):
    EZVIZ_APP_KEY, EZVIZ_APP_SECRET

The Flutter client plays video itself via the `ezviz_flutter` package's
`EzvizSimplePlayer` widget, which wraps EZVIZ's own native Android/iOS SDKs -
it resolves a device's live stream directly from its serial plus this
account's `appKey`/`accessToken`, so this bridge's only job is to hand those
over; it never fetches or proxies a stream URL itself. (HLS/RTMP via
`live/address/get` with `protocol=2`/`3` were tried first and empirically
ruled out: this account's region returns "success" responses that don't
actually work - HLS playlists point at a fixed EZVIZ error-placeholder
segment, and the RTMP relay refuses the connection. A prior version of this
bridge returned `ezopen://` URLs from `protocol=1` for a WebView-embedded JS
player, but `ezviz_flutter`'s native widget needs no stream URL at all.)

Usage:
    EZVIZ_APP_KEY=... EZVIZ_APP_SECRET=... python scripts/ezviz_bridge.py [--host 127.0.0.1] [--port 8765]

Then, from any client on the same machine/network:
    GET /devices   -> [{"serial", "name", "model"}, ...]
    GET /config    -> {"appKey": "...", "accessToken": "..."}
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

_TOKEN_URL = "https://open.ezvizlife.com/api/lapp/token/get"
_TOKEN_REFRESH_MARGIN_SECONDS = 300
_REQUEST_TIMEOUT_SECONDS = 10


class OpenPlatformError(RuntimeError):
    """Raised when the Open Platform API itself reports a failure."""


class _TokenCache:
    """Fetches and transparently refreshes the Open Platform access token.

    A single shared token is held for the whole bridge process (this bridge
    intentionally supports one EZVIZ account per process - see module
    docstring), guarded by a lock so two concurrent requests can't both
    trigger a refetch.
    """

    def __init__(self, app_key: str, app_secret: str) -> None:
        self._app_key = app_key
        self._app_secret = app_secret
        self._lock = threading.Lock()
        self._access_token: str | None = None
        self._area_domain: str | None = None
        self._expire_at_seconds = 0.0

    def _fetch(self) -> None:
        body = urllib.parse.urlencode(
            {"appKey": self._app_key, "appSecret": self._app_secret}
        ).encode("ascii")
        request = urllib.request.Request(_TOKEN_URL, data=body, method="POST")
        with urllib.request.urlopen(request, timeout=_REQUEST_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read())
        if payload.get("code") != "200":
            raise OpenPlatformError(f"token/get failed: {payload}")
        data = payload["data"]
        self._access_token = data["accessToken"]
        self._area_domain = data["areaDomain"]
        self._expire_at_seconds = data["expireTime"] / 1000.0  # ms -> s

    def get(self) -> tuple[str, str]:
        with self._lock:
            now = time.time()
            if (
                self._access_token is None
                or now >= self._expire_at_seconds - _TOKEN_REFRESH_MARGIN_SECONDS
            ):
                self._fetch()
            assert self._access_token is not None
            assert self._area_domain is not None
            return self._access_token, self._area_domain


def _call(area_domain: str, path: str, params: dict[str, str]) -> dict[str, Any]:
    body = urllib.parse.urlencode(params).encode("ascii")
    request = urllib.request.Request(f"{area_domain}{path}", data=body, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=_REQUEST_TIMEOUT_SECONDS) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as err:
        return json.loads(err.read())


_tokens: _TokenCache
_app_key: str


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload).encode("utf-8")


class EzvizBridgeHandler(BaseHTTPRequestHandler):
    server_version = "EzvizBridge/3.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"{self.address_string()} - {fmt % args}\n")

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = _json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/devices":
            self._handle_devices()
            return
        if parsed.path == "/config":
            self._handle_config()
            return
        self._send_json(404, {"error": "not found"})

    def _handle_devices(self) -> None:
        try:
            access_token, area_domain = _tokens.get()
            result = _call(
                area_domain,
                "/api/lapp/device/list",
                {"accessToken": access_token, "pageStart": "0", "pageSize": "50"},
            )
        except (OpenPlatformError, urllib.error.URLError) as err:
            self._send_json(502, {"error": str(err)})
            return

        if result.get("code") != "200":
            self._send_json(502, {"error": result.get("msg", "device/list failed")})
            return

        devices = [
            {
                "serial": item["deviceSerial"],
                "name": item.get("deviceName"),
                "model": item.get("model"),
            }
            for item in result.get("data") or []
        ]
        self._send_json(200, {"devices": devices})

    def _handle_config(self) -> None:
        try:
            access_token, _ = _tokens.get()
        except (OpenPlatformError, urllib.error.URLError) as err:
            self._send_json(502, {"error": str(err)})
            return
        self._send_json(200, {"appKey": _app_key, "accessToken": access_token})


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    app_key = os.environ.get("EZVIZ_APP_KEY")
    app_secret = os.environ.get("EZVIZ_APP_SECRET")
    if not app_key or not app_secret:
        sys.exit("Set EZVIZ_APP_KEY and EZVIZ_APP_SECRET environment variables first.")

    global _tokens, _app_key
    _app_key = app_key
    _tokens = _TokenCache(app_key, app_secret)
    _tokens.get()  # fail fast on bad credentials, before serving any request

    server = ThreadingHTTPServer((args.host, args.port), EzvizBridgeHandler)
    print(f"EZVIZ bridge listening on http://{args.host}:{args.port}")
    print("Endpoints: GET /devices, GET /config")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
