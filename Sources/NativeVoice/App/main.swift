import AppKit

// `MainActor.assumeIsolated` rather than a bare call: the top-level code of
// a main.swift executable runs on the main thread but is not inferred as
// MainActor-isolated by the compiler, so a synchronous call into the
// MainActor-isolated AppDelegate needs this assertion. It is a runtime
// assertion of a fact that is true by construction here — this is the
// process's main thread — not a workaround of an actual race.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
