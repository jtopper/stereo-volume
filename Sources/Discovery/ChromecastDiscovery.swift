import Network
import Foundation

struct CastDevice {
    let name:     String
    let endpoint: NWEndpoint
}

// Discovers Chromecast devices on the local network via mDNS.
enum ChromecastDiscovery {
    // Browses for up to `timeout` seconds and returns all found devices.
    static func discover(timeout: Duration) async -> [CastDevice] {
        await withCheckedContinuation { continuation in
            var devices: [CastDevice] = []
            var seen = Set<String>()

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local."),
                using: .tcp
            )

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .bonjour(txt) = result.metadata,
                          let name = txt["fn"],
                          !seen.contains(name)
                    else { continue }
                    seen.insert(name)
                    devices.append(CastDevice(name: name, endpoint: result.endpoint))
                }
            }

            browser.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(for: timeout)
                browser.cancel()
                continuation.resume(returning: devices)
            }
        }
    }
}
