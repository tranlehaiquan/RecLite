import Cocoa

// Top-level code in main.swift runs synchronously on the main thread.
// We can safely instantiate AppDelegate here using MainActor.assumeIsolated.
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
