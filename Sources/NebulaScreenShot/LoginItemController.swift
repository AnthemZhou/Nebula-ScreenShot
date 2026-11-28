// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon
import ServiceManagement
import OSLog

enum LoginItemState: String, Sendable { case notRegistered, enabled, requiresApproval, notFound }

protocol LoginItemServicing: Sendable {
    func status() async -> LoginItemState
    func register() async throws
    func unregister() async throws
}

// Service Management can involve IPC. Keep it off the main actor so launch,
// menus and the already-registered capture shortcut remain responsive.
actor SystemLoginItemService: LoginItemServicing {
    func status() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor final class LoginItemController {
    private static let configuredKey = "launchAtLoginDefaultConfigured"
    private let service: any LoginItemServicing
    private let defaults: UserDefaults
    let canConfigure: Bool
    private(set) var state: LoginItemState = .notRegistered
    private(set) var isBusy = false
    private(set) var lastError: String?
    private var operation = 0
    var onChange: (() -> Void)?
    var onApprovalNeeded: () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "LoginItem")

    init(service: any LoginItemServicing = SystemLoginItemService(), defaults: UserDefaults = .standard,
         canConfigure: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.service = service; self.defaults = defaults; self.canConfigure = canConfigure
    }

    func configureDefaultIfNeeded() async {
        guard !isBusy, canConfigure else { return }
        operation += 1; isBusy = true; onChange?()
        defer { isBusy = false; onChange?() }
        state = await service.status()
        guard !defaults.bool(forKey: Self.configuredKey) else { return }
        // Apply the default once, not on each version/permission relaunch. The
        // system remains authoritative after either Settings or our menu changes it.
        // Mark before IPC so a rejected attempt cannot create a launch retry loop.
        defaults.set(true, forKey: Self.configuredKey)
        guard state != .enabled, state != .requiresApproval else { return }
        do { try await service.register() }
        catch { record(error) }
        state = await service.status()
        logger.notice("Default login item configured; state: \(String(describing: self.state), privacy: .public)")
    }

    func refresh() async {
        guard !isBusy, canConfigure else { return }
        let currentOperation = operation
        let latest = await service.status()
        guard !isBusy, operation == currentOperation else { return }
        state = latest
        if state == .enabled { lastError = nil }
        onChange?()
    }

    func toggle() async {
        guard !isBusy, canConfigure else { return }
        operation += 1; isBusy = true; lastError = nil; onChange?()
        defer { isBusy = false; onChange?() }
        defaults.set(true, forKey: Self.configuredKey)
        state = await service.status()
        // Never bypass a choice made in System Settings. Open its native control
        // only after an explicit click, never as a side effect of background launch.
        if state == .requiresApproval { onApprovalNeeded(); return }
        do {
            if state == .enabled { try await service.unregister() }
            else { try await service.register() }
        } catch { record(error) }
        state = await service.status()
        if state == .requiresApproval { lastError = nil; onApprovalNeeded() }
        logger.notice("Login item changed; state: \(String(describing: self.state), privacy: .public)")
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
        let error = error as NSError
        logger.error("Login item operation failed: \(error.domain, privacy: .public) / \(error.code, privacy: .public)")
    }
}

enum ApplicationLaunchContext {
    static func isBackground(_ event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventClass == kCoreEventClass, event?.eventID == kAEOpenApplication,
              let kind = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue else { return false }
        return kind == keyAELaunchedAsLogInItem || kind == keyAELaunchedAsServiceItem
    }

    static func showsWelcome(firstLaunch: Bool, captureRequested: Bool, event: NSAppleEventDescriptor?) -> Bool {
        // Unknown launch contexts also stay quiet. Only a known manual first
        // launch may show About; explicit menu actions remain available anytime.
        firstLaunch && !captureRequested && event?.eventClass == kCoreEventClass &&
            event?.eventID == kAEOpenApplication && !isBackground(event)
    }

    static func showsWelcomeOnReopen(launchFinished: Bool, event: NSAppleEventDescriptor?) -> Bool {
        launchFinished && event?.eventClass == kCoreEventClass && event?.eventID == kAEReopenApplication
    }
}
