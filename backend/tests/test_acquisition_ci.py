"""Guard the narrow native acquisition CI, not a native build substitute."""

from pathlib import Path


def test_acquisition_ci_uses_native_public_runner_and_unsigned_build():
    root = Path(__file__).resolve().parents[2]
    workflow = (root / ".github/workflows/ios-acquisition.yml").read_text()
    assert "runs-on: macos-26" in workflow
    assert "contents: read" in workflow
    assert "persist-credentials: false" in workflow
    assert "AcquisitionChecks.swift" in workflow
    assert "DeviceSessionChecks.swift" in workflow
    assert "xcodebuild" in workflow and "CODE_SIGNING_ALLOWED=NO" in workflow
    assert "secrets." not in workflow
