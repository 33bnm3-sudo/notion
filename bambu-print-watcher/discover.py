"""Listens for the periodic SSDP-style broadcast that Bambu Lab
printers send on the LAN every ~5 seconds (the same mechanism Bambu
Studio uses to auto-populate its printer list) and extracts IP,
serial number, model, and name for each one found.

The access code is deliberately NOT part of this broadcast (it would
be a security hole to advertise a password to the whole network), so
it still has to be entered by hand once - see README.md.

Run standalone to print discovered printers as JSON:
    python discover.py --timeout 5
"""

import argparse
import json
import re
import socket
from dataclasses import asdict, dataclass
from typing import Optional

DISCOVERY_PORT = 2021


@dataclass
class DiscoveredPrinter:
    ip: str
    serial: Optional[str]
    model: Optional[str]
    name: Optional[str]


def _extract_header(text: str, header: str) -> Optional[str]:
    match = re.search(rf"^{re.escape(header)}\s*:\s*(.+)$", text, re.IGNORECASE | re.MULTILINE)
    return match.group(1).strip() if match else None


def parse_packet(data: bytes, source_ip: str) -> Optional[DiscoveredPrinter]:
    try:
        text = data.decode("utf-8", errors="ignore")
    except Exception:
        return None

    if "bambu" not in text.lower():
        return None

    serial = _extract_header(text, "USN")
    model = _extract_header(text, "DevModel.bambu.com")
    name = _extract_header(text, "DevName.bambu.com")

    return DiscoveredPrinter(ip=source_ip, serial=serial, model=model, name=name)


def discover(timeout: float = 5.0) -> list[DiscoveredPrinter]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(0.5)
    sock.bind(("", DISCOVERY_PORT))

    found: dict[str, DiscoveredPrinter] = {}
    import time

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        printer = parse_packet(data, addr[0])
        if printer:
            found[printer.ip] = printer

    sock.close()
    return list(found.values())


def main() -> None:
    parser = argparse.ArgumentParser(description="Discover Bambu Lab printers on the LAN.")
    parser.add_argument("--timeout", type=float, default=5.0, help="seconds to listen")
    args = parser.parse_args()

    printers = discover(args.timeout)
    print(json.dumps([asdict(p) for p in printers]))


if __name__ == "__main__":
    main()
