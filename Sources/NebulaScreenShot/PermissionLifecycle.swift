// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class PermissionLifecycle {
    private var policy = PermissionRelaunchPolicy()
    private var session: AppRelauncher.Session?
    private var probe: Task<Void, Never>?
    var onGranted: (() -> Void)?

    func prepare() async throws {
        policy.begin(granted: CGPreflightScreenCaptureAccess())
        if session?.isRunning != true {
            session?.cancel()
            session = try AppRelauncher.prepare(.resume)
            try await session?.waitUntilReady()
        }
        guard probe == nil else { return }
        probe = Task { @MainActor [weak self] in
            for _ in 0..<1200 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.policy.isWaiting else { return }
                self.checkForGrant()
            }
            self?.probe = nil
        }
    }

    func checkForGrant() {
        guard policy.isWaiting else { return }
        guard policy.observe(granted: CGPreflightScreenCaptureAccess()) else { return }
        probe?.cancel(); probe = nil
        onGranted?()
    }

    func ensureReadyForRestart() async throws {
        if session?.isRunning != true {
            session?.cancel()
            session = try AppRelauncher.prepare(.resume)
            try await session?.waitUntilReady()
        }
    }

    func preserveForQuit(explicitQuit: Bool, sessionEnding: Bool, settingsQuit: Bool) -> Bool {
        policy.preserveForQuit(explicitQuit: explicitQuit, sessionEnding: sessionEnding, settingsQuit: settingsQuit)
    }

    func cancel() {
        policy.cancel()
        probe?.cancel(); probe = nil
        session?.cancel(); session = nil
    }
}
