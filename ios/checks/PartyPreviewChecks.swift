import Foundation

@main
struct PartyPreviewChecks {
    @MainActor
    static func main() {
        let preview = PartyPreview()
        assert(preview.room == nil && preview.ongoingGame == nil)
        preview.showExampleGame(.trivia)
        assert(preview.ongoingGame == nil)

        assert(!preview.create(name: "  ", deviceID: "kb-demo-01"))
        assert(!preview.create(name: String(repeating: "a", count: 81), deviceID: "kb-demo-01"))
        assert(!preview.create(name: "Friday\nnight", deviceID: "kb-demo-01"))
        assert(!preview.create(name: "Friday", deviceID: "../another-device"))
        assert(preview.room == nil)
        assert(preview.create(name: " Friday night ", deviceID: " kb-demo-01 "))
        assert(preview.room?.name == "Friday night" && preview.room?.deviceID == "kb-demo-01")
        assert(preview.room?.role == .host && preview.ongoingGame == nil)

        preview.showExampleGame(.pictionary)
        preview.viewAs(.guest)
        assert(preview.room?.role == .guest && preview.ongoingGame == .pictionary)
        preview.showExampleGame(nil)
        assert(preview.ongoingGame == nil)
        let previousRoom = preview.room
        assert(!preview.join(code: "ABC123"))
        assert(!preview.join(code: "KICK26-extra"))
        assert(preview.room == previousRoom)
        assert(preview.join(code: " kick26\n"))
        assert(preview.room?.role == .guest && preview.ongoingGame == nil)

        preview.showExampleGame(.trivia)
        preview.leave()
        assert(preview.room == nil && preview.ongoingGame == nil)
        preview.previewTap()
        assert(preview.room?.role == .guest && preview.ongoingGame == nil)
        assert(preview.create(name: "Friday"))
        assert(preview.room?.role == .host && preview.room?.deviceID == "kb-demo-01")
        assert(PartyGame.allCases.map(\.id) == [.trivia, .pictionary])
        print("Party preview checks passed")
    }
}
