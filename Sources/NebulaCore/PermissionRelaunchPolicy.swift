// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Tracks a native consent session, not general app liveness.
public struct PermissionRelaunchPolicy {
    public private(set) var isWaiting = false
    private var observedDenial = false

    public init() {}

    public mutating func begin(granted: Bool) {
        guard !isWaiting else { return }
        isWaiting = true
        observedDenial = !granted
    }

    public mutating func observe(granted: Bool) -> Bool {
        guard isWaiting else { return false }
        if !granted { observedDenial = true; return false }
        guard observedDenial else { return false }
        isWaiting = false
        return true
    }

    public func preserveForQuit(explicitQuit: Bool, sessionEnding: Bool, settingsQuit: Bool) -> Bool {
        isWaiting && !explicitQuit && !sessionEnding && settingsQuit
    }

    public mutating func cancel() { isWaiting = false; observedDenial = false }

    /// kqueue NOTE_EXITSTATUS supplies a wait(2) status. Force quit/signals must stay quit.
    public static func isCleanExit(_ status: Int) -> Bool { status == 0 }
}
