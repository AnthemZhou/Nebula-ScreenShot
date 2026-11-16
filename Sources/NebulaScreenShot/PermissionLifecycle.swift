// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore
import OSLog

@MainActor protocol ConsentRelaunchSession: AnyObject {
    var isRunning: Bool { get }
    func waitUntilReady() async throws
    func cancel()
}

extension AppRelauncher.Session: ConsentRelaunchSession {}

@MainActor final class PermissionLifecycle {
    private var policy = PermissionRelaunchPolicy()
    private var session: (any ConsentRelaunchSession)?
    private let checkAccess: () -> Bool
    private let makeSession: @MainActor () throws -> any ConsentRelaunchSession
    private let logger = Logger(subsystem: AppRelauncher.bundleIdentifier, category: "Permission")
    var isWaiting: Bool { policy.isWaiting }
    var onGranted: (() -> Void)?

    init(checkAccess: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
         makeSession: @escaping @MainActor () throws -> any ConsentRelaunchSession = { try AppRelauncher.prepare(.resume) }) {
        self.checkAccess = checkAccess
        self.makeSession = makeSession
    }

    func prepare() async throws {
        // Callers enter after denied access. Do not poll Core Graphics while the
        // native consent dialog is opening, closing or handing off to Settings.
        policy.begin(granted: false)
        if session?.isRunning != true {
            session?.cancel()
            session = try makeSession()
            try await session?.waitUntilReady()
        }
        logger.notice("Consent handoff armed; no permission polling while native UI is pending")
    }

    func checkForGrant() {
        guard policy.isWaiting else { return }
        let granted = checkAccess()
        logger.notice("Checking consent after Settings exit or user retry; granted: \(granted, privacy: .public)")
        guard policy.observe(granted: granted) else { return }
        onGranted?()
    }

    func ensureReadyForRestart() async throws {
        if session?.isRunning != true {
            session?.cancel()
            session = try makeSession()
            try await session?.waitUntilReady()
        }
    }

    func preserveForQuit(explicitQuit: Bool, sessionEnding: Bool, settingsQuit: Bool) -> Bool {
        policy.preserveForQuit(explicitQuit: explicitQuit, sessionEnding: sessionEnding, settingsQuit: settingsQuit)
    }

    func cancel(file: StaticString = #fileID, line: UInt = #line) {
        if policy.isWaiting {
            logger.notice("Consent handoff cancelled at \(String(describing: file), privacy: .public):\(line, privacy: .public)")
        }
        policy.cancel()
        session?.cancel(); session = nil
    }
}
