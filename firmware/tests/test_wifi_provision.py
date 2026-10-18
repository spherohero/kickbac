"""Synthetic tests only; no real Wi-Fi credentials or USB use."""

import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import ANY, MagicMock, patch

SPEC = importlib.util.spec_from_file_location(
    "provision_wifi", Path(__file__).parents[1] / "tools" / "provision_wifi.py"
)


class ProvisioningTests(unittest.TestCase):
    def setUp(self):
        assert SPEC is not None and SPEC.loader is not None
        self.module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.module)

    def test_save_changes_only_magic_and_preserves_limits(self):
        for ssid, password in [("fixture", "password"), ("é" * 16, "p" * 63)]:
            legacy = self.module.build_frame(ssid, password)
            self.assertEqual(
                legacy, self.module.build_frame(ssid, password, save=False)
            )
            saved = self.module.build_frame(ssid, password, save=True)
            self.assertEqual(saved[:4], b"KBS1")
            self.assertEqual(saved[4:], legacy[4:])
        for save in (False, True):
            for ssid, password in [
                ("é" * 17, "password"),
                ("", "password"),
                ("bad\0ssid", "password"),
                ("fixture", "short"),
                ("fixture", "p" * 64),
                ("fixture", "bad\npassword"),
                ("fixture", "é" * 8),
            ]:
                with (
                    self.subTest(save=save, ssid=ssid, password=password),
                    self.assertRaises(ValueError),
                ):
                    self.module.build_frame(ssid, password, save=save)

    def test_private_window_save_is_explicit_and_unchecked_by_default(self):
        for allow_save, checked in [(False, False), (True, False), (True, True)]:
            with self.subTest(allow_save=allow_save, checked=checked):
                tk = MagicMock()
                root = tk.Tk.return_value
                name, password = MagicMock(), MagicMock()
                name.get.return_value = "fixture"
                password.get.return_value = "password"
                tk.Entry.side_effect = [name, password]
                tk.BooleanVar.return_value.get.return_value = checked

                def button(_root, **kwargs):
                    _root.mainloop.side_effect = kwargs["command"]
                    return MagicMock()

                tk.Button.side_effect = button
                with patch.dict(
                    sys.modules, {"tkinter": tk, "tkinter.messagebox": tk.messagebox}
                ):
                    packet = self.module.private_window(allow_save=allow_save)
                self.assertEqual(
                    packet[:4], b"KBS1" if allow_save and checked else b"KBW1"
                )
                password.delete.assert_called_once_with(0, tk.END)
                tk.Entry.assert_any_call(ANY, width=35, show="*")
                if allow_save:
                    tk.BooleanVar.assert_called_once_with(master=root, value=False)
                    tk.Checkbutton.assert_called_once()
                    labels = " ".join(
                        call.kwargs.get("text", "") for call in tk.Label.call_args_list
                    )
                    self.assertIn("NVS storage not verified encrypted", labels)
                    self.assertIn("replaces single saved network", labels)
                    self.assertIn("device bearer stays RAM-only", labels)
                    root.geometry.assert_called_once_with("510x400")
                else:
                    tk.BooleanVar.assert_not_called()
                    tk.Checkbutton.assert_not_called()
                    root.geometry.assert_called_once_with("510x270")

    def test_private_window_cancel_sends_nothing(self):
        tk = MagicMock()
        with patch.dict(
            sys.modules, {"tkinter": tk, "tkinter.messagebox": tk.messagebox}
        ):
            self.assertIsNone(self.module.private_window(allow_save=True))

    def test_standalone_target_gate_and_sanitized_output(self):
        device_spec = importlib.util.spec_from_file_location(
            "provision_device",
            Path(__file__).parents[1] / "tools" / "provision_device.py",
        )
        assert device_spec is not None and device_spec.loader is not None
        device_module = importlib.util.module_from_spec(device_spec)
        device_spec.loader.exec_module(device_module)
        for identity in (False, True):
            serial = MagicMock()
            serial.SerialException = type("FixtureSerialError", (Exception,), {})
            port = serial.Serial.return_value
            list_ports = MagicMock()
            list_ports.comports.return_value = [
                SimpleNamespace(
                    device="FIXTURE",
                    vid=0x303A,
                    pid=0x1001,
                    serial_number="80:B5:4E:F1:B7:30" if identity else "other",
                )
            ]
            port.readline.side_effect = [
                b"probe_wifi joined=1 ssid=fixture-private-network",
                b"probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled",
                b"probe_https sdk_error=fixture-private-password",
                b"CONNECTIVITY_PASS wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect=1 sensor=disabled uploads=disabled",
            ]
            output = io.StringIO()
            packet = bytearray(b"KBW1fixture-private-packet")
            with (
                patch.dict(
                    sys.modules,
                    {
                        "serial": serial,
                        "serial.tools": SimpleNamespace(list_ports=list_ports),
                        "provision_device": device_module,
                    },
                ),
                patch.object(sys, "argv", ["provision_wifi", "--port", "FIXTURE"]),
                patch.object(
                    self.module, "private_window", return_value=packet
                ) as window,
                patch.object(self.module, "Path") as path,
                patch.object(self.module.time, "monotonic", return_value=0),
                redirect_stdout(output),
            ):
                result = self.module.main()
            self.assertNotIn("fixture-private", output.getvalue())
            if identity:
                self.assertEqual(result, 0)
                window.assert_called_once_with()
                port.write.assert_called_once()
                self.assertFalse(any(packet))
                self.assertFalse(port.dtr)
                self.assertFalse(port.rts)
                log_text = path.return_value.parents[
                    1
                ].__truediv__.return_value.__truediv__.return_value.write_text.call_args.args[
                    0
                ]
                self.assertNotIn("fixture-private", log_text)
                self.assertIn("CONNECTIVITY_PASS", log_text)
            else:
                self.assertEqual(result, 1)
                window.assert_not_called()
                serial.Serial.assert_not_called()

    def test_private_frame_is_exact_and_bounded(self):
        assert SPEC is not None and SPEC.loader is not None
        module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        packet = module.build_frame("fixture-network", "fixture-password")
        self.assertIsInstance(packet, bytearray)
        self.assertEqual(packet, b"KBW1\x0f\x10fixture-networkfixture-password")
        for ssid, password in [
            ("", "fixture-password"),
            ("x" * 33, "fixture-password"),
            ("fixture", "short"),
            ("fixture", "x" * 64),
            ("fixture", "bad\npassword"),
            ("bad\0ssid", "fixture-password"),
        ]:
            with self.assertRaises(ValueError):
                module.build_frame(ssid, password)
        self.assertEqual(len(module.build_frame("s" * 32, "p" * 63)), 101)


if __name__ == "__main__":
    unittest.main()
