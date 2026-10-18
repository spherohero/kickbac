"""Operator-only private SSH -> RAM -> local USB device credential relay.

Uses the existing authorized demo device; does not provision/rotate credentials,
read OS Wi-Fi profiles, print credentials or write them to a local file.
Device auth stays in RAM unless explicitly opted into on-device NVS storage.
"""

import argparse
import re
import shlex
import subprocess
import time
from pathlib import Path

REMOTE_RELAY = r"""
import hashlib, hmac, os, re, sqlite3, stat, sys
try:
    fd = os.open('/etc/kickbac/device-credentials/kb-demo-01.secret', os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ValueError()
        value = stream.read(128)
    if not re.fullmatch(rb'[A-Za-z0-9_-]{43}\n', value):
        raise ValueError()
    token = value[:-1]
    with sqlite3.connect('file:/var/lib/kickbac/kickbac.sqlite3?mode=ro', uri=True) as db:
        row = db.execute('SELECT credential_hash FROM devices WHERE id=?', ('kb-demo-01',)).fetchone()
    if not row or not hmac.compare_digest(hashlib.sha256(token).hexdigest(), row[0]):
        raise ValueError()
    sys.stdout.buffer.write(token)
except Exception:
    sys.exit(1)
"""


def build_device_frame(token: bytes) -> bytearray:
    if re.fullmatch(rb"[A-Za-z0-9_-]{43}", token) is None:
        raise ValueError("Device credential format rejected; no values logged.")
    return bytearray(b"KBD1") + token


def relay_frame() -> bytearray:
    result = subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "ConnectTimeout=10",
            "root@144.202.38.243",
            "python3 -c " + shlex.quote(REMOTE_RELAY),
        ],
        capture_output=True,
        timeout=25,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError("Private operator relay unavailable; no values logged.")
    return build_device_frame(result.stdout)


def safe_line(raw: bytes) -> str | None:
    # Output is accepted only for exact firmware-owned stage/field formats.
    text = raw.decode("ascii", errors="replace").strip()
    patterns = (
        r"probe_(?:ready private_usb_provisioning=1 sensor=disabled uploads=disabled|join state=started credentials=ram_only|dns ok=[01]|clock sntp_synced=[01](?: tls_skipped=1)?|disconnect observed=1)",
        r"probe_scan (?:state=started ssids=not_logged|networks=\d+ strongest_rssi_dbm=-?\d+ strongest_channel=\d+|state=failed code=-?\d+)",
        r"probe_wifi (?:joined|rejoined)=1 dhcp=1 rssi_dbm=-?\d+ channel=\d+",
        r"probe_https attempt=\d+ status=-?\d+ trusted_tls=[01] health_ok=[01]",
        r"probe_https_error attempt=\d+ tls_code=-?\d+ duration_ms=\d+",
        r"CONNECTIVITY_PASS wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect=1 sensor=disabled uploads=disabled",
        r"NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled",
        r"wifi_saved state=(?:absent|loaded|stored|invalid|write_failed)",
        r"device_saved state=(?:absent|loaded|stored|invalid|blocked|write_failed)",
        r"wifi_config state=accepted saved=[01]",
        r"wifi_connect state=started attempt=\d+ timeout_ms=30000",
        r"wifi_connect state=waiting wait_ms=\d+",
        r"wifi_connect state=joined attempt=\d+",
        r"wifi_link state=lost acquisition=invalidated",
        r"device_network state=lost credential=ram_retained pending=[01]",
        r"device_retry stage=(?:heartbeat|poll) status=-?\d+ number=[1-3] wait_ms=(?:2000|4000|8000) acquisition=invalidated",
        r"device_recovered stage=(?:heartbeat|poll) retries=[1-3] acquisition=requires_fresh_session",
        r"CONNECTIVITY_FAIL stage=[a-z_]+ sensor=disabled uploads=disabled",
        r"device_ready credential_relay=ram_only sensor=disabled uploads=(?:disabled|mock_only)",
        r"device_auth_negative status=401 rejected=1",
        r"device_heartbeat number=\d+ status=200 online=1 last_seen_at=[0-9T:.+Z-]+",
        r"device_poll number=\d+ status=200 active_state=(?:IDLE|ARMED|SAMPLING) actions=disabled",
        r"DEVICE_PASS identity=kb-demo-01 heartbeats=\d+ polls=\d+ online_refresh=1 ongoing=1 uploads=(?:disabled|mock_only)",
        r"DEVICE_FAIL stage=[a-z_]+ status=-?\d+ credential=cleared uploads=(?:disabled|mock_only)",
        r"MOCK_READY source=simulator armed=1 session_id=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
        r"MOCK_PENDING measurement_id=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} session_id=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} source=simulator",
        r"MOCK_ACCEPTED http=(?:200|201) measurement_id=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} session_id=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} source=simulator",
        r"MOCK_RETRY number=[1-3] wait_ms=(?:2000|4000|8000) source=simulator",
        r"MOCK_BLOCKED reason=[a-z_]+ pending=[01]",
    )
    return text if any(re.fullmatch(pattern, text) for pattern in patterns) else None


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--save-wifi",
        action="store_true",
        help="Offer an unchecked opt-in to replace the single saved Wi-Fi network.",
    )
    mode.add_argument(
        "--device-only",
        action="store_true",
        help="Skip Wi-Fi entry; relay only the existing bearer after device_ready.",
    )
    parser.add_argument(
        "--save-device-auth",
        action="store_true",
        help="Ask for explicit consent to store the existing bearer on the ESP in NVS.",
    )
    return parser.parse_args(argv)


