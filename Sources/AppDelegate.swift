import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config      = Config.load()
    private let cast        = CastController()
    private let interceptor = MediaKeyInterceptor()
    private var statusBar:  StatusBarController!
    private var prefs:      PreferencesWindowController!

    private var volumeBeforeMute: Float = 0.5
    private var currentVolume:    ReceiverVolume = ReceiverVolume(level: 0.5, muted: false)

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // hide from Dock

        statusBar = StatusBarController()
        prefs     = PreferencesWindowController()

        // Wire up status bar callbacks
        statusBar.onVolumeChanged = { [weak self] vol in self?.handleSlider(vol) }
        statusBar.onMuteToggled   = { [weak self] in     self?.handleMute() }
        statusBar.onPreferences   = { [weak self] in     self?.showPreferences() }
        statusBar.onQuit          = { NSApp.terminate(nil) }

        // Wire up Cast controller callback
        cast.onVolumeChanged = { [weak self] vol in
            guard let self else { return }
            self.currentVolume = vol
            self.statusBar.update(volume: vol)
        }

        // Start event interceptor
        interceptor.wantedDevice = config.audioDeviceName
        interceptor.onVolumeUp   = { [weak self] in self?.adjustVolume(+0.02) }
        interceptor.onVolumeDown = { [weak self] in self?.adjustVolume(-0.02) }
        interceptor.onMute       = { [weak self] in self?.handleMute() }
        interceptor.start()

        // Connect to configured Chromecast
        if !config.castDeviceName.isEmpty {
            statusBar.setConnectionStatus("Connecting…")
            connectToCast(named: config.castDeviceName)
        } else {
            statusBar.setConnectionStatus("Not configured")
        }
    }

    // MARK: - Volume control

    private func adjustVolume(_ delta: Float) {
        guard !currentVolume.muted else { return }
        let newLevel = min(1, max(0, currentVolume.level + delta))
        currentVolume.level = newLevel
        statusBar.update(volume: currentVolume)
        cast.setVolume(newLevel)
    }

    private func handleSlider(_ vol: Float) {
        cast.setVolume(vol)
    }

    private func handleMute() {
        if currentVolume.muted {
            cast.setMuted(false)
            cast.setVolume(volumeBeforeMute)
        } else {
            volumeBeforeMute = currentVolume.level
            cast.setMuted(true)
        }
    }

    // MARK: - Preferences

    private func showPreferences() {
        prefs.onSave = { [weak self] newConfig in
            guard let self else { return }
            self.config = newConfig
            try? newConfig.save()
            self.interceptor.wantedDevice = newConfig.audioDeviceName
            self.statusBar.setConnectionStatus("Connecting…")
            self.connectToCast(named: newConfig.castDeviceName)
        }
        prefs.open(current: config)
    }

    // MARK: - Discovery + connect

    private func connectToCast(named name: String) {
        Task {
            let devices = await ChromecastDiscovery.discover(timeout: .seconds(10))
            guard let device = devices.first(where: { $0.name == name }) else {
                self.statusBar.setConnectionStatus("Not found")
                return
            }
            self.cast.connect(to: device.endpoint)
        }
    }
}
