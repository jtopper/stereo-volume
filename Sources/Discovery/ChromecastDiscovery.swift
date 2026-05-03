import Network
import Foundation

struct CastDevice {
    let name:     String
    let endpoint: NWEndpoint
}

// Discovers Chromecast devices on the local network via mDNS.
enum ChromecastDiscovery {
    // Browses for up to `timeout` and returns all found devices.
    // Used by the preferences dialog to populate the dropdown.
    static func discover(timeout: Duration) async -> [CastDevice] {
        // Mutable state accessed only from `queue` (serial), so @unchecked Sendable is safe.
        final class State: @unchecked Sendable {
            var devices: [CastDevice] = []
            var seen    = Set<String>()
        }
        let state = State()
        let queue = DispatchQueue(label: "stereo-vol.discovery.all")

        return await withCheckedContinuation { continuation in
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local."),
                using: .tcp
            )

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .bonjour(txt) = result.metadata,
                          let name = txt["fn"],
                          !state.seen.contains(name)
                    else { continue }
                    state.seen.insert(name)
                    state.devices.append(CastDevice(name: name, endpoint: result.endpoint))
                }
            }

            browser.start(queue: queue)

            Task {
                try? await Task.sleep(for: timeout)
                queue.async {
                    browser.cancel()
                    continuation.resume(returning: state.devices)
                }
            }
        }
    }

    // Browses until the named device is found or `timeout` elapses.
    // Returns immediately on match rather than waiting out the full timeout.
    static func discover(named target: String, timeout: Duration) async -> CastDevice? {
        // Mutable state accessed only from `queue` (serial), so @unchecked Sendable is safe.
        final class State: @unchecked Sendable {
            var resumed = false
        }
        let state = State()
        let queue = DispatchQueue(label: "stereo-vol.discovery.named")

        return await withCheckedContinuation { continuation in
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local."),
                using: .tcp
            )

            browser.browseResultsChangedHandler = { results, _ in
                guard !state.resumed else { return }
                for result in results {
                    guard case let .bonjour(txt) = result.metadata,
                          let name = txt["fn"],
                          name == target
                    else { continue }
                    state.resumed = true
                    browser.cancel()
                    continuation.resume(returning: CastDevice(name: name, endpoint: result.endpoint))
                    return
                }
            }

            browser.start(queue: queue)

            Task {
                try? await Task.sleep(for: timeout)
                queue.async {
                    guard !state.resumed else { return }
                    state.resumed = true
                    browser.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
