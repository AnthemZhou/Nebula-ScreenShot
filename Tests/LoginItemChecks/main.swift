// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: message, code: 1) }
}

// All service changes and approval actions are faked. Never register a test
// login item, open System Settings, request screen access or post system input.
actor FakeLoginService: LoginItemServicing {
    var state: LoginItemState
    var registrations = 0, removals = 0
    var fails = false
    private var holdRegistration = false, holdNextStatus = false
    private var pendingRegistration: CheckedContinuation<Void, Never>?
    private var pendingStatus: CheckedContinuation<Void, Never>?
    init(_ state: LoginItemState = .notRegistered) { self.state = state }
    func status() async -> LoginItemState {
        let snapshot = state
        if holdNextStatus {
            holdNextStatus = false
            await withCheckedContinuation { pendingStatus = $0 }
        }
        return snapshot
    }
    func register() async throws {
        registrations += 1
        if holdRegistration { await withCheckedContinuation { pendingRegistration = $0 } }
        if fails { throw NSError(domain: "Fixture registration failure", code: 42) }
        state = .enabled
    }
    func unregister() throws {
        removals += 1
        if fails { throw NSError(domain: "Fixture removal failure", code: 43) }
        state = .notRegistered
    }
    func change(_ state: LoginItemState) { self.state = state }
    func setFailure(_ value: Bool) { fails = value }
    func suspendRegistration() { holdRegistration = true }
    func registrationIsPending() -> Bool { pendingRegistration != nil }
    func releaseRegistration() { holdRegistration = false; pendingRegistration?.resume(); pendingRegistration = nil }
    func suspendNextStatus() { holdNextStatus = true }
    func statusIsPending() -> Bool { pendingStatus != nil }
    func releaseStatus() { pendingStatus?.resume(); pendingStatus = nil }
    func counts() -> (Int, Int) { (registrations, removals) }
}

