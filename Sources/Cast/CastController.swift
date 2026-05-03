import Foundation
import Network

// Receiver status reported by the Chromecast.
struct ReceiverVolume {
    var level: Float
    var muted: Bool
}

// High-level Cast receiver controller: connection lifecycle, heartbeat, volume API.
// @MainActor so callers can safely update UI from the closure callbacks.
@MainActor
final class CastController {
    var onVolumeChanged: ((ReceiverVolume) -> Void)?

    private let conn       = CastConnection()
    private var endpoint:  NWEndpoint?
    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var requestID  = 1

    // MARK: - Connect

    func connect(to endpoint: NWEndpoint) {
        self.endpoint = endpoint
        reconnect?.cancel()
        startConnection()
    }

    func disconnect() {
        heartbeat?.cancel()
        reconnect?.cancel()
        conn.disconnect()
    }

    // MARK: - Volume API

    func setVolume(_ level: Float) {
        send(namespace: CastNamespace.receiver,
             payload: #"{"type":"SET_VOLUME","volume":{"level":\#(level)},"requestId":\#(nextID())}"#)
    }

    func setMuted(_ muted: Bool) {
        send(namespace: CastNamespace.receiver,
             payload: #"{"type":"SET_VOLUME","volume":{"muted":\#(muted)},"requestId":\#(nextID())}"#)
    }

    func requestStatus() {
        send(namespace: CastNamespace.receiver,
             payload: #"{"type":"GET_STATUS","requestId":\#(nextID())}"#)
    }

    // MARK: - Private

    private func startConnection() {
        guard let endpoint else { return }
        conn.onReady      = { [weak self] in    Task { @MainActor [weak self] in self?.handleReady() } }
        conn.onMessage    = { [weak self] msg in Task { @MainActor [weak self] in self?.handle(msg) } }
        conn.onDisconnect = { [weak self] in    Task { @MainActor [weak self] in self?.scheduleReconnect() } }
        conn.connect(to: endpoint)
        startHeartbeat()
    }

    private func handleReady() {
        send(namespace: CastNamespace.connection, payload: #"{"type":"CONNECT"}"#)
        requestStatus()
    }

    private func scheduleReconnect() {
        heartbeat?.cancel()
        reconnect = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.startConnection() }
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self.send(namespace: CastNamespace.heartbeat,
                          sourceID: "sender-0",
                          destinationID: "receiver-0",
                          payload: #"{"type":"PING"}"#)
            }
        }
    }

    private func handle(_ msg: CastMessage) {
        switch msg.namespace {
        case CastNamespace.heartbeat:
            break   // PONG — nothing to do
        case CastNamespace.receiver:
            parseReceiverStatus(msg.payloadUtf8)
        default:
            break
        }
    }

    private func parseReceiverStatus(_ json: String) {
        struct Response: Decodable {
            let type: String
            let status: Status?
            struct Status: Decodable {
                let volume: Volume?
                struct Volume: Decodable {
                    let level: Float?
                    let muted: Bool?
                }
            }
        }
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.type == "RECEIVER_STATUS",
              let vol = response.status?.volume
        else { return }

        onVolumeChanged?(ReceiverVolume(
            level: vol.level ?? 0,
            muted: vol.muted ?? false
        ))
    }

    private func send(namespace: String,
                      sourceID: String = "sender-0",
                      destinationID: String = "receiver-0",
                      payload: String) {
        var msg = CastMessage()
        msg.sourceID      = sourceID
        msg.destinationID = destinationID
        msg.namespace     = namespace
        msg.payloadUtf8   = payload
        conn.send(msg)
    }

    private func nextID() -> Int {
        defer { requestID += 1 }
        return requestID
    }
}

// MARK: - Cast namespaces

private enum CastNamespace {
    static let receiver  = "urn:x-cast:com.google.cast.receiver"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
}
