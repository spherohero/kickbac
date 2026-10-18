"""Source wiring guards for Release/local boundaries, not native UI acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "KickBAC"


class PartyTransparencyChecks(unittest.TestCase):
    def test_game_cannot_autorun_home_demo(self):
        home = (ROOT / "HomeView.swift").read_text()
        self.assertNotIn("onGameCheckInComplete", home)
        self.assertIn("guard !isGameCheckIn, !phase.isRunning", home)
        # The sole call is the labeled Home Debug button, never a game task.
        self.assertEqual(home.count("action: startReading"), 1)
        self.assertNotIn("{ startReading() }", home)

    def test_real_readiness_requires_the_exact_completed_session(self):
        trivia = (ROOT / "TriviaView.swift").read_text()
        self.assertNotIn("DeviceSessionStore()", trivia)
        for guard in ["test.id == checkInSessionID", "test.userID == session.profileOwner",
                      "test.deviceID == checkInDeviceID", "test.status == .complete",
                      "measurement.hasValidAcquisition", "measurement.sessionID == test.id"]:
            self.assertIn(guard, trivia)
        self.assertIn("game.completePreviewBreath(bac: measurement.bacReading?.value)", trivia)

    def test_practice_does_not_arm_a_device_or_upload_scores(self):
        trivia = (ROOT / "TriviaView.swift").read_text()
        self.assertIn("onStartCheckIn == nil", trivia)
        self.assertIn("Continue without a test", trivia)
        self.assertNotIn("saveGameResult", trivia)
        self.assertNotIn("armDevice", trivia)

    def test_live_party_uses_server_codes_and_fixture_entry_is_debug_only(self):
        live = (ROOT / "PartyLiveView.swift").read_text()
        self.assertNotIn("KICK26", live)
        self.assertIn("party.joinCode", live)
        self.assertIn('#if DEBUG\n            Button("Party layout")', live)


if __name__ == "__main__":
    unittest.main()
