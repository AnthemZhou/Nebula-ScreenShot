// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import NebulaCore

/// Persists the repair claim before resetting/relaunching, preventing restart loops.
final class ScreenPermissionUpgrade {
    private let defaults: UserDefaults
    private var policy: ScreenPermissionRepairPolicy
    private static let identityKey = "screenPermission.codeIdentity"
    private static let pendingKey = "screenPermission.upgradeRepairPending"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let signature = Self.signature()
        policy = ScreenPermissionRepairPolicy(identity: signature?.identity,
            previousIdentity: defaults.string(forKey: Self.identityKey), isAdHoc: signature?.adHoc == true,
            previouslyLaunched: defaults.bool(forKey: "hasLaunched"),
            savedPending: defaults.bool(forKey: Self.pendingKey))
        if let signature { defaults.set(signature.identity, forKey: Self.identityKey) }
        persist()
    }

    func consumeAfterCaptureDenial() -> Bool {
        let shouldRepair = policy.consumeAfterCaptureDenial()
        persist()
        return shouldRepair
    }

    func clear() {
        guard policy.pending else { return }
        policy.captureSucceeded()
        persist()
    }

    private func persist() { defaults.set(policy.pending, forKey: Self.pendingKey) }

    private static func signature() -> (identity: String, adHoc: Bool)? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let hash = info[kSecCodeInfoUnique as String] as? Data,
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber else { return nil }
        return (hash.map { String(format: "%02x", $0) }.joined(),
                flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0)
    }
}