def confirm_device_auth_storage() -> bool:
    import tkinter as tk
    from tkinter import messagebox

    root = tk.Tk()
    root.withdraw()
    try:
        return messagebox.askyesno(
            "Store existing device auth on this ESP?",
            "The existing device bearer will be stored on this ESP in NVS. "
            "NVS storage is not verified encrypted, and USB is not encrypted. "
            "No new or rotated credential will be created. "
            "Allow private on-device storage?",
            parent=root,
            default=messagebox.NO,
        )
    finally:
        root.destroy()


def main() -> int:
    import serial
    from provision_wifi import private_window

    args = parse_args()
    from serial.tools import list_ports

    matches = [p for p in list_ports.comports() if p.device == args.port]
    if len(matches) != 1 or (
        matches[0].vid,
        matches[0].pid,
        matches[0].serial_number,
    ) != (0x303A, 0x1001, "80:B5:4E:F1:B7:30"):
        print("DEVICE_NOT_VERIFIED: attached target identity mismatch; nothing sent.")
        return 1
    if args.save_device_auth and not confirm_device_auth_storage():
        print("DEVICE_CANCELLED: device auth storage not authorized; nothing sent.")
        return 2
    wifi_packet = bytearray()
    if not args.device_only:
        print(
            "Private Wi-Fi entry opens locally; existing device bearer is relayed automatically.",
            flush=True,
        )
        wifi_packet = (
            private_window(allow_save=True) if args.save_wifi else private_window()
        )
        if wifi_packet is None:
            print("DEVICE_CANCELLED: no credentials sent.")
            return 2
    device_packet = bytearray()
    save_requested = bytes(wifi_packet[:4]) == b"KBS1"
    lines: list[str] = []
    port = serial.Serial()
    port.port = args.port
    port.baudrate = 115200
    port.timeout = 0.4
    port.dtr = False
    port.rts = False
    try:
        port.open()
        if not args.device_only:
            port.write(b"WIFI_SETUP\n")
            port.flush()
        deadline = time.monotonic() + 240
        wifi_sent = False
        wifi_confirmed = args.device_only
        network_confirmed = False
        online_heartbeats = 0
        device_sent = False
        device_stored = False
        while time.monotonic() < deadline:
            line = safe_line(port.readline())
            if line is None:
                continue
            print(line, flush=True)
            lines.append(line)
            if args.save_device_auth and device_sent:
                if line == "device_saved state=stored":
                    device_stored = True
                elif line in (
                    "device_saved state=invalid",
                    "device_saved state=blocked",
                    "device_saved state=write_failed",
                ):
                    print(
                        "DEVICE_NOT_VERIFIED: device auth save failed; no retry or reset."
                    )
                    return 1
            if wifi_sent and line == "wifi_saved state=write_failed":
                print(
                    "DEVICE_NOT_VERIFIED: saved Wi-Fi write failed; no bearer forwarded."
                )
                return 1
            if wifi_sent and line.startswith("wifi_config state=accepted saved="):
                wifi_confirmed = not save_requested or line.endswith("saved=1")
                if not wifi_confirmed:
                    print(
                        "DEVICE_NOT_VERIFIED: requested Wi-Fi save not confirmed; no bearer forwarded."
                    )
                    return 1
            if wifi_confirmed and line.startswith("NETWORK_READY "):
                network_confirmed = True
            if (
                wifi_sent
                and wifi_confirmed
                and network_confirmed
                and (not args.save_device_auth or (device_sent and device_stored))
                and line.startswith("device_heartbeat ")
            ):
                online_heartbeats += 1
                if online_heartbeats >= 3:
                    return 0
            if (
                line.startswith("probe_ready ")
                and not wifi_sent
                and not args.device_only
            ):
                port.write(wifi_packet)
                port.flush()
                wifi_packet[:] = b"\0" * len(wifi_packet)
                wifi_sent = True
            elif (
                line.startswith("device_ready ") and not device_sent and wifi_confirmed
            ):
                device_packet = relay_frame()
                if args.save_device_auth:
                    device_packet[:4] = b"KBA1"
                port.write(device_packet)
                port.flush()
                device_packet[:] = b"\0" * len(device_packet)
                device_sent = True
            elif (
                line.startswith("DEVICE_PASS ")
                and device_sent
                and (not args.save_device_auth or device_stored)
            ):
                return 0
            elif line.startswith(("CONNECTIVITY_FAIL ", "DEVICE_FAIL ")):
                return 1
        print("DEVICE_NOT_VERIFIED: bounded wait expired; no auth/TLS bypass.")
        return 1
    except (OSError, ValueError, subprocess.SubprocessError, serial.SerialException):
        print("DEVICE_NOT_VERIFIED: private relay/USB unavailable; no values logged.")
        return 1
    finally:
        wifi_packet[:] = b"\0" * len(wifi_packet)
        device_packet[:] = b"\0" * len(device_packet)
        port.close()
        log = Path(__file__).parents[1] / "build" / "device-connectivity.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
