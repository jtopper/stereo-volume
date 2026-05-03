import Network
import Foundation

// NWProtocolFramer that implements the Cast wire format:
// each message is prefixed with a 4-byte big-endian length.
final class CastFramer: NWProtocolFramerImplementation {
    static let label      = "CastV2Framer"
    static let definition = NWProtocolFramer.Definition(implementation: CastFramer.self)

    required init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    // Called whenever new bytes arrive. Returns the minimum bytes needed before
    // being called again; 0 means "call me as soon as anything arrives".
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var bodyLength = 0

            let parsedHeader = framer.parseInput(
                minimumIncompleteLength: 4,
                maximumLength: 4
            ) { buffer, _ -> Int in
                guard let buffer, buffer.count == 4 else { return 0 }
                bodyLength = Int(UInt32(bigEndian: buffer.load(fromByteOffset: 0, as: UInt32.self)))
                return 4   // consumed 4 header bytes
            }
            guard parsedHeader else { return 4 }   // need more data

            let msg = NWProtocolFramer.Message(definition: CastFramer.definition)
            guard framer.deliverInputNoCopy(length: bodyLength,
                                            message: msg,
                                            isComplete: true) else { return 0 }
        }
    }

    func handleOutput(framer: NWProtocolFramer.Instance,
                      message: NWProtocolFramer.Message,
                      messageLength: Int,
                      isComplete: Bool) {
        var header = UInt32(messageLength).bigEndian
        framer.writeOutput(data: Data(bytes: &header, count: 4))
        try? framer.writeOutputNoCopy(length: messageLength)
    }
}
