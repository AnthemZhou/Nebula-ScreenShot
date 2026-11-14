// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKey()
    private let capture = CaptureCoordinator()
    private var welcome: WelcomeWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        capture.onError = { [weak self] in self?.showError($0) }
        capture.onPermissionNeeded = { [weak self] in self?.showWelcome() }
        capture.onComplete = { [weak self] message in
            self?.statusItem.button?.toolTip = message
            self?.statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.restoreStatusIcon() }
        }
        hotKey.onPress = { [weak self] in self?.beginCapture() }
        hotKey.register()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--demo") {
            capture.begin(demo: true)
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") || hotKey.registrationStatus != noErr {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showWelcome()
        }
    }

    private func configureMenu() {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "关于 Nebula ScreenShot", action: #selector(showWelcome), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出 Nebula ScreenShot", action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = submenu
        appMenu.addItem(appItem)
        NSApp.mainMenu = appMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        restoreStatusIcon()
        let menu = NSMenu()
        let title = NSMenuItem(title: "Nebula ScreenShot", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let captureItem = NSMenuItem(title: "区域截图  ⌃⇧⌘4", action: #selector(beginCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(withTitle: "试用标注…", action: #selector(beginDemo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置与使用说明…", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(withTitle: "GitHub 开源仓库", action: #selector(openRepository), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Nebula ScreenShot", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func restoreStatusIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nebula ScreenShot")
        statusItem.button?.toolTip = "Nebula ScreenShot · ⌃⇧⌘4"
    }

    @objc private func beginCapture() {
        welcome?.window?.orderOut(nil)
        capture.begin()
    }

    @objc private func beginDemo() {
        welcome?.window?.orderOut(nil)
        capture.begin(demo: true)
    }

    @objc private func showWelcome() {
        if capture.isActive { return }
        if welcome == nil {
            let controller = WelcomeWindow()
            controller.onCapture = { [weak self] in self?.beginCapture() }
            controller.onDemo = { [weak self] in self?.beginDemo() }
            controller.onRetryShortcut = { [weak self] in self?.hotKey.register(); self?.refreshStatus() }
            welcome = controller
        }
        welcome?.refresh(registrationFailed: hotKey.registrationStatus != noErr)
        welcome?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcome?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshStatus() { welcome?.refresh(registrationFailed: hotKey.registrationStatus != noErr) }
    @objc private func displaysChanged() { if capture.isActive { capture.finish() } }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot")!) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Nebula ScreenShot"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey.unregister(); capture.finish(restoreFocus: false) }
}
