// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore
import OSLog
import Carbon
import ScreenCaptureKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKey()
    private let capture = CaptureCoordinator()
    private var welcome: WelcomeWindow?
    private var permissionFlowActive = false
    private var permissionPrompt = ScreenPermissionPrompt()
    private let permissionLifecycle = PermissionLifecycle()
    private let permissionProgress = PermissionProgressHUD()
    private var permissionRecoveryTask: Task<Void, Never>?
    private var plannedRelaunch: AppRelauncher.Session?
    private var permissionRestartPlanned = false
    private var explicitQuit = false
    private var sessionEnding = false
    private var launchFinished = false
    private var captureRequestedDuringLaunch = false
    private var permissionUpgrade: ScreenPermissionUpgrade!
    private var permissionRepairItem: NSMenuItem!
    private let permissionLogger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Permission")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotKey.onPress = { [weak self] in self?.captureFromShortcut() }
        hotKey.register()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlassMetalRenderer.prewarm()
        configureMenu()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        permissionUpgrade = ScreenPermissionUpgrade()
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        capture.onError = { [weak self] in self?.showError($0) }
        capture.onPermissionNeeded = { [weak self] in self?.showPermissionHelp() }
        capture.onCaptureReady = { [weak self] in
            self?.permissionPrompt.captureSucceeded()
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
        if !CommandLine.arguments.contains("--repair-screen-permission") &&
           !CommandLine.arguments.contains("--request-screen-permission") { prepareCaptureIfAllowed() }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationDeactivated(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionWillEnd),
            name: NSWorkspace.willPowerOffNotification, object: nil)
        launchFinished = true
        permissionLogger.notice("Application ready; shortcut registered: \(self.hotKey.isRegistered, privacy: .public); active: \(NSApp.isActive, privacy: .public)")
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
            beginAuthorizedCapture()
        } else if firstLaunch && !captureRequestedDuringLaunch {
            showWelcome()
        }
        if captureRequestedDuringLaunch {
            captureRequestedDuringLaunch = false
            captureFromShortcut()
        }
    }

    private func configureMenu() {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: L10n.text("关于 Nebula ScreenShot", "About Nebula ScreenShot"), action: #selector(showWelcome), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L10n.text("退出 Nebula ScreenShot", "Quit Nebula ScreenShot"), action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = submenu
        appMenu.addItem(appItem)
        NSApp.mainMenu = appMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        restoreStatusIcon()
        let menu = NSMenu()
        let title = NSMenuItem(title: "Nebula ScreenShot", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let captureItem = NSMenuItem(title: L10n.text("区域截图  \(HotKey.displayString)", "Capture Area  \(HotKey.displayString)"), action: #selector(beginCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        permissionRepairItem = NSMenuItem(title: L10n.text("修复屏幕录制授权…", "Repair Screen Recording Permission…"), action: #selector(reauthorizeScreenPermission), keyEquivalent: "")
        permissionRepairItem.isHidden = true
        menu.addItem(permissionRepairItem)
        menu.addItem(withTitle: L10n.text("试用标注…", "Try Annotations…"), action: #selector(beginDemo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("关于 Nebula ScreenShot…", "About Nebula ScreenShot…"), action: #selector(showWelcome), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: L10n.text("设置", "Settings"), action: nil, keyEquivalent: "")
        let settings = NSMenu()
        settings.addItem(withTitle: L10n.text("屏幕录制权限…", "Screen Recording Permission…"), action: #selector(openScreenPermission), keyEquivalent: "")
        settings.addItem(withTitle: L10n.text("重新授权屏幕录制…", "Reauthorize Screen Recording…"), action: #selector(reauthorizeScreenPermission), keyEquivalent: "")
        settings.addItem(withTitle: L10n.text("键盘快捷键设置…", "Keyboard Shortcut Settings…"), action: #selector(openKeyboardSettings), keyEquivalent: "")
        settings.addItem(withTitle: L10n.text("重新检测快捷键…", "Check Shortcut…"), action: #selector(checkShortcut), keyEquivalent: "")
        for item in settings.items { item.target = self }
        settingsItem.submenu = settings
        menu.addItem(settingsItem)
        menu.addItem(withTitle: L10n.text("使用说明", "Help"), action: #selector(openHelp), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("GitHub 开源仓库", "GitHub Repository"), action: #selector(openRepository), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("退出 Nebula ScreenShot", "Quit Nebula ScreenShot"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func restoreStatusIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nebula ScreenShot")
        statusItem.button?.toolTip = "Nebula ScreenShot · \(HotKey.displayString)"
    }

    @objc private func beginCapture() {
        guard !permissionFlowActive else { permissionProgress.showCurrent(); return }
        welcome?.window?.orderOut(nil)
        beginAuthorizedCapture(afterMenuDismissal: true)
    }

    private func captureFromShortcut() {
        guard launchFinished else {
            captureRequestedDuringLaunch = true
            permissionLogger.notice("Capture shortcut queued until launch completes")
            return
        }
        statusItem.menu?.cancelTracking()
        welcome?.window?.orderOut(nil)
        beginAuthorizedCapture()
    }

    private func beginAuthorizedCapture(afterMenuDismissal: Bool = false) {
        guard !permissionFlowActive, !permissionRestartPlanned, !capture.isActive else {
            if permissionFlowActive || permissionRestartPlanned { permissionProgress.showCurrent() }
            permissionLogger.notice("Capture request ignored; permission work: \(self.permissionFlowActive, privacy: .public); restarting: \(self.permissionRestartPlanned, privacy: .public); capturing: \(self.capture.isActive, privacy: .public)")
            return
        }
        if permissionPrompt.isWaiting {
            permissionLifecycle.checkForGrant()
            if !permissionRestartPlanned { openScreenPermissionSettings() }
            return
        }
        let granted = CGPreflightScreenCaptureAccess()
        switch permissionPrompt.actionBeforeCapture(granted: granted) {
        case .capture: capture.begin(afterMenuDismissal: afterMenuDismissal)
        case .requestConsent: requestNativePermission(retryCaptureIfGranted: true)
        case .waitForConsent:
            permissionLifecycle.checkForGrant()
            if !permissionRestartPlanned { requestNativePermission() }
        }
    }

    private func prepareCaptureIfAllowed() {
        // A changed build must resolve its permission at the user's first capture,
        // not indirectly through background ScreenCaptureKit metadata warmup.
        guard !permissionFlowActive, !permissionPrompt.isWaiting, !permissionUpgrade.isPending else { return }
        capture.prepare()
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
        if permissionPrompt.isWaiting || CGPreflightScreenCaptureAccess() { openScreenPermissionSettings() }
        else { requestNativePermission() }
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
            alert.messageText = L10n.text("快捷键暂时无法注册", "Unable to Register Shortcut")
            alert.informativeText = L10n.text("请退出占用此组合的其他截图应用，再重新检测。也可从菜单栏开始截图。\n错误代码：\(hotKey.registrationStatus)", "Quit other screenshot apps using this shortcut, then try again. You can also capture from the menu bar.\nError code: \(hotKey.registrationStatus)")
        } else {
            alert.messageText = L10n.text("快捷键已注册：\(HotKey.displayString)", "Shortcut Registered: \(HotKey.displayString)")
            alert.informativeText = L10n.text("按下快捷键即可选择截图区域。首次使用需允许屏幕录制。", "Press the shortcut to select an area. Allow screen recording on first use.")
            if conflict == true {
                alert.informativeText += L10n.text("\n\n已以独占方式注册。若仍出现系统截屏面板，请在键盘快捷键 → 截屏中调整“截屏和录制选项”。", "\n\nRegistered exclusively. If the system screenshot panel still appears, adjust “Screenshot and recording options” in Keyboard Shortcuts → Screenshots.")
            }
        }
        alert.addButton(withTitle: L10n.text("好", "OK"))
        if conflict == true || hotKey.registrationStatus != noErr { alert.addButton(withTitle: L10n.text("快捷键设置", "Shortcut Settings")) }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openKeyboardSettings() }
    }

    private func showPermissionHelp() {
        guard !permissionFlowActive else { return }
        permissionRepairItem.isHidden = false
        statusItem.button?.toolTip = L10n.text("屏幕录制权限待授权 · 可在菜单中修复授权", "Screen recording permission required · Repair available in the menu")
        permissionPrompt.captureDenied()
        permissionLogger.notice("ScreenCaptureKit denied access; observing existing native consent without another request")
        observePendingConsent()
    }

    private func observePendingConsent() {
        permissionFlowActive = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.permissionFlowActive = false }
            do { try await self.permissionLifecycle.prepare() }
            catch { self.permissionLifecycle.cancel(); self.showError(error.localizedDescription) }
        }
    }

    private func requestNativePermission(retryCaptureIfGranted: Bool = false) {
        guard !permissionFlowActive, !permissionRestartPlanned else { return }
        permissionFlowActive = true
        // Repair only before the first prompt. Resetting after ScreenCaptureKit
        // has prompted causes the same native dialog to appear a second time.
        if !permissionPrompt.isWaiting && permissionUpgrade.consumeBeforeConsent(granted: CGPreflightScreenCaptureAccess()) {
            permissionLogger.notice("Repairing outdated ad-hoc authorization before requesting native consent")
            recoverScreenPermission()
            return
        }
        permissionProgress.show(.preparing)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.permissionFlowActive = false; self.permissionProgress.hide() }
            do {
                // The helper must be watching before native consent can terminate this app.
                try await self.permissionLifecycle.prepare()
                guard !self.explicitQuit, !self.sessionEnding else { self.permissionLifecycle.cancel(); return }
                guard self.permissionPrompt.beginRequest() else {
                    self.permissionProgress.hide()
                    self.openScreenPermissionSettings()
                    return
                }
                self.permissionLogger.notice("Requesting native consent through ScreenCaptureKit once; automatic relaunch armed")
                // Never stack an app permission message over the native dialog.
                self.permissionProgress.hide()
                do {
                    // Use the same framework as capture. Do not combine its native
                    // consent UI with the legacy Core Graphics permission dialog.
                    // This enumerates content only; no screen pixels are recorded.
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    guard !self.explicitQuit, !self.sessionEnding, !self.permissionRestartPlanned else { return }
                    self.permissionPrompt.completeRequest(granted: true)
                    self.permissionLogger.notice("ScreenCaptureKit consent request completed with access")
                    self.permissionLifecycle.cancel()
                    if retryCaptureIfGranted { self.capture.begin() }
                } catch {
                    guard ScreenCaptureFailure.isPermissionDenied(error) else { throw error }
                    self.permissionPrompt.completeRequest(granted: false)
                    self.permissionRepairItem.isHidden = false
                    self.permissionLogger.notice("Native consent pending; no second request, retry or automatic Settings launch")
                }
                // The native dialog owns its Open Settings button. Opening Settings
                // here as well races the system's dialog dismissal/activation.
            } catch {
                self.permissionLifecycle.cancel()
                self.permissionProgress.hide()
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
        permissionProgress.show(.recovering)
        statusItem.button?.toolTip = L10n.text("正在重新授权屏幕录制…", "Reauthorizing screen recording…")
        permissionRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await ScreenPermissionRecovery.resetAndPrepareRelaunch()
                self.plannedRelaunch = session
                try await session.waitUntilReady()
                guard !self.explicitQuit, !self.sessionEnding else { session.cancel(); return }
                self.permissionRestartPlanned = true
                self.permissionProgress.show(.restarting)
                self.permissionLogger.notice("Screen permission reset completed; relaunching for native consent")
                NSApp.terminate(nil)
            } catch {
                self.plannedRelaunch?.cancel(); self.plannedRelaunch = nil
                self.permissionProgress.hide()
                self.restoreStatusIcon()
                self.permissionFlowActive = false
                if !(error is CancellationError), !self.explicitQuit, !self.sessionEnding {
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func applicationDeactivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              PermissionRelaunchPolicy.isSystemSettings(application.bundleIdentifier) else { return }
        permissionLifecycle.checkForGrant()
    }

    private func restartAfterConsent() {
        guard !explicitQuit, !sessionEnding, !permissionRestartPlanned else { return }
        permissionRestartPlanned = true
        permissionFlowActive = true
        permissionProgress.show(.restarting)
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
                self.permissionRestartPlanned = false
                self.permissionFlowActive = false
                self.permissionProgress.hide()
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func sessionWillEnd() {
        // macOS also posts willPowerOff while handling Settings' consent quit.
        // Keep that narrowly identified handoff alive; a real logout/shutdown
        // or an unrelated notification must still cancel the helper.
        let context = currentQuitContext()
        if permissionLifecycle.shouldIgnorePowerOff(quitOrigin: context.origin,
                                                    systemQuit: context.systemQuit) {
            permissionLogger.notice("Settings consent quit is not a session shutdown; preserving automatic relaunch")
            return
        }
        sessionEnding = true
        permissionLifecycle.cancel()
        plannedRelaunch?.cancel()
    }

    @objc private func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot#使用")!) }
    @objc private func displaysChanged() {
        if capture.isActive { capture.finish() }
        capture.displaysChanged(prepare: !permissionFlowActive && !permissionPrompt.isWaiting && !permissionUpgrade.isPending)
    }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: "https://github.com/AnthemZhou/Nebula-ScreenShot")!) }
    @objc private func quit() {
        explicitQuit = true
        permissionRecoveryTask?.cancel()
        permissionLifecycle.cancel()
        plannedRelaunch?.cancel()
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Nebula ScreenShot"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("好", "OK"))
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func currentQuitContext() -> (event: NSAppleEventDescriptor?, reason: UInt32?, origin: String?, systemQuit: Bool) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let reason = event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        let endReasons = [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut].map { UInt32($0) }
        let senderPID = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let origin = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return (event, reason, origin, reason.map { endReasons.contains($0) } == true || origin == "com.apple.loginwindow")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let context = currentQuitContext()
        let (event, reason, origin) = (context.event, context.reason, context.origin)
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ending = sessionEnding || context.systemQuit
        func isSettings(_ id: String?) -> Bool {
            PermissionRelaunchPolicy.isSystemSettings(id)
        }
        let consentService = ["com.apple.coreservices.uiagent", "com.apple.SecurityAgent"].contains(origin ?? "")
        let settingsQuit = isSettings(origin) || consentService ||
            (origin == nil && (event == nil || isSettings(frontmost)))
        let preserve = !explicitQuit && !ending && (permissionRestartPlanned ||
            permissionLifecycle.preserveForQuit(explicitQuit: explicitQuit, sessionEnding: ending, settingsQuit: settingsQuit))
        let wasWaiting = permissionLifecycle.isWaiting
        if !preserve { permissionLifecycle.cancel(); plannedRelaunch?.cancel() }
        permissionLogger.notice("Application quitting; permission handoff: \(preserve, privacy: .public); origin: \(origin ?? "none", privacy: .public); waiting: \(wasWaiting, privacy: .public); explicit: \(self.explicitQuit, privacy: .public); session ending: \(ending, privacy: .public); reason: \(reason ?? 0, privacy: .public)")
        return .terminateNow
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !hotKey.isRegistered { hotKey.register() }
        capture.restoreKeyboardFocusIfNeeded()
    }
    func applicationDidResignActive(_ notification: Notification) { capture.applicationLostFocus() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        permissionRecoveryTask?.cancel()
        permissionProgress.hide()
        hotKey.unregister()
        capture.finish(restoreFocus: false)
    }
}
