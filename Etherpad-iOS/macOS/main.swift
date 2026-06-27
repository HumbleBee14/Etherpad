import AppKit

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

// Explicit AppKit bootstrap. NOTE: `@main` on an NSApplicationDelegate does NOT
// start the AppKit run loop or connect the delegate when there is no storyboard/
// XIB — the process launches but applicationDidFinishLaunching never fires, so no
// window appears. We bootstrap NSApplication manually instead.
let app = NSApplication.shared
let delegate = MacAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

// Temporary stub; replaced by MacSynthViewController.swift.
final class MacSynthViewController: NSViewController {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 790)) }
}
