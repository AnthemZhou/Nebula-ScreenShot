// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Requests initial OS consent once per process. This is not a capture-access gate;
/// ScreenCaptureKit remains the authority on whether a capture can proceed.
public struct ScreenPermissionPrompt {
    private var requested = false

    public init() {}

    /// nil means this process has already requested consent, not that access was denied.
    public mutating func requestOnce(using request: () -> Bool) -> Bool? {
        guard !requested else { return nil }
        requested = true
        return request()
    }
}
