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

    // Browses until the named device is found or `timeout` elapses.
    // Returns immediately on match rather than waiting out the full timeout.
    static func discover(named target: String, timeout: Duration) async -> CastDevice? {
        await withCheckedContinuation { continuation in
            var resumed = false

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local."),
                using: .tcp
            )

            browser.browseResultsChangedHandler = { results, _ in
                guard !resumed else { return }
                for result in results {
                    guard case let .bonjour(txt) = result.metadata,
                          let name = txt["fn"],
                          name == target
                    else { continue }
                    resumed = true
                    browser.cancel()
                    continuation.resume(returning: CastDevice(name: name, endpoint: result.endpoint))
                    return
                }
            }

            browser.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(for: timeout)
                guard !resumed else { return }
                resumed = true
                browser.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}
