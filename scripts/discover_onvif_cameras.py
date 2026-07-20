#!/usr/bin/env python3
"""WS-Discovery probe: find ONVIF-capable cameras on the local network.

Diagnostic tool only, not part of the CameraAdapter contract. Sends a single
SOAP WS-Discovery Probe as a UDP multicast and prints whatever replies within
the timeout window. Stdlib-only (socket), no third-party deps.

Usage:
    python scripts/discover_onvif_cameras.py [--timeout SECONDS]
"""

from __future__ import annotations

import argparse
import socket
import time
import uuid

MULTICAST_ADDR = "239.255.255.250"
MULTICAST_PORT = 3702

PROBE_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
            xmlns:w="http://www.w3.org/2005/08/addressing"
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
            xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <e:Header>
    <w:MessageID>uuid:{message_id}</w:MessageID>
    <w:To e:mustUnderstand="1">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action e:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
    <w:ReplyTo>
      <w:Address>http://www.w3.org/2005/08/addressing/anonymous</w:Address>
    </w:ReplyTo>
  </e:Header>
  <e:Body>
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>"""


def build_probe() -> bytes:
    message = PROBE_TEMPLATE.format(message_id=uuid.uuid4())
    return message.encode("utf-8")


def discover(timeout: float) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(timeout)

    probe = build_probe()
    print(f"Sending WS-Discovery Probe to {MULTICAST_ADDR}:{MULTICAST_PORT} "
          f"(listening {timeout}s for replies)...")
    sock.sendto(probe, (MULTICAST_ADDR, MULTICAST_PORT))

    deadline = time.monotonic() + timeout
    found = 0
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        sock.settimeout(remaining)
        try:
            data, addr = sock.recvfrom(65535)
        except socket.timeout:
            break

        found += 1
        text = data.decode("utf-8", errors="replace")
        xaddrs = _extract_tag(text, "XAddrs")
        types = _extract_tag(text, "Types")
        print(f"\n--- Reply #{found} from {addr[0]}:{addr[1]} ---")
        print(f"  Types : {types or '(not found)'}")
        print(f"  XAddrs: {xaddrs or '(not found)'}")

    sock.close()

    if found == 0:
        print("\nNo ONVIF ProbeMatch replies received.")
        print("This can mean the camera doesn't expose ONVIF, ONVIF is off in its")
        print("settings, or discovery traffic is being blocked by a firewall/router.")
        print("Fall back to your router's DHCP client list or the EZVIZ app's")
        print("device-info page to find the camera's IP manually.")
    else:
        print(f"\n{found} device(s) responded. Use the XAddrs host as --host for "
              "test_rtsp_connection.py.")


def _extract_tag(xml_text: str, tag: str) -> str | None:
    for prefix in ("d:", "dn:", ""):
        start_tag = f"<{prefix}{tag}>"
        end_tag = f"</{prefix}{tag}>"
        start = xml_text.find(start_tag)
        if start != -1:
            start += len(start_tag)
            end = xml_text.find(end_tag, start)
            if end != -1:
                return xml_text[start:end].strip()
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=4.0,
                         help="Seconds to listen for replies (default: 4.0)")
    args = parser.parse_args()
    discover(args.timeout)


if __name__ == "__main__":
    main()
