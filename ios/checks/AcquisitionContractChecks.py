"""Cross-platform source/wire guard, NOT execution of Swift or native acceptance.
Run: python ios/checks/AcquisitionContractChecks.py
"""
import json
from pathlib import Path
import re
import unittest

IOS = Path(__file__).resolve().parents[1]
API = (IOS / 'KickBAC/KickBACAPI.swift').read_text(encoding='utf-8')


class AcquisitionContractChecks(unittest.TestCase):
    def test_nullable_manual_metadata_can_be_decoded_without_breaking_legacy(self):
        self.assertRegex(API, r'let breathDurationMS: Int\?')
        for name, wire in [('acquisitionMethod', 'acquisition_method'), ('sampleDurationMS', 'sample_duration_ms')]:
            self.assertIn(f'case {name} = "{wire}"', API)
        swift = (IOS / 'checks/AcquisitionChecks.swift').read_text(encoding='utf-8')
        self.assertIn('JSONDecoder().decode(APIMeasurement.self', swift)
        fixtures = json.loads((IOS / 'checks/fixtures/acquisition.json').read_text(encoding='utf-8'))
        self.assertIsNone(fixtures['manual']['breath_duration_ms'])
        self.assertEqual(fixtures['manual']['acquisition_method'], 'manual_timed')
        self.assertIsNone(fixtures['manual']['estimated_bac_percent'])
        self.assertNotIn('acquisition_method', fixtures['legacy'])
        self.assertIsInstance(fixtures['legacy']['breath_duration_ms'], int)


    def test_mode_aware_labels_and_bac_gate(self):
        self.assertIn('var hasValidAcquisition: Bool', API)
        self.assertIn('var isManualTimed: Bool', API)
        self.assertIn('Timed sensor sample — breath not validated', API)
        self.assertIn('Sample window', API)
        self.assertIn('guard hasValidAcquisition, !isManualTimed, !isTestReading, source == "device"', API)
        self.assertIn('var durationAccessibilityValue: String', API)
        swift = (IOS / 'checks/AcquisitionChecks.swift').read_text(encoding='utf-8')
        for token in ['hasValidAcquisition', 'durationAccessibilityValue', 'unknown', '60001', 'NSNull()']:
            self.assertIn(token, swift)


    def test_home_history_and_accessibility_use_honest_mode_labels(self):
        home = (IOS / 'KickBAC/HomeView.swift').read_text(encoding='utf-8')
        history = (IOS / 'KickBAC/ProfileHistoryView.swift').read_text(encoding='utf-8')
        self.assertIn('Text(notice)', home)
        self.assertIn('measurement.acquisitionNotice', home)
        self.assertIn('measurement.durationText', home)
        self.assertIn('measurement.durationAccessibilityValue', home)
        self.assertIn('measurement.sourceTitle', home)
        self.assertNotIn('Double(measurement.breathDurationMS)', home)
        self.assertNotIn('Recorded breath duration:', home)
        self.assertIn('reading.acquisitionNotice', history)
        self.assertIn('reading.durationText', history)
        self.assertIn('reading.sourceTitle', history)
        self.assertIn('reading.bacReading', history)
        self.assertNotIn('if let value = reading.estimatedBACPercent', history)


    def test_arming_copy_does_not_claim_measurement_or_validated_breath(self):
        home = (IOS / 'KickBAC/HomeView.swift').read_text(encoding='utf-8')
        connection = (IOS / 'KickBAC/DeviceConnectionView.swift').read_text(encoding='utf-8')
        self.assertIn('case .sampling: return "Sensor acquisition', home)
        self.assertIn('breath not validated', home)
        self.assertIn('operator', connection)
        self.assertIn('USB', connection)
        self.assertIn('kb-demo-01', connection)
        self.assertIn('Button("Arm test")', connection)
        self.assertNotIn('"The device is sampling."', connection)


    def test_invalid_acquisition_cannot_complete_an_exact_session(self):
        store = (IOS / 'KickBAC/DeviceSessionStore.swift').read_text(encoding='utf-8')
        self.assertIn('loaded.id == id, loaded.deviceID == targetID, loaded.userID == owner', store)
        self.assertIn('reading.sessionID == id, reading.deviceID == targetID', store)
        self.assertIn('reading.hasValidAcquisition', store)
        self.assertIn('loaded.status == .complete', store)
        self.assertIn('func retryPolling() { pollID = UUID() }', store)
        checks = (IOS / 'checks/DeviceSessionChecks.swift').read_text(encoding='utf-8')
        self.assertIn('Invalid acquisition produced a completion', checks)
        self.assertIn('manual_timed', checks)


if __name__ == '__main__':
    unittest.main()
