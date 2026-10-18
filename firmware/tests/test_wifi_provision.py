"""Synthetic tests only; no real Wi-Fi credentials or USB use."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "provision_wifi", Path(__file__).parents[1] / "tools" / "provision_wifi.py"
)


class ProvisioningTests(unittest.TestCase):
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
