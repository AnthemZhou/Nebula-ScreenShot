// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Requests initial OS consent once per process. This is not a capture-access gate;
/// ScreenCaptureKit remains the authority on whether a capture can proceed.
public struct ScreenPermissionPrompt {
    public enum DeniedAction: Equatable {
        case retryCapture, waitForSystem, openSettings
    }
    private var requested = false

    public init() {}

    /// nil means this process has already requested consent, not that access was denied.
    public mutating func requestOnce(using request: () -> Bool) -> Bool? {
        guard !requested else { return nil }
        requested = true
        return request()
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
