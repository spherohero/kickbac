import Foundation

// A disappearing preview may stop only its own lease, never a newer preview's camera.
nonisolated struct CameraActivity {
    private(set) var owner: UUID?
    private(set) var revision = 0

    mutating func activate(owner: UUID) -> Int {
        self.owner = owner
        revision += 1
        return revision
    }

    mutating func deactivate(owner: UUID) -> Int? {
        guard self.owner == owner else { return nil }
        self.owner = nil
        revision += 1
        return revision
    }

    mutating func nextRequest() -> Int? {
        guard owner != nil else { return nil }
        revision += 1
        return revision
    }

    func isCurrent(_ revision: Int) -> Bool { self.revision == revision }
}

nonisolated struct CameraRequestOrder {
    private var latest = 0

    mutating func accept(_ revision: Int) -> Bool {
        guard revision >= latest else { return false }
        latest = revision
        return true
    }
}