@MainActor func runChecks() async throws {
    func waitUntil(_ ready: () async -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !(await ready()) {
            try check(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for a controlled service request")
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    let suite = "NebulaLoginFixture.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let backend = FakeLoginService()
    let controller = LoginItemController(service: backend, defaults: defaults, canConfigure: true)
    var approvals = 0
    controller.onApprovalNeeded = { approvals += 1 }
    await controller.configureDefaultIfNeeded()
    try check(controller.state == .enabled && !controller.isBusy && approvals == 0, "First bundled launch enables without UI")
    await controller.configureDefaultIfNeeded()
    try check(await backend.counts().0 == 1, "Repeated startup does not duplicate registration")
    await controller.toggle()
    try check(controller.state == .notRegistered, "Switch off unregisters the login item")
    let relaunched = LoginItemController(service: backend, defaults: UserDefaults(suiteName: suite)!, canConfigure: true)
    relaunched.onApprovalNeeded = { approvals += 1 }
    await relaunched.configureDefaultIfNeeded()
    try check(await backend.counts().0 == 1 && relaunched.state == .notRegistered, "Off survives relaunch/upgrade")
    await relaunched.toggle()
    try check(await backend.counts().0 == 2 && relaunched.state == .enabled, "Explicit enable can register again")
    await backend.change(.requiresApproval)
    await relaunched.refresh()
    try check(relaunched.state == .requiresApproval, "Read current System Settings choice")
    await relaunched.configureDefaultIfNeeded()
    try check(await backend.counts().0 == 2 && approvals == 0, "External disable is not overridden on launch")
    await relaunched.toggle()
    try check(await backend.counts().0 == 2 && approvals == 1, "Only explicit user click opens native approval settings")
    await backend.change(.notRegistered)
    await relaunched.configureDefaultIfNeeded()
    try check(await backend.counts().0 == 2 && relaunched.state == .notRegistered, "External removal is also preserved")
    print("PASS: default once, manual off/on, upgrade persistence and System Settings authority")

    for existing in [LoginItemState.enabled, .requiresApproval] {
        defaults.removePersistentDomain(forName: suite)
        let service = FakeLoginService(existing)
        let current = LoginItemController(service: service, defaults: defaults, canConfigure: true)
        current.onApprovalNeeded = { approvals += 1 }
        await current.configureDefaultIfNeeded()
        try check(await service.counts().0 == 0 && current.state == existing, "Respect pre-existing login items without re-registering")
    }
    defaults.removePersistentDomain(forName: suite)
    let failureService = FakeLoginService()
    await failureService.setFailure(true)
    let failure = LoginItemController(service: failureService, defaults: defaults, canConfigure: true)
    await failure.configureDefaultIfNeeded()
    try check(failure.state == .notRegistered && failure.lastError != nil && !failure.isBusy, "Failures never look enabled or stay busy")
    await failure.configureDefaultIfNeeded()
    try check(await failureService.counts().0 == 1, "Registration error cannot loop across permission relaunches")
    await failureService.setFailure(false)
    await failure.toggle()
    try check(failure.state == .enabled && failure.lastError == nil, "Explicit retry recovers")
    await failureService.setFailure(true)
    await failure.toggle()
    try check(failure.state == .enabled && failure.lastError != nil, "Unregister failure preserves real enabled state")
    print("PASS: pre-existing states, truthful error state and explicit retry")

    defaults.removePersistentDomain(forName: suite)
    let unbundled = LoginItemController(service: backend, defaults: defaults, canConfigure: false)
    await unbundled.configureDefaultIfNeeded(); await unbundled.toggle()
    try check(defaults.persistentDomain(forName: suite)?.isEmpty != false, "Unbundled tools never consume the app's default or register")
    let slowService = FakeLoginService()
    await slowService.suspendRegistration()
    let slow = LoginItemController(service: slowService, defaults: defaults, canConfigure: true)
    let configure = Task { await slow.configureDefaultIfNeeded() }
    try await waitUntil { await slowService.registrationIsPending() }
    await slow.toggle() // Reject duplicate mutation while the first request is pending.
    // Keep registration pending until another main-actor task actually runs.
    // No assumption about timer granularity, VM speed or scheduler throughput.
    let heartbeat = Task { @MainActor in slow.isBusy }
    try check(await heartbeat.value, "Main actor executes while registration is still pending")
    try check(await slowService.counts().0 == 1, "Pending registration suppresses duplicate mutations")
    await slowService.releaseRegistration()
    await configure.value
    try check(slow.state == .enabled && !slow.isBusy, "Explicit service completion updates the controller")
    await slowService.suspendNextStatus()
    let refresh = Task { await slow.refresh() }
    try await waitUntil { await slowService.statusIsPending() }
    await slow.toggle()
    await slowService.releaseStatus()
    await refresh.value
    try check(slow.state == .notRegistered, "A stale menu refresh cannot restore enabled state after turning off")
    print("PASS: unbundled safety, responsive startup, duplicate suppression and refresh race")

    func event(_ id: AEEventID = kAEOpenApplication, kind: OSType? = nil) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let kind { event.setParam(NSAppleEventDescriptor(enumCode: kind), forKeyword: keyAEPropData) }
        return event
    }
    for launch in [event(kind: keyAELaunchedAsLogInItem), event(kind: keyAELaunchedAsServiceItem)] {
        try check(ApplicationLaunchContext.isBackground(launch), "Native login/service event is identified")
        for first in [true, false] {
            try check(!ApplicationLaunchContext.showsWelcome(firstLaunch: first, captureRequested: false, event: launch), "Login must never show the main window")
            try check(!ApplicationLaunchContext.showsWelcomeOnReopen(launchFinished: true, event: launch), "Background reopen remains silent")
        }
    }
    try check(!ApplicationLaunchContext.showsWelcome(firstLaunch: true, captureRequested: false, event: nil), "Unknown launch context stays quiet")
    try check(!ApplicationLaunchContext.showsWelcomeOnReopen(launchFinished: true, event: nil), "Unknown reopen stays quiet")
    try check(ApplicationLaunchContext.showsWelcome(firstLaunch: true, captureRequested: false, event: event()), "Known manual first launch may show About")
    try check(!ApplicationLaunchContext.showsWelcome(firstLaunch: true, captureRequested: true, event: event()), "Queued shortcut takes priority over About")
    try check(!ApplicationLaunchContext.showsWelcomeOnReopen(launchFinished: false, event: event(kAEReopenApplication)), "Startup never opens a window from an early reopen")
    try check(ApplicationLaunchContext.showsWelcomeOnReopen(launchFinished: true, event: event(kAEReopenApplication)), "Explicit Finder reopen retains About")
    try check(NSApp?.windows.allSatisfy { !$0.isVisible } != false, "Checks never show windows")
    print("PASS: native login/service and unknown launches stay windowless; manual launch and first shortcut routing preserved")
}

Task { @MainActor in
    do { try await runChecks(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
RunLoop.main.run()
