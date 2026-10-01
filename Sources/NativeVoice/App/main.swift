import AppKit

// `AppDelegate` is @MainActor, and top-level code in a SwiftPM executable is
// nonisolated, so constructing it directly does not compile under Swift 6
// concurrency checking. A SwiftPM executable does start on the main thread,
// so this asserts a fact rather than changing behaviour.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
