"""Guard the narrow native acquisition CI, not a native build substitute."""

import re
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


def test_ios_project_uses_its_declared_compatible_preferred_format():
    root = Path(__file__).resolve().parents[2]
    project = (root / "ios/KickBAC.xcodeproj/project.pbxproj").read_text()
    actual = re.search(r"\bobjectVersion = (\d+);", project)
    preferred = re.search(r"\bpreferredProjectObjectVersion = (\d+);", project)
    assert actual is not None and preferred is not None
    assert actual.group(1) == preferred.group(1) == "77"
