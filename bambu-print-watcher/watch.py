"""Watches a Bambu Lab printer's local MQTT status feed and calls a
callback when a print starts and another when it finishes/fails.

Connects directly to the printer over the LAN (port 8883, TLS) - Bambu
Studio is not involved and does not need to be running. See README.md
for how to find --host / --serial / --access-code.

The on_print_started/on_print_finished functions below are the
intended hook point for triggering the (already-built) camera
automation; wire those up separately.
"""

import argparse
import json
import logging
import ssl
from typing import Optional

import paho.mqtt.client as mqtt

PRINT_FINISHED_STATES = {"FINISH", "FAILED"}


class PrintStateTracker:
    """Tracks gcode_state transitions and fires callbacks on print
    start/finish. Kept separate from the MQTT plumbing so the
    transition logic can be unit tested without a real printer.

    Uses an explicit in-progress flag rather than comparing consecutive
    states directly, so a PREPARE -> RUNNING transition still counts as
    a start, while a PAUSE -> RUNNING (resume) doesn't re-fire it.
    """

    def __init__(self, on_started, on_finished):
        self._on_started = on_started
        self._on_finished = on_finished
        self._last_state: Optional[str] = None
        self._print_in_progress = False

    def handle_state(self, state: str) -> None:
        if state == self._last_state:
            return
        self._last_state = state

        if state == "RUNNING" and not self._print_in_progress:
            self._print_in_progress = True
            self._on_started()
        elif state in PRINT_FINISHED_STATES and self._print_in_progress:
            self._print_in_progress = False
            self._on_finished()


def extract_gcode_state(payload: dict) -> Optional[str]:
    return payload.get("print", {}).get("gcode_state")


def on_print_started() -> None:
    # TODO: call your Scrapy-based camera-on trigger here.
    print("[bambu-print-watcher] print started -> camera ON (not wired up yet)")


def on_print_finished() -> None:
    # TODO: call your Scrapy-based camera-off trigger here.
    print("[bambu-print-watcher] print finished -> camera OFF (not wired up yet)")


def run(host: str, serial: str, access_code: str, port: int = 8883) -> None:
    tracker = PrintStateTracker(on_print_started, on_print_finished)
    topic = f"device/{serial}/report"

    def on_connect(client, userdata, connect_flags, reason_code, properties):
        if reason_code == 0:
            logging.info("connected, subscribing to %s", topic)
            client.subscribe(topic)
        else:
            logging.error("connection failed: %s", reason_code)

    def on_message(client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return
        state = extract_gcode_state(payload)
        if state:
            logging.info("gcode_state = %s", state)
            tracker.handle_state(state)

    def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
        logging.warning("disconnected (reason: %s), paho will auto-reconnect", reason_code)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.username_pw_set("bblp", access_code)
    # Bambu printers use a self-signed cert on the LAN; this is the
    # standard/expected way every community integration connects to them.
    client.tls_set(cert_reqs=ssl.CERT_NONE)
    client.tls_insecure_set(True)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    client.connect(host, port, keepalive=30)
    client.loop_forever()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Watch a Bambu Lab printer for print start/finish over local MQTT."
    )
    parser.add_argument("--host", required=True, help="Printer IP address")
    parser.add_argument("--serial", required=True, help="Printer serial number")
    parser.add_argument("--access-code", required=True, help="LAN access code (printer network settings)")
    parser.add_argument("--port", type=int, default=8883)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(asctime)s %(message)s",
    )
    run(args.host, args.serial, args.access_code, args.port)


if __name__ == "__main__":
    main()
