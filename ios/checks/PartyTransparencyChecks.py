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

    def test_local_progress_is_honest_and_scores_stay_local(self):
        trivia = (ROOT / "TriviaView.swift").read_text()
        podium = (ROOT / "TriviaPodium.swift").read_text()
        self.assertIn("Local Trivia · unsaved scores and standings · this iPhone only", trivia)
        self.assertIn("Continue without a test", trivia)
        self.assertIn("No device or breath test is connected", trivia)
        self.assertIn("Local standings · scores aren't saved or shared", podium)
        self.assertNotIn("saveGameResult", trivia)
        self.assertNotIn("armDevice", trivia)

    def test_live_party_uses_server_codes_and_debug_fixture_is_disclosed(self):
        live = (ROOT / "PartyLiveView.swift").read_text()
        preview = (ROOT / "PartyView.swift").read_text()
        self.assertNotIn("KICK26", live)
        self.assertIn("party.joinCode", live)
        self.assertIn('#if DEBUG\n                    Button("Local party preview · unsaved")', live)
        self.assertIn("membership and code are not saved or shared", preview)
        self.assertIn("KICK26 cannot invite another phone", preview)


if __name__ == "__main__":
    unittest.main()
