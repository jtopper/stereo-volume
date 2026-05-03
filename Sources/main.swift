import AppKit

// main.swift runs on the main thread; tell Swift concurrency it's the main actor.
MainActor.assumeIsolated {
    let app      = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
