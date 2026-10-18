"""One-shot USB MOCK operator; the user must already have armed via the app.

From the repository root (PlatformIO supplies pyserial):
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/send_mock.py --port COM3

No API client, provisioning, arming, reset, or automatic resend is performed.
"""

import argparse
import re
import time
from contextlib import suppress
from pathlib import Path

from provision_device import safe_line

TARGET = (0x303A, 0x1001, "80:B5:4E:F1:B7:30")
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
READY = re.compile(rf"MOCK_READY source=simulator armed=1 session_id=({UUID})")
PENDING = re.compile(
    rf"MOCK_PENDING measurement_id=({UUID}) session_id=({UUID}) source=simulator"
)
ACCEPTED = re.compile(
    rf"MOCK_ACCEPTED http=(?:200|201) measurement_id=({UUID}) "
    rf"session_id=({UUID}) source=simulator"
)
BLOCKED = re.compile(r"MOCK_BLOCKED reason=[a-z_]+ pending=[01]")
MAX_LINE = 256
FAILURE = (
    "No automatic resend, rearm, or reset; the original pending transaction may remain."
)


def run_operator(port_name, ports, serial_factory, *, clock=time.monotonic, emit=print):
    """Host-testable operator; injected serial factory is never called for a bad target.

    emit receives only shared-allowlisted complete lines or fixed local diagnostics.
    Serial input is byte-framed and bounded, so an oversized/truncated line cannot
    be reinterpreted as a valid suffix. No serial exceptions/values are echoed.
    """
    matches = [p for p in ports if p.device == port_name]
    if (
        len(matches) != 1
        or (
            matches[0].vid,
            matches[0].pid,
            matches[0].serial_number,
        )
        != TARGET
    ):
        emit(
            "MOCK_OPERATOR target identity mismatch; nothing opened or sent. " + FAILURE
        )
        return 1

    port = None
    try:
        port = serial_factory()
        port.port = port_name
        port.baudrate = 115200
        port.timeout = 0.25
        port.write_timeout = 1.0
        # Set only before open; never toggle control lines or explicitly reset.
        port.dtr = False
        port.rts = False
        port.open()
        port.reset_input_buffer()
        deadline = clock() + 20.0
        sent = False
        requested_session = None
        pending = None
        buffer = bytearray()
        discard = False
        while clock() < deadline:
            port.timeout = min(0.25, max(0.001, deadline - clock()))
            raw = port.read(1)
            if clock() >= deadline:
                break
            if not raw:
                continue
            if raw != b"\n":
                if len(buffer) < MAX_LINE and not discard:
                    buffer.extend(raw)
                else:
                    buffer.clear()
                    discard = True
                continue
            if discard:
                buffer.clear()
                discard = False
                continue
            complete = bytes(buffer).removesuffix(b"\r")
            buffer.clear()
            line = safe_line(complete)
            # safe_line strips whitespace; require the original frame to be exact.
            if line is None or complete != line.encode("ascii"):
                continue
            emit(line)
            if not sent:
                ready = READY.fullmatch(line)
                if ready:
                    # Mark before write: even short writes/errors never cause retries.
                    sent = True
                    requested_session = ready.group(1)
                    command = f"MOCK {requested_session}\n".encode("ascii")
                    if port.write(command) != len(command):
                        emit("MOCK_OPERATOR incomplete write. " + FAILURE)
                        return 1
                    port.flush()
                    deadline = clock() + 90.0
                elif BLOCKED.fullmatch(line):
                    emit("MOCK_OPERATOR device blocked; nothing sent. " + FAILURE)
                    return 1
                continue
            if BLOCKED.fullmatch(line):
                emit("MOCK_OPERATOR device blocked. " + FAILURE)
                return 1
            match = PENDING.fullmatch(line)
            if match:
                if match.group(2) != requested_session:
                    emit("MOCK_OPERATOR wrong pending session. " + FAILURE)
                    return 1
                if pending is not None and pending != match.groups():
                    emit("MOCK_OPERATOR conflicting transaction IDs. " + FAILURE)
                    return 1
                pending = match.groups()
            match = ACCEPTED.fullmatch(line)
            if match and pending is not None and match.groups() == pending:
                return 0
        stage = "acknowledgment" if sent else "fresh ready"
        emit("MOCK_OPERATOR timed out waiting for " + stage + ". " + FAILURE)
        return 1
    except (OSError, ValueError, ImportError):
        # Serial drivers can include private serial data in exception messages.
        emit("MOCK_OPERATOR USB/log operation failed; no values logged. " + FAILURE)
        return 1
    finally:
        if port is not None:
            with suppress(OSError, ValueError):
                port.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()
    try:
        import serial
        from serial.tools import list_ports

        log = Path(__file__).parents[1] / "build" / "mock-operator.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("w", encoding="ascii") as stream:

            def emit(line):
                print(line, flush=True)
                # Local diagnostics are fixed text, but the log stores stages only.
                if safe_line(line.encode("ascii")) == line:
                    stream.write(line + "\n")
                    stream.flush()

            return run_operator(
                args.port, list_ports.comports(), serial.Serial, emit=emit
            )
    except (OSError, ValueError, ImportError):
        print(
            "MOCK_OPERATOR dependencies, log, or USB unavailable. " + FAILURE,
            flush=True,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
