// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore
import OSLog
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKey()
    private let capture = CaptureCoordinator()
    private var welcome: WelcomeWindow?
    private var permissionFlowActive = false
    private var permissionPrompt = ScreenPermissionPrompt()
    private let permissionLifecycle = PermissionLifecycle()
    private var plannedRelaunch: AppRelauncher.Session?
    private var permissionRestartPlanned = false
    private var explicitQuit = false
    private var sessionEnding = false
    private var permissionUpgrade: ScreenPermissionUpgrade!
    private var permissionRepairItem: NSMenuItem!
    private let permissionLogger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Permission")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        permissionUpgrade = ScreenPermissionUpgrade()
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        capture.onError = { [weak self] in self?.showError($0) }
        capture.onPermissionNeeded = { [weak self] in self?.showPermissionHelp() }
        capture.onCaptureReady = { [weak self] in
            self?.permissionLifecycle.cancel()
            self?.permissionUpgrade.clear()
            self?.permissionRepairItem.isHidden = true
            self?.restoreStatusIcon()
        }
        permissionLifecycle.onGranted = { [weak self] in self?.restartAfterConsent() }
        capture.onComplete = { [weak self] message in
            self?.statusItem.button?.toolTip = message
            self?.statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.restoreStatusIcon() }
        }
        hotKey.onPress = { [weak self] in self?.captureFromShortcut() }
        hotKey.register()
        if !CommandLine.arguments.contains("--repair-screen-permission") &&
           !CommandLine.arguments.contains("--request-screen-permission") { capture.prepare() }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkPermissionChange),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionWillEnd),
            name: NSWorkspace.willPowerOffNotification, object: nil)
        if CommandLine.arguments.contains("--repair-screen-permission") {
            permissionFlowActive = true
            recoverScreenPermission()
        } else if CommandLine.arguments.contains("--request-screen-permission") {
            requestNativePermission()
        } else if CommandLine.arguments.contains("--resume-after-permission") {
            permissionLogger.notice("Resumed after consent; shortcut registered: \(self.hotKey.isRegistered, privacy: .public)")
        } else if CommandLine.arguments.contains("--demo") {
            capture.begin(demo: true)
        } else if CommandLine.arguments.contains("--capture") {
            capture.begin()
        } else if firstLaunch {
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
        permissionRepairItem = NSMenuItem(title: "修复屏幕录制授权…", action: #selector(reauthorizeScreenPermission), keyEquivalent: "")
        permissionRepairItem.isHidden = true
        menu.addItem(permissionRepairItem)
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
        requestNativePermission(openSettingsAfterRequest: true)
    }

    private func openScreenPermissionSettings() {
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
        permissionRepairItem.isHidden = false
        statusItem.button?.toolTip = "屏幕录制权限待授权 · 可在菜单中修复授权"
        // Only a changed ad-hoc build gets one automatic repair after a real denial.
        // The persisted claim prevents resets on subsequent denials or relaunches.
        if permissionUpgrade.consumeAfterCaptureDenial() {
            permissionLogger.notice("Repairing outdated ad-hoc screen permission once")
            permissionFlowActive = true
            recoverScreenPermission()
            return
        }
        requestNativePermission(retryCaptureIfGranted: true)
    }

    private func requestNativePermission(retryCaptureIfGranted: Bool = false, openSettingsAfterRequest: Bool = false) {
        guard !permissionFlowActive else { return }
        permissionFlowActive = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.permissionFlowActive = false }
            do {
                // The helper must be watching before native consent can terminate this app.
                try await self.permissionLifecycle.prepare()
                guard !self.explicitQuit, !self.sessionEnding else { self.permissionLifecycle.cancel(); return }
                NSApp.activate(ignoringOtherApps: true)
                let action = self.permissionPrompt.actionAfterDenial {
                    self.permissionLogger.notice("Requesting native screen consent; automatic relaunch armed")
                    return CGRequestScreenCaptureAccess()
                }
                switch action {
                case .retryCapture:
                    if retryCaptureIfGranted { self.capture.begin() }
                    else { self.capture.prepare() }
                case .waitForSystem: self.permissionRepairItem.isHidden = false
                case .openSettings: self.openScreenPermissionSettings()
                }
                if openSettingsAfterRequest && action != .openSettings { self.openScreenPermissionSettings() }
            } catch {
                self.permissionLifecycle.cancel()
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func reauthorizeScreenPermission() {
        guard !permissionFlowActive, !capture.isActive else { return }
        permissionFlowActive = true
        recoverScreenPermission()
    }

    /// The caller keeps the flow locked until this process exits or recovery fails.
    private func recoverScreenPermission() {
        permissionLifecycle.cancel()
        permissionUpgrade.clear()
        statusItem.button?.toolTip = "正在重新授权屏幕录制…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await ScreenPermissionRecovery.resetAndPrepareRelaunch()
                self.plannedRelaunch = session
                try await session.waitUntilReady()
                guard !self.explicitQuit, !self.sessionEnding else { session.cancel(); return }
                self.permissionRestartPlanned = true
                self.permissionLogger.notice("Screen permission reset completed; relaunching for native consent")
                NSApp.terminate(nil)
            } catch {
                self.plannedRelaunch?.cancel(); self.plannedRelaunch = nil
                self.restoreStatusIcon()
                self.showError(error.localizedDescription)
                self.permissionFlowActive = false
            }
        }
    }

    @objc private func checkPermissionChange() { permissionLifecycle.checkForGrant() }

    private func restartAfterConsent() {
        guard !explicitQuit, !sessionEnding, !permissionRestartPlanned else { return }
        permissionFlowActive = true
        capture.finish(restoreFocus: false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.permissionLifecycle.ensureReadyForRestart()
                guard !self.explicitQuit, !self.sessionEnding else { self.permissionLifecycle.cancel(); return }
                self.permissionRestartPlanned = true
                self.permissionLogger.notice("Consent became available; restarting once to restore capture")
                NSApp.terminate(nil)
            } catch {
                self.permissionLifecycle.cancel()
                self.permissionFlowActive = false
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func sessionWillEnd() {
        sessionEnding = true
        permissionLifecycle.cancel()
        plannedRelaunch?.cancel()
    }

    @objc private func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot#使用")!) }
    @objc private func displaysChanged() {
        if capture.isActive { capture.finish() }
        capture.displaysChanged()
    }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot")!) }
    @objc private func quit() {
        explicitQuit = true
        permissionLifecycle.cancel()
        plannedRelaunch?.cancel()
        NSApp.terminate(nil)
    }

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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let reason = event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        let endReasons = [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut].map { UInt32($0) }
        let senderPID = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let origin = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ending = sessionEnding || reason.map { endReasons.contains($0) } == true || origin == "com.apple.loginwindow"
        func isSettings(_ id: String?) -> Bool {
            PermissionRelaunchPolicy.isSystemSettings(id)
        }
        let consentService = ["com.apple.coreservices.uiagent", "com.apple.SecurityAgent"].contains(origin ?? "")
        let settingsQuit = isSettings(origin) || consentService ||
            (origin == nil && (event == nil || isSettings(frontmost)))
        let preserve = !explicitQuit && !ending && (permissionRestartPlanned ||
            permissionLifecycle.preserveForQuit(explicitQuit: explicitQuit, sessionEnding: ending, settingsQuit: settingsQuit))
        if !preserve { permissionLifecycle.cancel(); plannedRelaunch?.cancel() }
        permissionLogger.notice("Application quitting; permission handoff: \(preserve, privacy: .public); origin: \(origin ?? "none", privacy: .public)")
        return .terminateNow
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !hotKey.isRegistered { hotKey.register() }
        permissionLifecycle.checkForGrant()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey.unregister(); capture.finish(restoreFocus: false) }
}
