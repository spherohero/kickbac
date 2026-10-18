"""Check user-facing app naming and shared launch/Welcome asset wiring."""
import json
from pathlib import Path
import plistlib
import re
import struct

ios = Path(__file__).resolve().parents[1]
info = plistlib.loads((ios / "Config/Info.plist").read_bytes())
assert info["CFBundleDisplayName"] == "KickBAC"
asset = info["UILaunchScreen"]["UIImageName"]
assert asset == "KickBACWordmark", "Launch screen must reference the updated shared wordmark"
for screen in ("WelcomeView.swift", "SplashScreen.swift"):
    source = (ios / "KickBAC" / screen).read_text()
    assert f'Image("{asset}")' in source, f"{screen} uses a different wordmark"

for path in (ios / "KickBAC").rglob("*.swift"):
    for literal in re.findall(r'"(?:[^"\\]|\\.)*"', path.read_text()):
        assert "kickBAC" not in literal and "Kick back" not in literal, f"Old branding in {path.name}: {literal}"
assert "kickBAC" not in info["NSCameraUsageDescription"]

image_set = ios / "KickBAC/Assets.xcassets" / f"{asset}.imageset"
images = json.loads((image_set / "Contents.json").read_text())["images"]
assert {image["scale"] for image in images} == {"1x", "2x", "3x"}
for image in images:
    data = (image_set / image["filename"]).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "Launch image must be PNG"
    scale = int(image["scale"][0])
    assert struct.unpack(">II", data[16:24]) == (300 * scale, 49 * scale)
assert not (ios / "KickBAC/Assets.xcassets/SplashWordmark.imageset").exists()
print("Branding checks passed: KickBAC copy, shared launch/Welcome wordmark, and 1x/2x/3x PNG assets. Rendering not verified.")
