import Foundation

@main
struct DeviceSessionChecks {
    @MainActor static func main() async throws {
        let base = URL(string: "https://api.kickbac.vodka")!
        let printed = try DeviceTarget.parse("kb-demo-01", baseURL: base)
        let linked = try DeviceTarget.parse("https://api.kickbac.vodka/d/kb-demo-01", baseURL: base)
        precondition(printed == "kb-demo-01" && linked == printed)
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
        try flow.select("kb-demo-01", baseURL: base)
        flow.switchOwner("sms|owner-a")
        await inspect(flow)
        precondition(flow.device?.online == false) // Offline and available are independent.
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

    private static func session(_ status: APITestSession.Status, owner: String = "sms|owner-a", measurement: APIMeasurement? = nil) -> APITestSession {
        APITestSession(id: "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b", deviceID: "kb-demo-01", userID: owner,
                       status: status, createdAt: "2026-10-17T23:00:00Z", expiresAt: "2026-10-17T23:01:00Z",
                       completedAt: nil, measurement: measurement)
    }

    private static func reading(estimate: Double? = nil, source: String = "device") -> APIMeasurement {
        APIMeasurement(id: "measurement", sessionID: "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b", deviceID: "kb-demo-01",
                       raw: .init(sensor: "mq3", value: 1200, unit: "adc_counts"), breathDurationMS: 2500,
                       source: source, measuredAt: nil, receivedAt: "2026-10-17T23:00:05Z", estimatedBACPercent: estimate)
    }
}
