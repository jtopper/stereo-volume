import AppKit

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    var onSave: ((Config) -> Void)?

    private var window:       NSWindow?
    private var audioPopup:   NSPopUpButton?
    private var castPopup:    NSPopUpButton?
    private var castSpinner:  NSProgressIndicator?
    private var castStatus:   NSTextField?
    private var saveButton:   NSButton?

    private var currentConfig: Config = Config()

    // MARK: - Open

    func open(current config: Config) {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        currentConfig = config

        // Phase 1: build window with audio devices immediately.
        buildWindow(audioDevices: AudioDevices.outputDeviceNames(), current: config)

        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Phase 2: discover Chromecasts while the dialog is open.
        Task {
            var devices = await ChromecastDiscovery.discover(timeout: .seconds(3))
            // Always include the currently configured device even if not found.
            if !config.castDeviceName.isEmpty,
               !devices.contains(where: { $0.name == config.castDeviceName }) {
                devices.insert(CastDevice(name: config.castDeviceName,
                                          endpoint: .hostPort(host: .name("", nil), port: 8009)),
                               at: 0)
            }
            populateCast(devices: devices, current: config.castDeviceName)
        }
    }

    // MARK: - Build window

    private func buildWindow(audioDevices: [String], current config: Config) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title    = "stereo-vol Preferences"
        win.delegate = self
        win.center()
        guard let cv = win.contentView else { return }

        // Audio Output row
        addLabel("Audio Output:", to: cv, frame: NSRect(x: 20, y: 105, width: 114, height: 22))
        let ap = NSPopUpButton(frame: NSRect(x: 142, y: 103, width: 268, height: 26), pullsDown: false)
        if audioDevices.isEmpty {
            ap.addItem(withTitle: "No audio output devices found")
            ap.isEnabled = false
        } else {
            audioDevices.forEach { ap.addItem(withTitle: $0) }
            if !config.audioDeviceName.isEmpty { ap.selectItem(withTitle: config.audioDeviceName) }
        }
        cv.addSubview(ap)
        audioPopup = ap

        // Chromecast row — loading state
        addLabel("Chromecast:", to: cv, frame: NSRect(x: 20, y: 65, width: 114, height: 22))

        let spinner = NSProgressIndicator(frame: NSRect(x: 142, y: 67, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        cv.addSubview(spinner)
        castSpinner = spinner

        let status = NSTextField(labelWithString: "Discovering Chromecast devices…")
        status.frame     = NSRect(x: 164, y: 67, width: 246, height: 18)
        status.textColor = .secondaryLabelColor
        status.font      = .systemFont(ofSize: NSFont.smallSystemFontSize)
        cv.addSubview(status)
        castStatus = status

        let cp = NSPopUpButton(frame: NSRect(x: 142, y: 63, width: 268, height: 26), pullsDown: false)
        cp.isHidden = true
        cv.addSubview(cp)
        castPopup = cp

        // Buttons
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.frame         = NSRect(x: 252, y: 16, width: 80, height: 28)
        cancel.keyEquivalent = "\u{1B}"
        cv.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        save.frame         = NSRect(x: 340, y: 16, width: 70, height: 28)
        save.keyEquivalent = "\r"
        save.isEnabled     = false
        cv.addSubview(save)
        saveButton = save

        self.window = win
    }

    // MARK: - Phase 2: populate cast dropdown

    private func populateCast(devices: [CastDevice], current: String) {
        guard window != nil else { return }   // dismissed during discovery

        castSpinner?.stopAnimation(nil); castSpinner?.isHidden = true
        castStatus?.isHidden = true
        castPopup?.isHidden  = false

        let cp = castPopup!
        cp.removeAllItems()
        if devices.isEmpty {
            cp.addItem(withTitle: "No Chromecast devices found")
            cp.isEnabled    = false
            saveButton?.isEnabled = false
        } else {
            devices.forEach { cp.addItem(withTitle: $0.name) }
            if !current.isEmpty { cp.selectItem(withTitle: current) }
            cp.isEnabled          = true
            saveButton?.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        guard let win = window else { return }
        var cfg = currentConfig
        cfg.audioDeviceName = audioPopup?.titleOfSelectedItem ?? ""
        cfg.castDeviceName  = castPopup?.titleOfSelectedItem  ?? ""
        self.window = nil
        win.orderOut(nil)
        onSave?(cfg)
    }

    @objc private func cancelClicked() {
        dismiss()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(); return false
    }

    private func dismiss() {
        guard let win = window else { return }
        self.window = nil
        win.orderOut(nil)
    }

    // MARK: - Helpers

    private func addLabel(_ text: String, to view: NSView, frame: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.frame     = frame
        label.alignment = .right
        view.addSubview(label)
    }
}
