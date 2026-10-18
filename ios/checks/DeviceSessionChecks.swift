import Foundation

@main
struct DeviceSessionChecks {
    @MainActor static func main() async throws {
        let base = URL(string: "https://api.kickbac.vodka")!
        let printed = try DeviceTarget.parse("kb-demo-01", baseURL: base)
        let linked = try DeviceTarget.parse("https://api.kickbac.vodka/d/kb-demo-01", baseURL: base)
        precondition(printed == "kb-demo-01" && linked == printed)
        let shortcut = DeviceTarget.shortcutURL(for: printed)!
        let shortcutTarget = try DeviceTarget.parseAppLink(shortcut, baseURL: base)
        let publicTarget = try DeviceTarget.parseAppLink(URL(string: "https://api.kickbac.vodka/d/kb-demo-01")!, baseURL: base)
        precondition(shortcutTarget == printed && publicTarget == printed)
        precondition(DeviceTarget.shortcutURL(for: "../other") == nil)
        let onlineUnit = APIDevice(id: printed, state: "AVAILABLE", online: true, lastSeenAt: nil)
        let offlineUnit = APIDevice(id: printed, state: "AVAILABLE", online: false, lastSeenAt: nil)
        precondition(onlineUnit.connectionLabel == "kb-demo-01 connected")
        precondition(offlineUnit.connectionLabel == "kb-demo-01 found · offline")
        precondition(!offlineUnit.connectionLabel.contains("connected"))
        for input in ["com.liam.KickBAC://device/kb-demo-01?arm=true",
                      "com.liam.KickBAC://device/kb-demo-01#arm", "com.liam.KickBAC://device:443/kb-demo-01",
                      "com.liam.KickBAC://user@device/kb-demo-01", "com.liam.KickBAC://device/kb-demo-01/extra",
                      "com.liam.KickBAC://device/%6Bb-demo-01", "com.liam.KickBAC://device/../other",
                      "com.liam.KickBAC://other/kb-demo-01", "other.app://device/kb-demo-01",
                      "com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback",
                      "http://api.kickbac.vodka/d/kb-demo-01", "https://evil.example/d/kb-demo-01"] {
            do { _ = try DeviceTarget.parseAppLink(URL(string: input)!, baseURL: base); preconditionFailure("Accepted an unrelated/unsafe app link") }
            catch DeviceTarget.TargetError.invalid { }
        }
        for input in ["https://evil.example/d/kb-demo-01", "http://api.kickbac.vodka/d/kb-demo-01",
                      "https://api.kickbac.vodka@evil.example/d/kb-demo-01", "https://api.kickbac.vodka/d/%2Fother",
                      "https://api.kickbac.vodka/d/kb-demo-01?next=evil", "../other", "https://api.kickbac.vodka:444/d/kb-demo-01"] {
            do { _ = try DeviceTarget.parse(input, baseURL: base); preconditionFailure("Accepted an untrusted device target") }
            catch DeviceTarget.TargetError.invalid { }
        }
        precondition(!DeviceTarget.isValidID("kb-demo-01\n"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "kickbac-device-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let flow = DeviceSessionStore(directory: directory)
        try flow.select(shortcutTarget, baseURL: base)
        precondition(flow.targetID == printed && flow.owner == nil && flow.test == nil && !flow.hasActiveSession,
                     "Opening a tag must only identify a device before sign-in")
        flow.switchOwner("sms|owner-a")
        precondition(flow.targetID == printed && flow.test == nil, "Device target must survive sign-in without arming")

        let scanDirectory = directory.appending(path: "scan")
        let scanFlow = DeviceSessionStore(directory: scanDirectory)
        var arms = 0
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in preconditionFailure("Looked up a scan without sign-in") },
            fetch: { _ in preconditionFailure() }, create: { _ in preconditionFailure() })
        scanFlow.switchOwner("sms|owner-a")
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in DeviceResolution(deviceID: printed) },
            fetch: { _ in APIDevice(id: printed, state: "AVAILABLE", online: false, lastSeenAt: nil) },
            create: { _ in preconditionFailure("Armed an offline scanned device") })
        precondition(!scanFlow.hasActiveSession && scanFlow.message?.contains("offline") == true)
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in DeviceResolution(deviceID: "wrong-unit") },
            fetch: { _ in preconditionFailure("Fetched after mismatched resolver") },
            create: { _ in preconditionFailure("Armed a mismatched resolver") })
        precondition(!scanFlow.hasActiveSession)
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in DeviceResolution(deviceID: printed) },
            fetch: { _ in
                scanFlow.switchOwner("sms|owner-b")
                return APIDevice(id: printed, state: "AVAILABLE", online: true, lastSeenAt: nil)
            }, create: { _ in preconditionFailure("A scan crossed an account switch") })
        precondition(!scanFlow.hasActiveSession && scanFlow.owner == "sms|owner-b")
        scanFlow.switchOwner("sms|owner-a")
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in DeviceResolution(deviceID: printed) },
            fetch: { _ in APIDevice(id: printed, state: "AVAILABLE", online: true, lastSeenAt: nil) },
            create: { id in
                precondition(id == printed)
                arms += 1
                return session(.armed)
            })
        precondition(arms == 1 && scanFlow.hasActiveSession)
        let scanSession = scanFlow.sessionID
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in preconditionFailure("Repeated tap resolved instead of resuming") },
            fetch: { _ in preconditionFailure() }, create: { _ in preconditionFailure("Repeated tap rearmed") })
        await scanFlow.startFromScan("other-unit", baseURL: base,
            resolve: { _ in preconditionFailure() }, fetch: { _ in preconditionFailure() },
            create: { _ in preconditionFailure("Different tag replaced an active test") })
        precondition(scanFlow.sessionID == scanSession && scanFlow.targetID == printed && arms == 1)
        scanFlow.resetCompletedTest()
        precondition(scanFlow.sessionID == scanSession && scanFlow.test?.status == .armed,
                     "Test again cleared an active reservation")
        await scanFlow.poll(fetch: { _ in session(.complete, measurement: reading()) }, onComplete: { })
        precondition(scanFlow.test?.status == .complete && !scanFlow.hasActiveSession)
        scanFlow.resetCompletedTest()
        precondition(scanFlow.test == nil && scanFlow.device == nil && scanFlow.targetID == nil
                     && scanFlow.message == nil && scanFlow.owner == "sms|owner-a" && arms == 1,
                     "Test again must clear the display and wait for a fresh tap without arming")
        let resetRestored = DeviceSessionStore(directory: scanDirectory)
        resetRestored.switchOwner("sms|owner-a")
        precondition(!resetRestored.hasActiveSession, "Reset restored the finished test as pending")
        let nextSessionID = UUID().uuidString.lowercased()
        await scanFlow.startFromScan(printed, baseURL: base,
            resolve: { _ in DeviceResolution(deviceID: printed) },
            fetch: { _ in APIDevice(id: printed, state: "AVAILABLE", online: true, lastSeenAt: nil) },
            create: { _ in
                arms += 1
                return session(.armed, id: nextSessionID)
            })
        precondition(arms == 2 && scanFlow.sessionID == nextSessionID && scanFlow.sessionID != scanSession,
                     "Fresh tap after Test again must start a new session")

        await inspect(flow)
        precondition(flow.device?.online == false) // Offline and available are independent.
        for status in [APITestSession.Status.armed, .sampling] {
            await flow.arm { _ in session(status, measurement: reading()) }
            precondition(!flow.hasActiveSession && flow.test == nil && flow.message != nil,
                         "Active arm response exposed a premature measurement")
        }
        await flow.arm { _ in session(.armed) }
        precondition(flow.hasActiveSession && flow.test?.status == .armed)
        await flow.arm { _ in preconditionFailure("Silently rearmed an active session") }
        let restored = DeviceSessionStore(directory: directory)
        restored.switchOwner("sms|owner-a")
        precondition(restored.sessionID == flow.sessionID && restored.targetID == "kb-demo-01")
        var completions = 0
        await restored.poll(fetch: { _ in session(.complete, measurement: reading()) }, onComplete: { completions += 1 })
        precondition(!restored.hasActiveSession && completions == 1)
        precondition(restored.test?.measurement?.estimatedBACPercent == nil)
        precondition(restored.test?.measurement?.bacReading == nil)
        await restored.poll(fetch: { _ in preconditionFailure("Polled a terminal session") }, onComplete: { preconditionFailure() })

        await flow.cancel { _ in throw KickBACAPI.APIError.server(status: 409, code: "invalid_state") }
        precondition(flow.hasActiveSession && flow.message != nil)
        await flow.poll(fetch: { _ in session(.expired) }, onComplete: { preconditionFailure("Expired test produced a reading") })
        precondition(!flow.hasActiveSession && flow.test?.status == .expired)
        await flow.arm { _ in session(.armed) }
        await flow.cancel { _ in session(.cancelled) }
        precondition(!flow.hasActiveSession && flow.test?.status == .cancelled)

        await flow.arm { _ in throw KickBACAPI.APIError.server(status: 409, code: "device_busy") }
        precondition(!flow.hasActiveSession && flow.message!.contains("being used"))
        await flow.arm { _ in session(.armed) }
        await flow.poll(fetch: { _ in session(.sampling, owner: "sms|foreign") }, onComplete: { preconditionFailure() })
        precondition(flow.test?.status == .armed && flow.message != nil)
        await flow.poll(fetch: { _ in
            flow.switchOwner("sms|owner-b")
            return session(.complete, measurement: reading())
        }, onComplete: { preconditionFailure("Applied another account's completion") })
        precondition(flow.owner == "sms|owner-b" && flow.test == nil && !flow.hasActiveSession)

        flow.switchOwner(nil)
        precondition(flow.test == nil && flow.device == nil)
        flow.switchOwner("sms|owner-a")
        precondition(flow.hasActiveSession) // Private pending session survives logout/relogin.
        await flow.poll(fetch: { _ in session(.complete, measurement: reading()) }, onComplete: { completions += 1 })
        precondition(completions == 2)
        let afterCompletion = DeviceSessionStore(directory: directory)
        afterCompletion.switchOwner("sms|owner-a")
        precondition(!afterCompletion.hasActiveSession)
        await inspect(flow)
        await flow.arm { _ in session(.armed) }
        await flow.poll(fetch: { _ in throw KickBACAPI.APIError.server(status: 404, code: "not_found") }, onComplete: { preconditionFailure() })
        precondition(!flow.hasActiveSession && flow.test == nil && flow.message != nil)
        try flow.select("another-device", baseURL: base)
        let afterMissing = DeviceSessionStore(directory: directory)
        afterMissing.switchOwner("sms|owner-a")
        precondition(!afterMissing.hasActiveSession)

        let manual = APIMeasurement(id: "manual", sessionID: "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b", deviceID: "kb-demo-01",
                                    raw: .init(sensor: "mq3", value: 1200, unit: "adc_counts"), breathDurationMS: nil,
                                    acquisitionMethod: "manual_timed", sampleDurationMS: 5000, source: "device", measuredAt: nil,
                                    receivedAt: "2026-10-17T23:00:05Z", estimatedBACPercent: nil)
        let invalid = APIMeasurement(id: "invalid", sessionID: manual.sessionID, deviceID: manual.deviceID,
                                     raw: manual.raw, breathDurationMS: 5000, acquisitionMethod: "manual_timed", sampleDurationMS: 5000,
                                     source: "device", measuredAt: nil, receivedAt: manual.receivedAt, estimatedBACPercent: nil)
        try flow.select("kb-demo-01", baseURL: base)
        await inspect(flow)
        await flow.arm { _ in session(.armed) }
        await flow.poll(fetch: { _ in session(.complete, measurement: invalid) }, onComplete: {
            preconditionFailure("Invalid acquisition produced a completion")
        })
        precondition(flow.hasActiveSession && flow.test?.status == .armed && flow.message != nil)
        await flow.poll(fetch: { _ in session(.complete, measurement: manual) }, onComplete: { completions += 1 })
        precondition(!flow.hasActiveSession && flow.test?.measurement?.isManualTimed == true && completions == 3)
        precondition(flow.test?.measurement?.bacReading == nil)

        let real = reading(estimate: 0.04, source: "device")
        let simulated = reading(estimate: 0.08, source: "simulator")
        precondition(real.bacReading?.value == 0.04 && simulated.bacReading == nil)
        let summary = DailyBACSummary(readings: [real, simulated, reading()].compactMap(\.bacReading), day: real.recordedDate!)
        precondition(summary.average == 0.04 && summary.high == 0.04)
        print("Device checks passed: trusted targets, offline availability, explicit arming, persistence, cancel/expiry, busy conflicts, terminal polling, owner isolation, and honest real/simulated/null BAC.")
    }

    @MainActor private static func inspect(_ flow: DeviceSessionStore) async {
        await flow.inspect(resolve: { DeviceResolution(deviceID: $0) }, fetch: {
            APIDevice(id: $0, state: "AVAILABLE", online: false, lastSeenAt: nil)
        })
    }

    private static func session(_ status: APITestSession.Status, owner: String = "sms|owner-a", measurement: APIMeasurement? = nil,
                                id: String = "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b") -> APITestSession {
        APITestSession(id: id, deviceID: "kb-demo-01", userID: owner,
                       status: status, createdAt: "2026-10-17T23:00:00Z", expiresAt: "2026-10-17T23:01:00Z",
                       completedAt: nil, measurement: measurement)
    }

    private static func reading(estimate: Double? = nil, source: String = "device") -> APIMeasurement {
        APIMeasurement(id: "measurement", sessionID: "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b", deviceID: "kb-demo-01",
                       raw: .init(sensor: "mq3", value: 1200, unit: "adc_counts"), breathDurationMS: 2500, acquisitionMethod: nil, sampleDurationMS: nil,
                       source: source, measuredAt: nil, receivedAt: "2026-10-17T23:00:05Z", estimatedBACPercent: estimate)
    }
}
