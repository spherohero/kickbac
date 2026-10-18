import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root:
// swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/ProfileStore.swift ios/KickBAC/ProfilePhoto.swift ios/KickBAC/KickBACAPI.swift ios/checks/ProfileChecks.swift -o /tmp/kickbac-profile-checks
// /tmp/kickbac-profile-checks
@main
struct ProfileChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "kickbac-profile-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = "sms|../account-a/+opaque"
        let coalesced = ProfileStore(directory: directory)
        coalesced.load(owner: owner)
        var resume: CheckedContinuation<APIProfile, Never>?
        let first = Task {
            await coalesced.refresh {
                await withCheckedContinuation { resume = $0 }
            }
        }
        while resume == nil { await Task.yield() }
        var secondStarted = false
        var secondReturned = false
        let second = Task {
            secondStarted = true
            await coalesced.refresh { preconditionFailure("Duplicated in-flight profile GET") }
            secondReturned = true
        }
        while !secondStarted { await Task.yield() }
        await Task.yield()
        precondition(!secondReturned && coalesced.remoteState == .unknown)
        resume!.resume(returning: response(owner: owner, name: "Loaded once"))
        await first.value
        await second.value
        precondition(secondReturned && coalesced.remoteState == .saved && !coalesced.isLoading)

        let store = ProfileStore(directory: directory)
        store.load(owner: owner)
        precondition(store.remoteState == .unknown && !store.needsOnboarding)
        await store.refresh { throw URLError(.notConnectedToInternet) }
        precondition(store.remoteState == .unknown && !store.needsOnboarding && store.message != nil)
        await store.refresh { response(owner: owner, name: nil) }
        precondition(store.needsOnboarding && store.message == nil)

        let photo = try png(width: 3000, height: 2000)
        let jpeg = try ProfilePhoto.prepare(photo)
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        precondition(CGImageSourceGetType(source)! as String == UTType.jpeg.identifier)
        precondition(properties[kCGImagePropertyPixelWidth] as! Int == 512)
        precondition((properties[kCGImagePropertyPixelHeight] as! Int) <= 512 && jpeg.count <= 524_288)
        let tiny = try ProfilePhoto.prepare(png(width: 24, height: 16))
        let tinySource = CGImageSourceCreateWithData(tiny as CFData, nil)!
        let tinyProperties = CGImageSourceCopyPropertiesAtIndex(tinySource, 0, nil)! as NSDictionary
        precondition(tinyProperties[kCGImagePropertyPixelWidth] as! Int == 24)
        do {
            _ = try ProfilePhoto.prepare(Data([1, 2, 3]))
            preconditionFailure("Accepted an invalid image")
        } catch ProfilePhoto.PreparationError.invalidImage { }

        try await store.save(name: "  Liam  ", photoData: photo) { name, data in
            precondition(store.isSaving && name == "Liam" && data!.count <= 524_288)
            return response(owner: owner, name: name, photo: data)
        }
        precondition(store.remoteState == .saved && store.profile.name == "Liam" && !store.isSaving)
        let savedPhoto = store.profile.photoData
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(files.count == 1 && !files[0].contains("account-a"))
        let restored = ProfileStore(directory: directory)
        restored.load(owner: owner)
        precondition(restored.profile == store.profile && restored.remoteState == .unknown)
        await restored.refresh { response(owner: owner, name: "Server name", photo: jpeg) }
        precondition(restored.profile.name == "Server name" && restored.remoteState == .saved)
        await restored.refresh { throw URLError(.timedOut) }
        precondition(restored.remoteState == .saved && !restored.needsOnboarding)

        for name in ["  ", String(repeating: "x", count: 81), "Li\u{0000}am"] {
            do {
                try await store.save(name: name, photoData: nil) { _, _ in preconditionFailure("Sent invalid name") }
                preconditionFailure("Accepted an invalid name")
            } catch ProfileStore.SaveError.invalidName { }
        }
        precondition(PartyProfile.isValidName(String(repeating: "x", count: 80)))
        // Count Unicode code points rather than Swift extended grapheme clusters.
        precondition(!PartyProfile.isValidName(String(repeating: "e\u{301}", count: 41)))
        do {
            try await store.save(name: "Pending edit", photoData: nil) { _, _ in throw URLError(.notConnectedToInternet) }
            preconditionFailure("Accepted a failed network save")
        } catch { }
        precondition(store.profile.name == "Liam" && store.profile.photoData == savedPhoto && !store.isSaving)
        // A name-only edit supplies the existing picture; an explicit nil removes it.
        try await store.save(name: "New name", photoData: savedPhoto) { name, data in
            precondition(data == savedPhoto)
            return response(owner: owner, name: name, photo: data)
        }
        try await store.save(name: "New name", photoData: nil) { name, data in
            precondition(data == nil)
            return response(owner: owner, name: name)
        }
        precondition(store.profile.photoData == nil)

        store.load(owner: "sms|account-b")
        precondition(store.profile == PartyProfile() && store.remoteState == .unknown)
        await store.refresh { response(owner: owner, name: "Foreign profile") }
        precondition(store.profile == PartyProfile() && store.remoteState == .unknown)
        await store.refresh { response(owner: "sms|account-b", name: nil) }
        do {
            try await store.save(name: "Nicholas", photoData: nil) { name, _ in
                store.load(owner: owner)
                return response(owner: "sms|account-b", name: name)
            }
            preconditionFailure("Applied a save after switching accounts")
        } catch ProfileStore.SaveError.signedOut { }
        precondition(store.owner == owner && store.profile.name == "New name" && !store.isSaving)
        await store.refresh {
            store.load(owner: "sms|account-b")
            return response(owner: owner, name: "Stale GET")
        }
        precondition(store.profile == PartyProfile() && !store.isLoading)
        store.load(owner: nil)
        precondition(store.profile == PartyProfile() && store.owner == nil)
        do {
            try await store.save(name: "Signed out", photoData: nil) { _, _ in preconditionFailure("Sent signed-out save") }
            preconditionFailure("Saved a profile without an account")
        } catch ProfileStore.SaveError.signedOut { }

        // A successful server write remains successful if the local cache cannot be written.
        let blocked = directory.appending(path: "file-not-directory")
        try Data().write(to: blocked)
        let unavailable = ProfileStore(directory: blocked)
        unavailable.load(owner: owner)
        await unavailable.refresh { response(owner: owner, name: nil) }
        try await unavailable.save(name: "Saved online", photoData: nil) { name, _ in response(owner: owner, name: name) }
        precondition(unavailable.profile.name == "Saved online" && unavailable.remoteState == .saved && unavailable.message != nil)

        let received = "2026-10-17T01:00:05+00:00"
        let baseline = try Date(received, strategy: .iso8601)
        precondition(reading(measured: nil, received: received).recordedDate == baseline)
        precondition(reading(measured: "invalid", received: received).recordedDate == baseline)
        let fractional = reading(measured: "2026-10-16T21:00:04.125-04:00", received: received)
        precondition(abs(fractional.recordedDate!.timeIntervalSince(baseline) + 0.875) < 0.001)
        precondition(reading(measured: "2026-10-17T01:00:00Z", received: received).recordedDate! < baseline)
        precondition(reading(measured: "invalid", received: "invalid").recordedDate == nil)
        precondition(fractional.estimatedBACPercent == nil && fractional.isTestReading)
        print("Profile checks passed: remote persistence, retries, account isolation, stale responses, explicit removal, image bounds/conversion, Unicode validation, cache failure, timestamps and null BAC.")
    }

    private static func response(owner: String, name: String?, photo: Data? = nil) -> APIProfile {
        APIProfile(userID: owner, displayName: name,
                   profilePicture: photo.map { APIProfilePicture(contentType: "image/jpeg", data: $0) },
                   createdAt: nil, updatedAt: nil)
    }

    private static func png(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func reading(measured: String?, received: String) -> APIMeasurement {
        APIMeasurement(id: "reading", sessionID: "session", deviceID: "device",
                       raw: .init(sensor: "mq3", value: 1200, unit: "adc_counts"),
                       breathDurationMS: 2500, acquisitionMethod: nil, sampleDurationMS: nil, source: "simulator", measuredAt: measured,
                       receivedAt: received, estimatedBACPercent: nil)
    }
}
