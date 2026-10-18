"""Synthetic host-only operator tests: no pyserial, USB, API, or credentials."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import send_mock

# Synthetic fixtures, never real user/session identifiers.
MEASUREMENT = "11111111-1111-4111-8111-111111111111"
SESSION = "22222222-2222-4222-8222-222222222222"
OTHER = "33333333-3333-4333-8333-333333333333"
READY = f"MOCK_READY source=simulator armed=1 session_id={SESSION}"
COMMAND = f"MOCK {SESSION}\n".encode("ascii")
PENDING = (
    f"MOCK_PENDING measurement_id={MEASUREMENT} session_id={SESSION} source=simulator"
)
HEARTBEAT = (
    "device_heartbeat number=1 status=200 online=1 last_seen_at=2026-10-18T12:00:00Z"
)


def accepted(status=201, measurement=MEASUREMENT, session=SESSION):
    return (
        f"MOCK_ACCEPTED http={status} measurement_id={measurement} "
        f"session_id={session} source=simulator"
    )


def frames(*lines):
    return ("\n".join(lines) + "\n").encode("ascii")


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class FakeSerial:
    def __init__(self, clock, incoming, stale=b"", short_write=False):
        self.clock = clock
        self.port = None
        self.baudrate = None
        self.dtr = None
        self.rts = None
        self.timeout = 0.25
        self.write_timeout = None
        self.incoming = bytearray(incoming)
        self.stale = bytearray(stale)
        self.short_write = short_write
        self.writes = []
        self.flushes = 0
        self.closed = False
        self.opened = False
        self.config = None
        self.cleared = False

    def open(self):
        self.config = (self.port, self.baudrate, self.dtr, self.rts, self.timeout)
        self.opened = True

    def reset_input_buffer(self):
        self.stale.clear()
        self.cleared = True

    def read(self, size):
        assert size == 1
        self.clock.now += 0.001 if self.incoming else self.timeout
        if self.incoming:
            return bytes([self.incoming.pop(0)])
        return b""

    def write(self, data):
        self.writes.append(data)
        return 1 if self.short_write else len(data)

    def flush(self):
        self.flushes += 1

    def close(self):
        self.closed = True


def target(**overrides):
    values = {
        "device": "COM3",
        "vid": 0x303A,
        "pid": 0x1001,
        "serial_number": "80:B5:4E:F1:B7:30",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


class MockOperatorTests(unittest.TestCase):
    def run_case(self, incoming=b"", *, ports=None, stale=b"", short_write=False):
        clock = Clock()
        serial = FakeSerial(clock, incoming, stale, short_write)
        factory = Mock(return_value=serial)
        output = []
        code = send_mock.run_operator(
            "COM3",
            [target()] if ports is None else ports,
            factory,
            clock=clock,
            emit=output.append,
        )
        return SimpleNamespace(
            code=code, serial=serial, clock=clock, output=output, factory=factory
        )

    def assert_failure(self, result, writes):
        self.assertNotEqual(result.code, 0)
        self.assertEqual(result.serial.writes, writes)
        self.assertIn("No automatic resend, rearm, or reset", result.output[-1])
        self.assertIn("pending transaction may remain", result.output[-1])

    def test_no_mock_without_exact_ready(self):
        result = self.run_case(
            frames(
                "MOCK_READY source=simulator armed=0", PENDING, accepted(), HEARTBEAT
            )
        )
        self.assert_failure(result, [])
        self.assertLessEqual(result.clock.now, 20.25)

    def test_stale_input_discarded(self):
        result = self.run_case(stale=frames(READY, PENDING, accepted()))
        self.assert_failure(result, [])
        self.assertTrue(result.serial.cleared)

    def test_one_write_interleaved_duplicate_ready(self):
        result = self.run_case(
            frames(
                READY, HEARTBEAT, READY, PENDING, HEARTBEAT, READY, PENDING, accepted()
            )
        )
        self.assertEqual(result.code, 0)
        self.assertEqual(result.serial.writes, [COMMAND])
        self.assertEqual(result.serial.flushes, 1)
        self.assertTrue(result.serial.closed)
        self.assertEqual(result.serial.config, ("COM3", 115200, False, False, 0.25))

    def test_matching_ack_200_and_201(self):
        for status in (200, 201):
            with self.subTest(status=status):
                result = self.run_case(frames(READY, PENDING, accepted(status)))
                self.assertEqual(result.code, 0)
                self.assertEqual(result.serial.writes, [COMMAND])

    def test_old_ack_without_post_send_pending_never_succeeds(self):
        result = self.run_case(frames(PENDING, accepted(), READY, accepted()))
        self.assert_failure(result, [COMMAND])

    def test_wrong_ack_ids_or_http_status_never_succeed(self):
        for ack in (
            accepted(measurement=OTHER),
            accepted(session=OTHER),
            accepted(202),
        ):
            with self.subTest(ack=ack):
                result = self.run_case(frames(READY, PENDING, ack))
                self.assert_failure(result, [COMMAND])

    def test_wrong_ack_then_matching_ack(self):
        result = self.run_case(
            frames(READY, PENDING, accepted(measurement=OTHER), accepted())
        )
        self.assertEqual(result.code, 0)
        self.assertEqual(result.serial.writes, [COMMAND])

    def test_ack_timeout_no_future_write(self):
        result = self.run_case(frames(READY, PENDING, READY))
        self.assert_failure(result, [COMMAND])
        self.assertGreaterEqual(result.clock.now, 90)
        self.assertLess(result.clock.now, 91)
        self.assertTrue(result.serial.closed)

    def test_block_before_and_after_send(self):
        for prefix, writes in (([], []), ([READY, PENDING], [COMMAND])):
            with self.subTest(prefix=prefix):
                result = self.run_case(
                    frames(
                        *prefix, "MOCK_BLOCKED reason=session_expired pending=1", READY
                    )
                )
                self.assert_failure(result, writes)

    def test_target_gate_before_serial_factory(self):
        for ports in (
            [],
            [target(vid=0x1234)],
            [target(pid=0x1002)],
            [target(serial_number="not-the-target")],
            [target(device="COM4")],
            [target(), target()],
        ):
            with self.subTest(ports=ports):
                result = self.run_case(frames(READY), ports=ports)
                self.assert_failure(result, [])
                result.factory.assert_not_called()
                self.assertFalse(result.serial.opened)

    def test_arbitrary_echo_and_malformed_frames_not_logged(self):
        noise = [
            '{"body":"synthetic_private_marker"}',
            "Authorization: Bearer synthetic_private_marker",
            "MOCK_BLOCKED reason=synthetic_private_marker pending=1 extra=body",
            " " + READY,
            "x" * 300 + READY,
            "MOCK_READY source=simulator armed=1 extra=body",
        ]
        result = self.run_case(frames(*noise, READY, PENDING, accepted()))
        self.assertEqual(result.code, 0)
        self.assertEqual(result.output, [READY, PENDING, accepted()])

    def test_partial_frame_cannot_trigger_write(self):
        result = self.run_case(READY.encode("ascii"))
        self.assert_failure(result, [])

    def test_short_write_never_retried(self):
        result = self.run_case(
            frames(READY, READY, PENDING, accepted()), short_write=True
        )
        self.assert_failure(result, [COMMAND])
        self.assertEqual(result.serial.flushes, 0)

    def test_retry_stages_are_passive(self):
        retries = [
            f"MOCK_RETRY number={number} wait_ms={wait} source=simulator"
            for number, wait in ((1, 2000), (2, 4000), (3, 8000))
        ]
        result = self.run_case(frames(READY, PENDING, *retries, HEARTBEAT, accepted()))
        self.assertEqual(result.code, 0)
        self.assertEqual(result.serial.writes, [COMMAND])
        for line in retries:
            self.assertIn(line, result.output)

    def test_conflicting_pending_fails_closed(self):
        conflict = PENDING.replace(MEASUREMENT, OTHER)
        result = self.run_case(frames(READY, PENDING, conflict, accepted()))
        self.assert_failure(result, [COMMAND])


if __name__ == "__main__":
    unittest.main()
