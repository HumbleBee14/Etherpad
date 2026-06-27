import AppKit

@main
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vc = MacSynthViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Etherpad"
        window.contentViewController = vc
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

// TEMP stub, replaced in Task 6 by macOS/MacSynthViewController.swift.
final class MacSynthViewController: NSViewController {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 790)) }
}
