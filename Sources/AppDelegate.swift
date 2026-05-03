import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config      = Config.load()
    private let cast        = CastController()
    private let interceptor = MediaKeyInterceptor()
    private var statusBar:  StatusBarController!
    private var prefs:      PreferencesWindowController!

    private var volumeBeforeMute:       Float = 0.5
    private var currentVolume:          ReceiverVolume = ReceiverVolume(level: 0.5, muted: false)
    private var suppressFeedbackUntil:  Date = .distantPast

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

        // Wire up Cast controller callback — ignore feedback while slider is being dragged.
        cast.onVolumeChanged = { [weak self] vol in
            guard let self else { return }
            // Enable controls on first successful volume reading from the device.
            self.statusBar.setConfigured(true)
            guard Date() >= self.suppressFeedbackUntil else { return }
            self.currentVolume = vol
            self.statusBar.update(volume: vol)
        }

        // Start event interceptor
        interceptor.wantedDevice      = config.audioDeviceName
        interceptor.onVolumeUp        = { [weak self] in self?.adjustVolume(+0.02) }
        interceptor.onVolumeDown      = { [weak self] in self?.adjustVolume(-0.02) }
        interceptor.onMute            = { [weak self] in self?.handleMute() }
        interceptor.onPermissionDenied = { [weak self] in self?.showAccessibilityAlert() }
        interceptor.start()

        // Connect to configured Chromecast, or prompt for first-time setup.
        if !config.castDeviceName.isEmpty && !config.audioDeviceName.isEmpty {
            statusBar.setConnectionStatus("Connecting…")
            connectToCast(named: config.castDeviceName)
        } else {
            statusBar.setConfigured(false)
            statusBar.setConnectionStatus("Not configured")
            showPreferences(firstRun: true)
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
        currentVolume.level = vol
        suppressFeedbackUntil = Date().addingTimeInterval(1.0)
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

    // MARK: - Accessibility permission

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText     = "Accessibility Permission Required"
        alert.informativeText = "stereo-vol needs Accessibility access to intercept media keys. Grant permission in System Settings → Privacy & Security → Accessibility, then restart the app."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Preferences

    private func showPreferences(firstRun: Bool = false) {
        prefs.onSave = { [weak self] newConfig in
            guard let self else { return }
            self.config = newConfig
            try? newConfig.save()
            self.interceptor.wantedDevice = newConfig.audioDeviceName
            self.statusBar.setConfigured(false)
            self.statusBar.setConnectionStatus("Connecting…")
            self.connectToCast(named: newConfig.castDeviceName)
        }
        prefs.open(current: config, firstRun: firstRun)
    }

    // MARK: - Discovery + connect

    private func connectToCast(named name: String) {
        Task {
            guard let device = await ChromecastDiscovery.discover(named: name, timeout: .seconds(10)) else {
                self.statusBar.setConnectionStatus("Not found")
                return
            }
            self.cast.connect(to: device.endpoint)
        }
    }
}
