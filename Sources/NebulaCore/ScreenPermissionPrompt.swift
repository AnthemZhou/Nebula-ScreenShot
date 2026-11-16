// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Serializes explicit consent and ScreenCaptureKit's implicit permission prompt.
public struct ScreenPermissionPrompt {
    public enum CaptureAction: Equatable { case capture, requestConsent, waitForConsent }
    private var requested = false
    public private(set) var isWaiting = false

    public init() {}

    public func actionBeforeCapture(granted: Bool) -> CaptureAction {
        // A grant during this session is handled by the consent restart watcher.
        if isWaiting { return .waitForConsent }
        if granted { return .capture }
        return requested ? .waitForConsent : .requestConsent
    }

    public mutating func captureDenied() {
        // ScreenCaptureKit may already have shown the native dialog. Neither a
        // second CGRequest call nor a reset/relaunch should follow that denial.
        requested = true
        isWaiting = true
    }

    public mutating func captureSucceeded() { isWaiting = false }

    /// Claim before starting the asynchronous ScreenCaptureKit request. Repeated
    /// shortcuts/settings actions may open Settings but cannot request again.
    public mutating func beginRequest() -> Bool {
        guard !requested else { return false }
        requested = true
        isWaiting = true
        return true
    }

    /// Only a successful access operation completes consent; initiating a native
    /// request is not evidence that the user has granted permission.
    public mutating func completeRequest(granted: Bool) { isWaiting = !granted }
}
