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

    /// Recent macOS versions send the consent quit from the Privacy & Security extension.
    public static func isSystemSettings(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier == "com.apple.settings.PrivacySecurity.extension" ||
            identifier.hasPrefix("com.apple.systempreferences") ||
            identifier.hasPrefix("com.apple.systemsettings")
    }

    /// LaunchServices may still report the exited parent as running for a short time.
    /// A successful handoff requires a different, live application process.
    public static func isReplacementProcess(_ pid: Int32, exitedPID: Int32, helperPID: Int32,
                                            isTerminated: Bool, isAlive: Bool) -> Bool {
        pid > 1 && pid != exitedPID && pid != helperPID && !isTerminated && isAlive
    }
}
