"""Operator-only private SSH -> RAM -> local USB device credential relay.

Uses the existing authorized demo device; does not provision/rotate credentials,
read OS Wi-Fi profiles, print credentials or write them to a local file.
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
        r"probe_transport stage=(?:HTTPS|TCP) attempt=\d+ phase=(?:BEGIN|END) monotonic_ms=\d+ utc_s=\d+ status=-?\d+ duration_ms=\d+",
        r"CONNECTIVITY_PASS wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect=1 sensor=disabled uploads=disabled",
        r"CONNECTIVITY_FAIL stage=[a-z_]+ sensor=disabled uploads=disabled",
        r"device_ready credential_relay=ram_only sensor=disabled uploads=disabled",
        r"device_auth_negative status=401 rejected=1",
        r"device_heartbeat number=\d+ status=200 online=1 last_seen_at=[0-9T:.+Z-]+",
        r"device_poll number=\d+ status=200 active_state=(?:IDLE|ARMED|SAMPLING) actions=disabled",
        r"DEVICE_PASS identity=kb-demo-01 heartbeats=\d+ polls=\d+ online_refresh=1 ongoing=1 uploads=disabled",
        r"DEVICE_FAIL stage=[a-z_]+ status=-?\d+ credential=cleared uploads=disabled",
    )
    return text if any(re.fullmatch(pattern, text) for pattern in patterns) else None


def main() -> int:
    import serial
    from provision_wifi import private_window

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()
    from serial.tools import list_ports

    matches = [p for p in list_ports.comports() if p.device == args.port]
    if len(matches) != 1 or (
        matches[0].vid,
        matches[0].pid,
        matches[0].serial_number,
    ) != (0x303A, 0x1001, "80:B5:4E:F1:B7:30"):
        print("DEVICE_NOT_VERIFIED: attached target identity mismatch; nothing sent.")
        return 1
    print(
        "Private Wi-Fi entry opens locally; existing device bearer is relayed automatically.",
        flush=True,
    )
    wifi_packet = private_window()
    if wifi_packet is None:
        print("DEVICE_CANCELLED: no credentials sent.")
        return 2
    device_packet = bytearray()
    lines: list[str] = []
    port = serial.Serial()
    port.port = args.port
    port.baudrate = 115200
    port.timeout = 0.4
    port.dtr = False
    port.rts = False
    try:
        # Verify availability/format/hash privately before touching the board.
        device_packet = relay_frame()
        port.open()
        deadline = time.monotonic() + 240
        wifi_sent = False
        device_sent = False
        while time.monotonic() < deadline:
            line = safe_line(port.readline())
            if line is None:
                continue
            print(line, flush=True)
            lines.append(line)
            if line.startswith("probe_ready ") and not wifi_sent:
                port.write(wifi_packet)
                port.flush()
                wifi_packet[:] = b"\0" * len(wifi_packet)
                wifi_sent = True
            elif line.startswith("device_ready ") and not device_sent:
                port.write(device_packet)
                port.flush()
                device_packet[:] = b"\0" * len(device_packet)
                device_sent = True
            elif line.startswith("DEVICE_PASS "):
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
