import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var testEngine: MacCsoundEngine?   // TEMP (Task 4 audio self-test)

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

        // TEMP audio self-test: play a pad note at 0.3s, release at 2.0s.
        let e = MacCsoundEngine(); testEngine = e
        e.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            e.noteOn(slot: 0, x: 0.5, y: 0.7)
            NSLog("[Etherpad-mac] TEST noteOn fired")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            e.noteOff(slot: 0); NSLog("[Etherpad-mac] TEST noteOff fired")
        }
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
