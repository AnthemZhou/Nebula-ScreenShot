// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKey()
    private let capture = CaptureCoordinator()
    private var welcome: WelcomeWindow?
    private var permissionFlowActive = false
    private var permissionPrompt = ScreenPermissionPrompt()

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
        hotKey.onPress = { [weak self] in self?.captureFromShortcut() }
        hotKey.register()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--demo") {
            capture.begin(demo: true)
        } else if CommandLine.arguments.contains("--capture") {
            capture.begin()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
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
        settings.addItem(withTitle: "重新授权屏幕录制…", action: #selector(reauthorizeScreenPermission), keyEquivalent: "")
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
        guard !permissionFlowActive else { return }
        welcome?.window?.orderOut(nil)
        capture.begin(afterMenuDismissal: true)
    }

    private func captureFromShortcut() {
        guard !permissionFlowActive else { return }
        statusItem.menu?.cancelTracking()
        welcome?.window?.orderOut(nil)
        capture.begin()
    }

    @objc private func beginDemo() {
        guard !permissionFlowActive else { return }
        welcome?.window?.orderOut(nil)
        capture.begin(demo: true, afterMenuDismissal: true)
    }

    @objc private func showWelcome() {
        if capture.isActive { return }
        if welcome == nil { welcome = WelcomeWindow() }
        welcome?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcome?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openScreenPermission() {
        guard !permissionFlowActive else { return }
        permissionFlowActive = true
        // A newly reset app may not appear in Settings until it explicitly requests consent.
        _ = permissionPrompt.requestOnce(using: CGRequestScreenCaptureAccess)
        permissionFlowActive = false
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
    }

    @objc private func checkShortcut() {
        hotKey.register()
        let alert = NSAlert()
        let conflict = HotKey.systemConflict
        if hotKey.registrationStatus != noErr {
            alert.messageText = "快捷键暂时无法注册"
            alert.informativeText = "请退出占用此组合的其他截图应用，再重新检测。也可从菜单栏开始截图。\n错误代码：\(hotKey.registrationStatus)"
        } else {
            alert.messageText = "快捷键已注册：\(HotKey.displayString)"
            alert.informativeText = "按下快捷键即可选择截图区域。首次使用需允许屏幕录制。"
            if conflict == true {
                alert.informativeText += "\n\n已以独占方式注册。若仍出现系统截屏面板，请在键盘快捷键 → 截屏中调整“截屏和录制选项”。"
            }
        }
        alert.addButton(withTitle: "好")
        if conflict == true || hotKey.registrationStatus != noErr { alert.addButton(withTitle: "快捷键设置") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openKeyboardSettings() }
    }

    private func showPermissionHelp() {
        guard !permissionFlowActive else { return }
        permissionFlowActive = true
        // Request only after ScreenCaptureKit denies a user-initiated capture. Do not
        // use Core Graphics preflight to block a capture that ScreenCaptureKit can perform.
        if permissionPrompt.requestOnce(using: CGRequestScreenCaptureAccess) == true {
            permissionFlowActive = false
            capture.begin()
            return
        }
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在系统设置中允许 Nebula ScreenShot。若开关已打开仍无法截图，“重新授权”会仅清除 Nebula 的旧屏幕录制记录，重启后再次请求授权。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "重新授权")
        alert.addButton(withTitle: "稍后").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            permissionFlowActive = false
            openScreenPermission()
        case .alertSecondButtonReturn:
            recoverScreenPermission()
        default:
            permissionFlowActive = false
        }
    }

    @objc private func reauthorizeScreenPermission() {
        guard !permissionFlowActive, !capture.isActive else { return }
        permissionFlowActive = true
        let alert = NSAlert()
        alert.messageText = "重新授权屏幕录制？"
        alert.informativeText = "仅清除 Nebula ScreenShot 的旧屏幕录制授权记录，并重新启动当前应用。系统随后会再次请求授权。其他应用的权限不受影响。"
        alert.addButton(withTitle: "重新授权")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            recoverScreenPermission()
        } else {
            permissionFlowActive = false
        }
    }

    /// The caller keeps the permission flow locked after the user's explicit recovery action.
    private func recoverScreenPermission() {
        statusItem.button?.toolTip = "正在重新授权屏幕录制…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ScreenPermissionRecovery.resetAndPrepareRelaunch()
                NSApp.terminate(nil)
            } catch {
                self.restoreStatusIcon()
                self.showError(error.localizedDescription)
                self.permissionFlowActive = false
            }
        }
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
    func applicationDidBecomeActive(_ notification: Notification) {
        if !hotKey.isRegistered { hotKey.register() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey.unregister(); capture.finish(restoreFocus: false) }
}
