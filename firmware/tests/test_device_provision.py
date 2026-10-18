"""Synthetic tests only: never accesses a real credential or board."""

import importlib.util
import io
import subprocess
import sys
import unittest
from contextlib import ExitStack, redirect_stderr, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

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
        ]:
            self.assertIsNone(self.module.safe_line(line))

    def test_exact_sanitized_device_stage_is_retained(self):
        for line in [
            "device_auth_negative status=401 rejected=1",
            "NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled",
            "device_retry stage=poll status=502 number=1 wait_ms=2000 acquisition=invalidated",
            "device_recovered stage=poll retries=1 acquisition=requires_fresh_session",
            "probe_https_error attempt=2 tls_code=-1 duration_ms=7001",
            "device_heartbeat number=1 status=200 online=1 last_seen_at=2026-10-18T00:30:01.123456+00:00",
            "device_poll number=1 status=200 active_state=IDLE actions=disabled",
            "DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=disabled",
        ]:
            self.assertEqual(self.module.safe_line(line.encode()), line)

    def test_saved_wifi_and_recovery_allowlist_is_exact(self):
        stages = [
            *(
                f"wifi_saved state={state}"
                for state in ("absent", "loaded", "stored", "invalid", "write_failed")
            ),
            "wifi_connect state=started attempt=1 timeout_ms=30000",
            "wifi_connect state=waiting wait_ms=1234",
            "wifi_connect state=joined attempt=2",
            "wifi_link state=lost acquisition=invalidated",
            "device_network state=lost credential=ram_retained pending=0",
            "device_network state=lost credential=ram_retained pending=1",
        ]
        for line in stages:
            self.assertEqual(self.module.safe_line(line.encode()), line)
            for suffix in (
                " ssid=fixture",
                " password=fixture",
                " bearer=fixture",
                " sdk_error=fixture",
            ):
                self.assertIsNone(self.module.safe_line((line + suffix).encode()))
        for line in [
            "wifi_saved state=encrypted",
            "wifi_saved state=stored password=fixture",
            "wifi_connect state=started attempt=1 timeout_ms=1",
            "wifi_connect state=joined attempt=fixture",
            "device_network state=lost credential=persisted pending=0",
            "device_network state=lost credential=ram_retained pending=2",
            "wifi_link state=lost acquisition=valid",
            "KBS1fixture-private-networkfixture-password",
            "E wifi: fixture-private-password",
        ]:
            self.assertIsNone(self.module.safe_line(line.encode()))

    def test_cli_modes_default_and_exclusion(self):
        args = self.module.parse_args(["--port", "FIXTURE"])
        self.assertFalse(args.save_wifi)
        self.assertFalse(args.device_only)
        self.assertFalse(args.save_device_auth)
        for flag in ("--save-wifi", "--device-only"):
            args = self.module.parse_args(["--port", "FIXTURE", flag])
            self.assertTrue(getattr(args, flag[2:].replace("-", "_")))
        for mode in ([], ["--device-only"], ["--save-wifi"]):
            args = self.module.parse_args(
                ["--port", "FIXTURE", "--save-device-auth", *mode]
            )
            self.assertTrue(args.save_device_auth)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.module.parse_args(
                ["--port", "FIXTURE", "--save-wifi", "--device-only"]
            )

    def run_helper(
        self, flags=(), stages=(), identity=True, cancel=False, save=False, consent=True
    ):
        """All I/O is synthetic, including serial discovery, SSH and log writes."""
        serial = MagicMock()
        serial.SerialException = type("FixtureSerialError", (Exception,), {})
        port = serial.Serial.return_value
        port.readline.side_effect = list(stages) + [b""]
        writes = []
        port.write.side_effect = lambda packet: writes.append(bytes(packet))
        target = SimpleNamespace(
            device="FIXTURE",
            vid=0x303A,
            pid=0x1001,
            serial_number="80:B5:4E:F1:B7:30" if identity else "other",
        )
        list_ports = MagicMock()
        list_ports.comports.return_value = [target]
        wifi = MagicMock()
        wifi_packet = bytearray(
            (b"KBS1" if save else b"KBW1") + b"fixture-private-wifi"
        )
        wifi.private_window.return_value = None if cancel else wifi_packet
        device_packet = bytearray(b"KBD1" + b"x" * 43)
        relay_reads = []

        def relay():
            relay_reads.append(port.readline.call_count)
            return device_packet

        output = io.StringIO()
        with ExitStack() as stack:
            confirm = stack.enter_context(
                patch.object(
                    self.module, "confirm_device_auth_storage", return_value=consent
                )
            )
            stack.enter_context(
                patch.dict(
                    sys.modules,
                    {
                        "serial": serial,
                        "serial.tools": SimpleNamespace(list_ports=list_ports),
                        "provision_wifi": wifi,
                    },
                )
            )
            stack.enter_context(
                patch.object(
                    sys, "argv", ["provision_device", "--port", "FIXTURE", *flags]
                )
            )
            stack.enter_context(
                patch.object(self.module, "relay_frame", side_effect=relay)
            )
            log_path = stack.enter_context(patch.object(self.module, "Path"))
            log = log_path.return_value.parents[1] / "build" / "device-connectivity.log"
            stack.enter_context(
                patch.object(
                    self.module.time,
                    "monotonic",
                    side_effect=[0] + [1] * len(stages) + [241],
                )
            )
            stack.enter_context(redirect_stdout(output))
            result = self.module.main()
        for call in log.write_text.call_args_list:
            self.assertNotIn("fixture-private", call.args[0])
            self.assertNotIn("x" * 43, call.args[0])
        self.assertNotIn("fixture-private", output.getvalue())
        self.assertNotIn("x" * 43, output.getvalue())
        if "--save-device-auth" not in flags:
            confirm.assert_not_called()
        return SimpleNamespace(
            result=result,
            wifi=wifi,
            port=port,
            writes=writes,
            relay_reads=relay_reads,
            wifi_packet=wifi_packet,
            device_packet=device_packet,
            output=output.getvalue(),
            confirm=confirm,
        )

    def test_device_only_waits_for_ready_and_never_sends_wifi(self):
        result = self.run_helper(
            flags=["--device-only"],
            stages=[
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                b"wifi_saved state=loaded",
                b"NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled",
                b"device_ready credential_relay=ram_only sensor=disabled uploads=disabled",
                b"device_ready credential_relay=ram_only sensor=disabled uploads=disabled",
                b"DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=disabled",
            ],
        )
        self.assertEqual(result.result, 0)
        result.wifi.private_window.assert_not_called()
        self.assertEqual(result.relay_reads, [4])
        self.assertEqual(result.writes, [b"KBD1" + b"x" * 43])
        self.assertFalse(any(result.device_packet))
        self.assertFalse(result.port.dtr)
        self.assertFalse(result.port.rts)
        result.port.close.assert_called_once()

    def test_device_only_timeout_does_not_fetch_or_prompt(self):
        result = self.run_helper(
            flags=["--device-only"],
            stages=[
                b"wifi_saved state=absent",
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
            ],
        )
        self.assertEqual(result.result, 1)
        self.assertIn("bounded wait expired", result.output)
        self.assertEqual(result.writes, [])
        self.assertEqual(result.relay_reads, [])
        result.wifi.private_window.assert_not_called()

    def test_default_and_save_modes_only_offer_save_when_requested(self):
        for flags in ([], ["--save-wifi"]):
            result = self.run_helper(
                flags=flags,
                stages=[
                    b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                    b"wifi_config state=accepted saved=0",
                    b"device_ready credential_relay=ram_only sensor=disabled uploads=mock_only",
                    b"DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=mock_only",
                ],
            )
            self.assertEqual(result.result, 0)
            if flags:
                result.wifi.private_window.assert_called_once_with(allow_save=True)
            else:
                result.wifi.private_window.assert_called_once_with()
            self.assertEqual(result.writes[0], b"WIFI_SETUP\n")
            self.assertEqual(result.writes[1], b"KBW1fixture-private-wifi")
            self.assertEqual(len(result.writes), 3)
            self.assertFalse(any(result.wifi_packet))
            self.assertFalse(any(result.device_packet))

    def test_saved_replacement_requires_ack_before_bearer(self):
        ready = (
            b"device_ready credential_relay=ram_only sensor=disabled uploads=mock_only"
        )
        result = self.run_helper(
            flags=["--save-wifi"],
            save=True,
            stages=[
                ready,
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                ready,
                b"wifi_saved state=stored",
                b"wifi_config state=accepted saved=1",
                ready,
                b"DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=mock_only",
            ],
        )
        self.assertEqual(result.result, 0)
        self.assertEqual(result.relay_reads, [6])
        self.assertEqual(result.writes[0], b"WIFI_SETUP\n")
        self.assertEqual(result.writes[1], b"KBS1fixture-private-wifi")
        failed = self.run_helper(
            flags=["--save-wifi"],
            save=True,
            stages=[
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                b"wifi_saved state=write_failed",
                ready,
            ],
        )
        self.assertEqual(failed.result, 1)
        self.assertEqual(failed.relay_reads, [])

    def test_online_replacement_with_ram_bearer_never_relays_another(self):
        result = self.run_helper(
            flags=["--save-wifi"],
            save=True,
            stages=[
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                b"wifi_saved state=stored",
                b"wifi_config state=accepted saved=1",
                b"NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled",
                b"device_heartbeat number=10 status=200 online=1 last_seen_at=2026-10-18T12:00:01Z",
                b"device_heartbeat number=11 status=200 online=1 last_seen_at=2026-10-18T12:00:11Z",
                b"device_heartbeat number=12 status=200 online=1 last_seen_at=2026-10-18T12:00:21Z",
            ],
        )
        self.assertEqual(result.result, 0)
        self.assertEqual(result.relay_reads, [])
        self.assertEqual(result.writes, [b"WIFI_SETUP\n", b"KBS1fixture-private-wifi"])

    def test_identity_failure_precedes_private_entry_relay_and_serial(self):
        for flags in ([], ["--save-wifi"], ["--device-only"], ["--save-device-auth"]):
            result = self.run_helper(flags=flags, identity=False)
            self.assertEqual(result.result, 1)
            result.wifi.private_window.assert_not_called()
            result.confirm.assert_not_called()
            result.port.open.assert_not_called()
            self.assertEqual(result.relay_reads, [])
            self.assertEqual(result.writes, [])

    def test_cancel_does_not_touch_serial_or_relay(self):
        result = self.run_helper(flags=["--save-wifi"], cancel=True)
        self.assertEqual(result.result, 2)
        result.port.open.assert_not_called()
        self.assertEqual(result.relay_reads, [])

    def test_consent_is_local_default_no_and_warns_about_storage_and_usb(self):
        tk = MagicMock()
        tk.messagebox.NO = "no"
        tk.messagebox.askyesno.return_value = False
        with patch.dict(sys.modules, {"tkinter": tk}):
            self.assertFalse(self.module.confirm_device_auth_storage())
        args, kwargs = tk.messagebox.askyesno.call_args
        self.assertEqual(kwargs["default"], "no")
        self.assertEqual(kwargs["parent"], tk.Tk.return_value)
        for warning in (
            "existing device bearer",
            "NVS",
            "not verified encrypted",
            "USB is not encrypted",
            "No new or rotated credential",
        ):
            self.assertIn(warning, args[1])
        tk.Tk.return_value.withdraw.assert_called_once()
        tk.Tk.return_value.destroy.assert_called_once()

    def test_device_auth_consent_cancel_precedes_wifi_serial_and_relay(self):
        for mode in ([], ["--device-only"], ["--save-wifi"]):
            result = self.run_helper(flags=["--save-device-auth", *mode], consent=False)
            self.assertEqual(result.result, 2)
            result.confirm.assert_called_once_with()
            result.wifi.private_window.assert_not_called()
            result.port.open.assert_not_called()
            self.assertEqual(result.writes, [])
            self.assertEqual(result.relay_reads, [])

    def test_device_saved_allowlist_rejects_secrets_sdk_and_unknown_fields(self):
        for state in (
            "absent",
            "loaded",
            "stored",
            "invalid",
            "blocked",
            "write_failed",
        ):
            line = f"device_saved state={state}"
            self.assertEqual(self.module.safe_line(line.encode()), line)
            for suffix in (
                " bearer=" + "x" * 43,
                " password=fixture-private",
                " sdk_error=fixture-private",
                " reason=other",
            ):
                self.assertIsNone(self.module.safe_line((line + suffix).encode()))
        for line in (
            b"device_saved state=encrypted",
            b"E nvs: fixture-private",
            b"KBA1" + b"x" * 43,
        ):
            self.assertIsNone(self.module.safe_line(line))

    def test_device_auth_save_sends_existing_token_once_and_requires_later_ack(self):
        ready = (
            b"device_ready credential_relay=ram_only sensor=disabled uploads=disabled"
        )
        passed = b"DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=7 online_refresh=1 ongoing=1 uploads=disabled"
        for states, expected in (
            ([ready, b"device_saved state=stored", ready, passed], 0),
            ([ready, passed], 1),
            ([b"device_saved state=stored", ready, passed], 1),
            ([ready, b"device_saved state=loaded", passed], 1),
            ([ready, b"device_saved state=stored bearer=" + b"x" * 43, passed], 1),
            ([ready, b"E nvs: fixture-private", passed], 1),
        ):
            with self.subTest(states=states):
                result = self.run_helper(
                    flags=["--save-device-auth", "--device-only"], stages=states
                )
                self.assertEqual(result.result, expected)
                result.confirm.assert_called_once_with()
                result.wifi.private_window.assert_not_called()
                self.assertEqual(result.writes, [b"KBA1" + b"x" * 43])
                self.assertEqual(len(result.relay_reads), 1)
                self.assertFalse(any(result.device_packet))
                self.assertFalse(result.port.dtr)
                self.assertFalse(result.port.rts)

    def test_device_auth_save_failures_stop_without_retry_or_reset(self):
        ready = (
            b"device_ready credential_relay=ram_only sensor=disabled uploads=disabled"
        )
        for state in ("invalid", "blocked", "write_failed"):
            result = self.run_helper(
                flags=["--save-device-auth", "--device-only"],
                stages=[ready, f"device_saved state={state}".encode(), ready],
            )
            self.assertEqual(result.result, 1)
            self.assertEqual(result.port.readline.call_count, 2)
            self.assertEqual(result.writes, [b"KBA1" + b"x" * 43])
            self.assertEqual(len(result.relay_reads), 1)
            self.assertFalse(result.port.dtr)
            self.assertFalse(result.port.rts)

    def test_autoboot_heartbeats_cannot_satisfy_device_auth_save_without_frame_ack(
        self,
    ):
        setup = [
            b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
            b"wifi_config state=accepted saved=1",
            b"NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled",
        ]
        heartbeats = [
            f"device_heartbeat number={n} status=200 online=1 last_seen_at=2026-10-18T12:00:01Z".encode()
            for n in (10, 11, 12)
        ]
        ready = (
            b"device_ready credential_relay=ram_only sensor=disabled uploads=disabled"
        )
        for extra, expected in (
            ([], 1),
            ([b"device_saved state=stored"], 1),
            ([ready], 1),
            ([b"device_saved state=stored", ready], 1),
            ([ready, b"device_saved state=stored"], 0),
        ):
            result = self.run_helper(
                flags=["--save-wifi", "--save-device-auth"],
                save=True,
                stages=setup + extra + heartbeats,
            )
            self.assertEqual(result.result, expected)
            self.assertEqual(
                result.writes[:2], [b"WIFI_SETUP\n", b"KBS1fixture-private-wifi"]
            )
            self.assertEqual(
                result.writes[2:], [b"KBA1" + b"x" * 43] if ready in extra else []
            )

    def test_network_failure_before_ready_does_not_relay(self):
        result = self.run_helper(
            flags=["--device-only"],
            stages=[
                b"CONNECTIVITY_FAIL stage=clock sensor=disabled uploads=disabled",
            ],
        )
        self.assertEqual(result.result, 1)
        self.assertEqual(result.relay_reads, [])
        self.assertEqual(result.writes, [])


if __name__ == "__main__":
    unittest.main()
