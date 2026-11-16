// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Serializes explicit consent and ScreenCaptureKit's implicit permission prompt.
public struct ScreenPermissionPrompt {
    public enum CaptureAction: Equatable { case capture, requestConsent, waitForConsent }
    public enum DeniedAction: Equatable {
        case retryCapture, waitForSystem, openSettings
    }
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

    /// nil means this process has already requested consent, not that access was denied.
    public mutating func requestOnce(using request: () -> Bool) -> Bool? {
        guard !requested else { return nil }
        requested = true
        let granted = request()
        isWaiting = !granted
        return granted
    }

    /// A pending native prompt must never be followed by a second app-owned alert.
    public mutating func actionAfterDenial(using request: () -> Bool) -> DeniedAction {
        switch requestOnce(using: request) {
        case true?: return .retryCapture
        case false?: return .waitForSystem
        case nil: return .openSettings
        }
    }
}
