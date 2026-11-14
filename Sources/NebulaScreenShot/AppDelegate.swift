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
        capture.onPermissionNeeded = { [weak self] in self?.showPermissionHelp() }
        capture.onComplete = { [weak self] message in
            self?.statusItem.button?.toolTip = message
            self?.statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.restoreStatusIcon() }
        }
        hotKey.onPress = { [weak self] in self?.beginCapture() }
        hotKey.register()
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
        let captureItem = NSMenuItem(title: "区域截图  \(HotKey.displayString)", action: #selector(beginCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(withTitle: "试用标注…", action: #selector(beginDemo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "关于 Nebula ScreenShot…", action: #selector(showWelcome), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let settings = NSMenu()
        settings.addItem(withTitle: "屏幕录制权限…", action: #selector(openScreenPermission), keyEquivalent: "")
        settings.addItem(withTitle: "键盘快捷键设置…", action: #selector(openKeyboardSettings), keyEquivalent: "")
        settings.addItem(withTitle: "重新检测快捷键…", action: #selector(checkShortcut), keyEquivalent: "")
        for item in settings.items { item.target = self }
        settingsItem.submenu = settings
        menu.addItem(settingsItem)
        menu.addItem(withTitle: "使用说明", action: #selector(openHelp), keyEquivalent: "")
        menu.addItem(withTitle: "GitHub 开源仓库", action: #selector(openRepository), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Nebula ScreenShot", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func restoreStatusIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nebula ScreenShot")
        statusItem.button?.toolTip = "Nebula ScreenShot · \(HotKey.displayString)"
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
        if welcome == nil { welcome = WelcomeWindow() }
        welcome?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcome?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openScreenPermission() {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
    }

    @objc private func checkShortcut() {
        hotKey.register()
        let alert = NSAlert()
        let conflict = HotKey.systemConflict
        if conflict == true {
            alert.messageText = "系统占用了 \(HotKey.displayString)"
            alert.informativeText = "请检查系统设置 → 键盘 → 键盘快捷键 → 截屏中的“截屏和录制选项”。调整后重新检测。"
        } else if hotKey.registrationStatus != noErr {
            alert.messageText = "快捷键暂时无法注册"
            alert.informativeText = "请检查其他应用或仍在运行的旧版 Nebula 是否占用了该组合。也可从菜单栏开始截图。"
        } else {
            alert.messageText = "快捷键已注册：\(HotKey.displayString)"
            alert.informativeText = conflict == nil ? "暂时无法读取系统占用情况。可尝试快捷键，或从菜单栏开始截图。" : "可以使用此快捷键开始截图。"
        }
        alert.addButton(withTitle: "好")
        if conflict == true || hotKey.registrationStatus != noErr { alert.addButton(withTitle: "快捷键设置") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openKeyboardSettings() }
    }

    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "在系统设置中允许 Nebula ScreenShot 后重试；如系统要求，请重新打开应用。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openScreenPermission() }
    }

    @objc private func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot#使用")!) }
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
