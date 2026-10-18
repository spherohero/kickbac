import Foundation
import CryptoKit
@preconcurrency import MultipeerConnectivity

/// Encrypted, party/game-scoped nearby transport. The party host owns round state.
@MainActor
final class NearbyTrivia: NSObject {
    private let game: TriviaPreview
    private let scope: String
    private let name: String
    private let hosting: Bool
    private let peer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invited: Set<MCPeerID> = []
    private var discoveredHosts: Set<MCPeerID> = []
    private var lastInvitation = Date.distantPast
    private var players: [MCPeerID: String] = [:]
    private var heartbeat: Task<Void, Never>?
    private var lastRevision = -1
    private var revision = 0
    private var stopped = false
    private static let service = "kickbac-trivia"

    private struct Packet: Codable {
        let scope: String
        let kind: String
        let playerID: String
        let name: String
        let participation: TriviaPreview.Participation
        var index: Int?
        var round: Int
        var revision: Int
        var snapshot: TriviaPreview.Snapshot?
        var partyCode: String?
    }

    init(game: TriviaPreview, partyID: String, gameID: String, name: String, isHost: Bool) {
        self.game = game
        self.name = String((name.isEmpty ? "Player" : name).prefix(60))
        hosting = isHost
        scope = SHA256.hash(data: Data((partyID + ":" + gameID).utf8)).map { String(format: "%02x", $0) }.joined()
        peer = MCPeerID(displayName: UUID().uuidString)
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        game.localPlayerID = peer.displayName
        game.usesNearby = true
        game.isNearbyHost = isHost
        game.nearbyPlayers = [.init(id: peer.displayName, name: self.name, participation: game.participation)]
        game.connectionMessage = isHost ? "Waiting for players" : "Connecting to the host"
        game.sendNearbyAction = { [weak self] kind, index in self?.sendAction(kind, index: index) }
        game.nearbyDidChange = { [weak self] in self?.publish() }
        session.delegate = self
        if isHost {
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["room": scope], serviceType: Self.service)
            advertiser.delegate = self
            self.advertiser = advertiser
            advertiser.startAdvertisingPeer()
        } else {
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
            browser.delegate = self
            self.browser = browser
            browser.startBrowsingForPeers()
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                if self.hosting { self.publish() }
                else {
                    self.sendAction("ready", index: nil)
                    self.reconnectIfNeeded()
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() {
        stopped = true
        heartbeat?.cancel(); heartbeat = nil
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session.disconnect()
        game.sendNearbyAction = nil; game.nearbyDidChange = nil
    }

    private func sendAction(_ kind: String, index: Int?) {
        guard !hosting, !stopped else { return }
        send(Packet(scope: scope, kind: kind, playerID: peer.displayName, name: name,
                    participation: game.participation, index: index, round: game.roundNumber, revision: 0), to: session.connectedPeers)
    }

    private func reconnectIfNeeded() {
        guard !hosting, !stopped, session.connectedPeers.isEmpty,
              Date.now.timeIntervalSince(lastInvitation) >= 6,
              let host = discoveredHosts.first, let browser else { return }
        lastInvitation = .now
        invited.insert(host)
        browser.invitePeer(host, to: session, withContext: Data(scope.utf8), timeout: 5)
    }

    private func publish() {
        guard hosting, !stopped else { return }
        revision += 1
        send(Packet(scope: scope, kind: "state", playerID: peer.displayName, name: name,
                    participation: game.participation, round: game.roundNumber,
                    revision: revision, snapshot: game.snapshot(), partyCode: game.sharedPartyCode), to: session.connectedPeers)
    }

    private func send(_ packet: Packet, to peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(packet)
            try session.send(data, toPeers: peers, with: .reliable)
        } catch { game.connectionMessage = "Connection interrupted. Keep both phones nearby." }
    }

    private func receive(_ data: Data, from sender: MCPeerID) {
        guard !stopped, data.count <= 65536, session.connectedPeers.contains(sender),
              let packet = try? JSONDecoder().decode(Packet.self, from: data), packet.scope == scope,
              packet.playerID == sender.displayName else { return }
        if hosting {
            guard packet.kind != "state", packet.name.count <= 60 else { return }
            players[sender] = packet.playerID
            game.updateNearbyPlayer(id: packet.playerID, name: packet.name, participation: packet.participation)
            guard packet.round == game.roundNumber else { publish(); return }
            if packet.kind == "spin" { game.spin(playerID: packet.playerID) }
            if packet.kind == "answer", let index = packet.index {
                game.recordAnswer(playerID: packet.playerID, index: index)
            }
            publish()
        } else if packet.kind == "state", packet.revision > lastRevision, let snapshot = packet.snapshot {
            lastRevision = packet.revision
            if let code = packet.partyCode, code.count == 8,
               code.allSatisfy({ "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }) {
                game.sharedPartyCode = code
            }
            game.apply(snapshot)
        }
    }

    private func changed(_ sender: MCPeerID, state: MCSessionState) {
        guard !stopped else { return }
        if state == .connected {
            game.connectionMessage = nil
            if hosting { publish() } else { sendAction("ready", index: nil) }
        } else if state == .notConnected {
            invited.remove(sender)
            game.connectionMessage = hosting ? "Waiting for players to reconnect" : "Reconnecting to the host"
            if let id = players[sender], let player = game.nearbyPlayers.first(where: { $0.id == id }) {
                game.updateNearbyPlayer(id: id, name: player.name, participation: .undecided)
            }
        }
    }
}

extension NearbyTrivia: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in self?.changed(peerID, state: state) }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.receive(data, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}

extension NearbyTrivia: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                               withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, context == Data(self.scope.utf8), self.session.connectedPeers.count < 7 else {
                invitationHandler(false, nil); return
            }
            invitationHandler(true, self.session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in self?.game.connectionMessage = "Allow Local Network access in Settings to connect players." }
    }
}

extension NearbyTrivia: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, info?["room"] == self.scope, !self.invited.contains(peerID) else { return }
            self.discoveredHosts.insert(peerID)
            self.reconnectIfNeeded()
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.invited.remove(peerID)
            self?.discoveredHosts.remove(peerID)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in self?.game.connectionMessage = "Allow Local Network access in Settings to connect players." }
    }
}
