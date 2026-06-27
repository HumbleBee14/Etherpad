import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var synthVC: MacSynthViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        synthVC = MacSynthViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isRestorable = false
        window.title = "Etherpad"
        window.contentViewController = synthVC
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillResignActive(_ notification: Notification) {
        synthVC?.handleAppDeactivation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        synthVC?.shutdown()
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(MacSynthViewController.showSettingsMenu),
                        keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Etherpad",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let modeItem = NSMenuItem()
        mainMenu.addItem(modeItem)
        let modeMenu = NSMenu(title: "Mode")
        let multitouchItem = NSMenuItem(
            title: "Toggle Touchpad Mode",
            action: #selector(MacSynthViewController.toggleMultitouch),
            keyEquivalent: "m")
        multitouchItem.keyEquivalentModifierMask = [.option]
        modeMenu.addItem(multitouchItem)

        let immersiveItem = NSMenuItem(
            title: "Toggle Immersive Mode",
            action: #selector(MacSynthViewController.toggleImmersive),
            keyEquivalent: "h")
        immersiveItem.keyEquivalentModifierMask = [.option]
        modeMenu.addItem(immersiveItem)

        modeMenu.addItem(.separator())
        let recordStartItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(MacSynthViewController.startRecordingMenu),
            keyEquivalent: "r")
        recordStartItem.keyEquivalentModifierMask = [.option]
        modeMenu.addItem(recordStartItem)
        let recordStopItem = NSMenuItem(
            title: "Stop Recording",
            action: #selector(MacSynthViewController.stopRecordingMenu),
            keyEquivalent: "s")
        recordStopItem.keyEquivalentModifierMask = [.option]
        modeMenu.addItem(recordStopItem)
        modeItem.submenu = modeMenu

        NSApp.mainMenu = mainMenu
    }
}

// @main on an NSApplicationDelegate does not start the AppKit run loop without a
// storyboard/XIB; bootstrap NSApplication explicitly.
let app = NSApplication.shared
let delegate = MacAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
