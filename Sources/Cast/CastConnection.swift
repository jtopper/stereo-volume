import Network
import Security
import Foundation

// Low-level Cast V2 connection: TLS to port 8009, length-prefixed protobuf frames.
// All methods are called from CastController's actor context.
final class CastConnection {
    private var connection: NWConnection?
    var onMessage: ((CastMessage) -> Void)?
    var onDisconnect: (() -> Void)?

    // MARK: - Connect / Disconnect

    func connect(to endpoint: NWEndpoint) {
        let params = makeParameters()
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onDisconnect?()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        receiveNext(conn)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Send

    func send(_ message: CastMessage) {
        guard let conn = connection else { return }
        let data = message.encode()
        conn.send(content: data,
                  contentContext: .defaultMessage,
                  isComplete: true,
                  completion: .idempotent)
    }

    // MARK: - Private

    private func receiveNext(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty,
               let msg = try? CastMessage(data: data) {
                self?.onMessage?(msg)
            }
            if error == nil {
                self?.receiveNext(conn)
            }
        }
    }

    private func makeParameters() -> NWParameters {
        // TLS with certificate validation disabled — Cast devices use self-signed certs.
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            .global(qos: .userInitiated)
        )

        let params = NWParameters(tls: tlsOptions)
        // Insert our length-prefix framer above TLS.
        params.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolFramer.Options(definition: CastFramer.definition),
            at: 0
        )
        return params
    }
}
