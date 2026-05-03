import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Intercepts system media key events via CGEventTap.
// Only intercepts if the current default audio output matches `wantedDevice`.
// All callbacks are dispatched to the main queue.
final class MediaKeyInterceptor {
    var onVolumeUp:        (() -> Void)?
    var onVolumeDown:      (() -> Void)?
    var onMute:            (() -> Void)?
    var onPermissionDenied:(() -> Void)?

    // The audio output device name we want to intercept keys for.
    var wantedDevice: String = ""

    private var tapPort:   CFMachPort?
    private var tapThread: Thread?

    // MARK: - Start

    func start() {
        // Check Accessibility permission before attempting the event tap.
        // If not granted, surface the error immediately rather than letting
        // the tap silently fail.
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?() }
            return
        }

        let thread = Thread { [weak self] in self?.runTap() }
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    // MARK: - Private

    private func runTap() {
        let mask = CGEventMask(1 << 14)   // NX_SYSDEFINED = 14
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let me = Unmanaged<MediaKeyInterceptor>
                    .fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("stereo-vol: could not create event tap — Accessibility permission not granted")
            DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?() }
            return
        }

        tapPort = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    private func handle(proxy: CGEventTapProxy,
                        type: CGEventType,
                        event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type.rawValue == 14 else { return Unmanaged.passRetained(event) }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8,
              nsEvent.data1 != -1
        else { return Unmanaged.passRetained(event) }

        let keyCode  = (nsEvent.data1 & 0xFFFF0000) >> 16
        let keyFlags =  nsEvent.data1 & 0x0000FFFF
        let keyDown  = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyDown else { return Unmanaged.passRetained(event) }

        guard keyCode == 0 || keyCode == 1 || keyCode == 7 else {
            return Unmanaged.passRetained(event)
        }

        guard let current = AudioDevices.defaultOutputName(),
              current == wantedDevice
        else { return Unmanaged.passRetained(event) }

        let code = keyCode
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch code {
            case 0: self.onVolumeUp?()
            case 1: self.onVolumeDown?()
            case 7: self.onMute?()
            default: break
            }
        }
        return nil   // suppress — we handled it
    }
}
