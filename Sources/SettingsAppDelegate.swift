import AppKit

/// The settings window, opened from Applications or Spotlight. It exits as soon as its window is closed.
@MainActor
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(intercepts: false)
    private var windowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let windowController = SettingsWindowController(model: model) {
            NSApp.terminate(nil)
        }
        self.windowController = windowController
        model.onStateChange = { [weak windowController] in windowController?.refresh() }
        model.onLogChange = { [weak windowController] in windowController?.refreshLog() }
        model.start()
        NSApp.activate()
        windowController.showWindow(nil)
    }

    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
