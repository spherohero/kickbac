"""Source wiring guards for Release/local boundaries, not native UI acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "KickBAC"


class PartyTransparencyChecks(unittest.TestCase):
    def test_finger_practice_requires_explicit_interaction(self):
        home = (ROOT / "HomeView.swift").read_text()
        self.assertNotIn("onGameCheckInComplete", home)
        self.assertNotIn('Button("Demo"', home)
        self.assertNotIn('Button("Onboarding"', home)
        self.assertIn("!deviceFlow.hasActiveSession", home)
        self.assertIn("practice.save(", home)
        self.assertIn("simulated 0.00 reading", home)
        self.assertNotIn(".task { startReading()", home)

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
        self.assertIn("game.completePracticeReading(value: $0.value)", trivia)
        self.assertIn("Continue without a test", trivia)
        self.assertNotIn("saveGameResult", trivia)
        self.assertNotIn("armDevice", trivia)

    def test_live_party_uses_server_codes_without_debug_layout_entry(self):
        live = (ROOT / "PartyLiveView.swift").read_text()
        self.assertNotIn("KICK26", live)
        self.assertIn("party.joinCode", live)
        self.assertNotIn('Button("Party layout")', live)

    def test_action_errors_do_not_leak_onto_party_homepage(self):
        live = (ROOT / "PartyLiveView.swift").read_text()
        page = live.split("private var page: some View {", 1)[1].split("private var entry: some View {", 1)[0]
        self.assertNotIn("error ?? store.message", page,
                         "Closing setup must not expose its error above the Party entry card")
        self.assertNotIn('Button("Try again")', page)
        self.assertNotIn("savedParties", page, "The Party page must not show the removed Your parties section")
        room = live.split("private func room(_ party: APIParty)", 1)[1].split("private var playerName", 1)[0]
        self.assertNotIn("error ?? store.message", room,
                         "Refresh and retained request errors must not render above the party title")
        sheet = live.split("private func entrySheet", 1)[1].split("private var sheetDestination", 1)[0]
        self.assertIn("error ?? store.message", sheet,
                      "Setup failures must remain visible inside setup for exact retry")

    def test_new_party_setup_cannot_create_an_unbound_party(self):
        live = (ROOT / "PartyLiveView.swift").read_text()
        self.assertNotIn("PartyWrite.create(", live)
        self.assertIn("PartyWrite.resolve(name: input, deviceID: scannedDevice.id)", live)
        self.assertIn('linked.deviceID == id', live)

    def test_party_tag_route_cannot_fall_through_to_home_auto_arm(self):
        content = (ROOT / "ContentView.swift").read_text()
        handler = content.split(".onOpenURL { url in", 1)[1]
        party_route = handler.split("if selectedTab == .party", 1)[1].split(
            'if url.scheme?.lowercased() == "com.liam.kickbac"', 1
        )[0]
        self.assertIn("partyDeviceLink = PartyDeviceLink(deviceID: id, linkAsHost: false)", party_route)
        self.assertIn("return", party_route)
        self.assertNotIn("pendingScanDeviceID =", party_route)
        self.assertNotIn("armDevice", party_route)


if __name__ == "__main__":
    unittest.main()
