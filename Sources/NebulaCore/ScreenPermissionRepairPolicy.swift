// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A known ad-hoc upgrade may repair denied authorization before any native prompt.
public struct ScreenPermissionRepairPolicy {
    public private(set) var pending: Bool

    public init(identity: String?, previousIdentity: String?, isAdHoc: Bool,
                previouslyLaunched: Bool, savedPending: Bool) {
        guard let identity, isAdHoc else { pending = false; return }
        pending = identity == previousIdentity ? savedPending : previouslyLaunched
    }

    public mutating func consumeBeforeConsent(granted: Bool) -> Bool {
        guard pending, !granted else { return false }
        pending = false
        return true
    }

    public mutating func captureSucceeded() { pending = false }
}
