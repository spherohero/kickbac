import Foundation

@main
struct AcquisitionChecks {
    static func main() throws {
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ios/checks/fixtures/acquisition.json"
        let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: [String: Any]]
        func decode(_ wire: [String: Any]) throws -> APIMeasurement {
            try JSONDecoder().decode(APIMeasurement.self, from: JSONSerialization.data(withJSONObject: wire))
        }
        let manual = try decode(fixtures["manual"]!)
        let legacy = try decode(fixtures["legacy"]!)
        precondition(manual.breathDurationMS == nil && manual.acquisitionMethod == "manual_timed" && manual.sampleDurationMS == 5000)
        precondition(legacy.breathDurationMS == 2500 && legacy.acquisitionMethod == nil && legacy.sampleDurationMS == nil)
        precondition(manual.estimatedBACPercent == nil && legacy.estimatedBACPercent == nil)
        precondition(manual.hasValidAcquisition && legacy.hasValidAcquisition)
        precondition(manual.isManualTimed && !legacy.isManualTimed)
        precondition(manual.durationText == "Sample window: 5.00 s")
        precondition(manual.acquisitionNotice == "Timed sensor sample — breath not validated")
        precondition(manual.durationAccessibilityValue.contains("breath not validated"))
        precondition(legacy.sourceTitle.contains("Simulated"))
        precondition(legacy.durationAccessibilityValue.contains("Simulated"))
        var wire = fixtures["manual"]!
        for value in [0, 60001] {
            wire["sample_duration_ms"] = value
            let invalid = try decode(wire)
            precondition(!invalid.hasValidAcquisition && invalid.bacReading == nil)
        }
        wire = fixtures["manual"]!
        wire["estimated_bac_percent"] = 0.08
        let inventedBAC = try decode(wire)
        precondition(!inventedBAC.hasValidAcquisition && inventedBAC.bacReading == nil)
        wire = fixtures["manual"]!
        wire["breath_duration_ms"] = 2500
        let mixed = try decode(wire)
        precondition(!mixed.hasValidAcquisition && mixed.durationText == "Duration unavailable")
        wire = fixtures["manual"]!
        wire["acquisition_method"] = "unknown"
        let unknown = try decode(wire)
        precondition(!unknown.hasValidAcquisition)
        wire = fixtures["legacy"]!
        wire["acquisition_method"] = NSNull()
        wire["sample_duration_ms"] = NSNull()
        let pairedNull = try decode(wire)
        precondition(pairedNull.hasValidAcquisition)
        wire["source"] = "device"
        wire["estimated_bac_percent"] = 0.04
        let estimatedLegacy = try decode(wire)
        precondition(estimatedLegacy.bacReading?.value == 0.04)
        wire["breath_duration_ms"] = NSNull()
        let missingDuration = try decode(wire)
        precondition(!missingDuration.hasValidAcquisition)
        print("Acquisition decoding checks passed: nullable manual, legacy, invalid/mixed/unknown metadata, labels and BAC gates.")
    }
}
