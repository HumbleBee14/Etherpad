import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var synthVC: MacSynthViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        synthVC = MacSynthViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Etherpad"
        window.contentViewController = synthVC
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

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
        appMenu.addItem(withTitle: "About Etherpad",
                        action: #selector(MacSynthViewController.showAboutMenu),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Etherpad",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let modeItem = NSMenuItem()
        mainMenu.addItem(modeItem)
        let modeMenu = NSMenu(title: "Mode")
        modeMenu.addItem(withTitle: "Toggle Multitouch",
                         action: #selector(MacSynthViewController.toggleMultitouch),
                         keyEquivalent: "m")
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
