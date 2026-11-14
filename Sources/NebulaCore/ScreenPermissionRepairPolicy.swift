// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Only an actual capture denial may consume this one-time ad-hoc upgrade repair.
public struct ScreenPermissionRepairPolicy {
    public private(set) var pending: Bool

    public init(identity: String?, previousIdentity: String?, isAdHoc: Bool,
                previouslyLaunched: Bool, savedPending: Bool) {
        guard let identity, isAdHoc else { pending = false; return }
        pending = identity == previousIdentity ? savedPending : previouslyLaunched
    }

    public mutating func consumeAfterCaptureDenial() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }

    public mutating func captureSucceeded() { pending = false }
}
