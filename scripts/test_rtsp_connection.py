#!/usr/bin/env python3
"""RTSP connectivity/auth check for a network camera (e.g. EZVIZ CS-H6c).

Diagnostic tool only, not part of the CameraAdapter contract. Speaks raw RTSP
over a TCP socket: OPTIONS, then DESCRIBE with Digest (RFC 2617) or Basic auth
if challenged. Stdlib-only (socket, hashlib), no third-party deps.

Usage:
    python scripts/test_rtsp_connection.py --host 192.168.1.50 \\
        --user admin --password SXPKLB
"""

from __future__ import annotations

import argparse
import hashlib
import socket
import sys

RECV_TIMEOUT = 5.0
RECV_BUFSIZE = 8192


def send_request(sock: socket.socket, request: str) -> str:
    sock.sendall(request.encode("utf-8"))
    chunks = []
    sock.settimeout(RECV_TIMEOUT)
    try:
        while True:
            chunk = sock.recv(RECV_BUFSIZE)
            if not chunk:
                break
            chunks.append(chunk)
            if len(chunk) < RECV_BUFSIZE:
                break
    except socket.timeout:
        pass
    return b"".join(chunks).decode("utf-8", errors="replace")


def parse_headers(response: str) -> dict[str, str]:
    headers: dict[str, str] = {}
    for line in response.split("\r\n")[1:]:
        if not line or ":" not in line:
            continue
        key, _, value = line.partition(":")
        headers[key.strip().lower()] = value.strip()
    return headers


def status_line(response: str) -> str:
    return response.split("\r\n", 1)[0] if response else "(no response)"


def parse_www_authenticate(value: str) -> tuple[str, dict[str, str]]:
    scheme, _, rest = value.partition(" ")
    params: dict[str, str] = {}
    for part in rest.split(","):
        part = part.strip()
        if "=" not in part:
            continue
        key, _, val = part.partition("=")
        params[key.strip()] = val.strip().strip('"')
    return scheme, params


def build_digest_header(method: str, uri: str, user: str, password: str,
                         params: dict[str, str]) -> str:
    realm = params.get("realm", "")
    nonce = params.get("nonce", "")
    qop = params.get("qop")

    ha1 = hashlib.md5(f"{user}:{realm}:{password}".encode()).hexdigest()
    ha2 = hashlib.md5(f"{method}:{uri}".encode()).hexdigest()

    if qop:
        nc = "00000001"
        cnonce = hashlib.md5(f"{user}{nonce}".encode()).hexdigest()[:16]
        response = hashlib.md5(
            f"{ha1}:{nonce}:{nc}:{cnonce}:{qop}:{ha2}".encode()
        ).hexdigest()
        return (
            f'Digest username="{user}", realm="{realm}", nonce="{nonce}", '
            f'uri="{uri}", qop={qop}, nc={nc}, cnonce="{cnonce}", '
            f'response="{response}"'
        )

    response = hashlib.md5(f"{ha1}:{nonce}:{ha2}".encode()).hexdigest()
    return (
        f'Digest username="{user}", realm="{realm}", nonce="{nonce}", '
        f'uri="{uri}", response="{response}"'
    )


def build_basic_header(user: str, password: str) -> str:
    import base64
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    return f"Basic {token}"


def run(host: str, port: int, user: str, password: str, path: str) -> int:
    rtsp_url = f"rtsp://{host}:{port}{path}"
    print(f"Target: {rtsp_url}")
    print(f"Connecting to {host}:{port}...")

    try:
        sock = socket.create_connection((host, port), timeout=RECV_TIMEOUT)
    except (socket.timeout, ConnectionRefusedError, OSError) as exc:
        print(f"\nFAILED: could not open TCP connection ({exc}).")
        print("Check the IP, that RTSP/local access is enabled in the EZVIZ app, "
              "and that nothing is blocking port 554.")
        return 1

    try:
        cseq = 1
        options_request = (
            f"OPTIONS {rtsp_url} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\n"
            f"\r\n"
        )
        options_response = send_request(sock, options_request)
        print(f"\nOPTIONS -> {status_line(options_response)}")
        if not options_response:
            print("FAILED: no response to OPTIONS. Server may not be RTSP, or is "
                  "dropping the connection.")
            return 1

        cseq += 1
        describe_request = (
            f"DESCRIBE {rtsp_url} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\n"
            f"Accept: application/sdp\r\n"
            f"\r\n"
        )
        describe_response = send_request(sock, describe_request)
        print(f"DESCRIBE -> {status_line(describe_response)}")

        headers = parse_headers(describe_response)
        if "401" in status_line(describe_response) and "www-authenticate" in headers:
            scheme, params = parse_www_authenticate(headers["www-authenticate"])
            cseq += 1
            if scheme.lower() == "digest":
                auth_header = build_digest_header(
                    "DESCRIBE", rtsp_url, user, password, params
                )
            else:
                auth_header = build_basic_header(user, password)

            sock.close()
            sock = socket.create_connection((host, port), timeout=RECV_TIMEOUT)
            authed_request = (
                f"DESCRIBE {rtsp_url} RTSP/1.0\r\n"
                f"CSeq: {cseq}\r\n"
                f"Accept: application/sdp\r\n"
                f"Authorization: {auth_header}\r\n"
                f"\r\n"
            )
            describe_response = send_request(sock, authed_request)
            print(f"DESCRIBE (with {scheme} auth) -> {status_line(describe_response)}")

        final_status = status_line(describe_response)
        print(f"\n=== Verdict ===")
        if final_status.startswith("RTSP/1.0 200"):
            print("SUCCESS: camera reachable, credentials accepted, stream described.")
            return 0
        elif "401" in final_status:
            print("FAILED: authentication rejected. Check --user/--password "
                  "(verification code is case-sensitive).")
            return 1
        elif "404" in final_status:
            print(f"FAILED: stream path not found at {path}. Try --path "
                  "/h264/ch1/sub/av_stream or check your camera's documented paths.")
            return 1
        else:
            print(f"FAILED: unexpected status ({final_status}).")
            return 1
    finally:
        sock.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="Camera IP address")
    parser.add_argument("--port", type=int, default=554, help="RTSP port (default: 554)")
    parser.add_argument("--user", default="admin", help="RTSP username (default: admin)")
    parser.add_argument("--password", required=True,
                         help="RTSP password (EZVIZ default: the device Verification Code)")
    parser.add_argument("--path", default="/h264/ch1/main/av_stream",
                         help="RTSP stream path (default: /h264/ch1/main/av_stream)")
    args = parser.parse_args()

    exit_code = run(args.host, args.port, args.user, args.password, args.path)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
