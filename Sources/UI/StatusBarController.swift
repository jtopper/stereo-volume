import AppKit

@MainActor
final class StatusBarController {
    var onVolumeChanged:  ((Float) -> Void)?
    var onMuteToggled:    (() -> Void)?
    var onPreferences:    (() -> Void)?
    var onQuit:           (() -> Void)?

    private let statusItem  = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let sliderView  = VolumeSliderView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
    private let muteItem    = NSMenuItem(title: "Mute",         action: nil, keyEquivalent: "")
    private let prefsItem   = NSMenuItem(title: "Preferences…", action: nil, keyEquivalent: "")

    private var volumeTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        buildMenu()
        statusItem.button?.title = "🔊"

        sliderView.onChanged = { [weak self] vol in
            self?.throttledVolumeSet(vol)
        }
    }

    // MARK: - Update from outside

    func update(volume: ReceiverVolume) {
        if volume.muted {
            statusItem.button?.title = "🔇"
            sliderView.setVolume(volume.level, label: "Muted")
            muteItem.state = .on
        } else {
            statusItem.button?.title = "🔊"
            sliderView.setVolume(volume.level, label: "\(Int((volume.level * 100).rounded()))%")
            muteItem.state = .off
        }
    }

    func setConnectionStatus(_ text: String) {
        sliderView.setVolume(0, label: text)
    }

    func setPreferencesEnabled(_ enabled: Bool) {
        prefsItem.isEnabled = enabled
    }

    // MARK: - Private

    private func buildMenu() {
        let menu = NSMenu()

        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        muteItem.target = self
        muteItem.action = #selector(muteTapped)
        menu.addItem(muteItem)

        menu.addItem(.separator())

        prefsItem.target = self
        prefsItem.action = #selector(prefsTapped)
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // Throttle slider → Chromecast: send immediately, then at most once per 100 ms.
    private func throttledVolumeSet(_ vol: Float) {
        statusItem.button?.title = "🔊"
        volumeTask?.cancel()
        volumeTask = Task {
            onVolumeChanged?(vol)                          // immediate
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            onVolumeChanged?(vol)                          // trailing update
        }
    }

    // MARK: - Actions

    @objc private func muteTapped()  { onMuteToggled?() }
    @objc private func prefsTapped() { onPreferences?() }
    @objc private func quitTapped()  { onQuit?() }
}
