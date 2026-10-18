"""Synthetic tests only: never accesses a real credential or board."""

import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "provision_device", Path(__file__).parents[1] / "tools" / "provision_device.py"
)


class DeviceProvisionTests(unittest.TestCase):
    def setUp(self):
        assert SPEC is not None and SPEC.loader is not None
        self.module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.module)

    def test_frame_requires_exact_current_operator_token(self):
        packet = self.module.build_device_frame(b"x" * 43)
        self.assertIsInstance(packet, bytearray)
        self.assertEqual(packet, b"KBD1" + b"x" * 43)
        for value in [
            b"",
            b"x" * 42,
            b"x" * 44,
            b"x" * 42 + b"\n",
            b"x" * 42 + b"!",
            b"\0" * 43,
        ]:
            with self.assertRaises(ValueError):
                self.module.build_device_frame(value)

    def test_relay_captures_stdout_instead_of_printing_or_using_shell(self):
        completed = subprocess.CompletedProcess([], 0, stdout=b"x" * 43, stderr=b"")
        with patch.object(self.module.subprocess, "run", return_value=completed) as run:
            packet = self.module.relay_frame()
        self.assertEqual(packet, b"KBD1" + b"x" * 43)
        args, kwargs = run.call_args
        self.assertIsInstance(args[0], list)
        self.assertIn("StrictHostKeyChecking=yes", args[0])
        self.assertIn("BatchMode=yes", args[0])
        self.assertTrue(kwargs["capture_output"])
        self.assertFalse(kwargs.get("shell", False))
        self.assertLessEqual(kwargs["timeout"], 30)

    def test_failed_or_banner_polluted_relay_rejects_without_credential_text(self):
        for completed in [
            subprocess.CompletedProcess(
                [], 1, stdout=b"", stderr=b"fixture-private-error"
            ),
            subprocess.CompletedProcess(
                [], 0, stdout=b"banner\n" + b"x" * 43, stderr=b""
            ),
        ]:
            with (
                patch.object(self.module.subprocess, "run", return_value=completed),
                self.assertRaises(ValueError),
            ):
                self.module.relay_frame()

    def test_output_allowlist_never_logs_echoed_tokens_or_arbitrary_fields(self):
        for line in [
            b"KBD1" + b"x" * 43,
            b"Authorization: Bearer " + b"x" * 43,
            b"device_ready credential_relay=" + b"x" * 43,
            b"device_poll token=" + b"x" * 43,
            b"probe_wifi joined=1 ssid=fixture-private-network",
            b"probe_transport stage=TCP attempt=2 phase=END monotonic_ms=1 utc_s=0 status=0 duration_ms=7000 private=fixture",
            b"probe_transport stage=TCP attempt=2 phase=END monotonic_ms=1 utc_s=fixture-private status=0 duration_ms=7000",
        ]:
            self.assertIsNone(self.module.safe_line(line))

    def test_exact_sanitized_device_stage_is_retained(self):
        for line in [
            "device_auth_negative status=401 rejected=1",
            "probe_https_error attempt=2 tls_code=-1 duration_ms=7001",
            "probe_transport stage=HTTPS attempt=2 phase=BEGIN monotonic_ms=100 utc_s=1792300000 status=0 duration_ms=0",
            "probe_transport stage=HTTPS attempt=2 phase=END monotonic_ms=7101 utc_s=1792300007 status=-1 duration_ms=7001",
            "probe_transport stage=TCP attempt=2 phase=END monotonic_ms=14101 utc_s=1792300014 status=0 duration_ms=7000",
            "device_heartbeat number=1 status=200 online=1 last_seen_at=2026-10-18T00:30:01.123456+00:00",
            "device_poll number=1 status=200 active_state=IDLE actions=disabled",
            "DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=disabled",
        ]:
            self.assertEqual(self.module.safe_line(line.encode()), line)


if __name__ == "__main__":
    unittest.main()
