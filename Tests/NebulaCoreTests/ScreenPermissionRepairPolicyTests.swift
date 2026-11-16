// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import NebulaCore

@Test func firstInstallAndStableSignaturesDoNotResetPermission() {
    var fresh = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: nil, isAdHoc: true,
                                             previouslyLaunched: false, savedPending: false)
    #expect(fresh.consumeBeforeConsent(granted: false) == false)
    var signed = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: "old", isAdHoc: false,
                                              previouslyLaunched: true, savedPending: true)
    #expect(signed.consumeBeforeConsent(granted: false) == false)
    var unknown = ScreenPermissionRepairPolicy(identity: nil, previousIdentity: "old", isAdHoc: true,
                                               previouslyLaunched: true, savedPending: true)
    #expect(unknown.consumeBeforeConsent(granted: false) == false)
}

@Test func changedAdHocBuildRepairsOnlyOnceAcrossRelaunches() {
    var policy = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: "old", isAdHoc: true,
                                               previouslyLaunched: true, savedPending: false)
    #expect(policy.pending)
    #expect(policy.consumeBeforeConsent(granted: true) == false)
    #expect(policy.pending)
    #expect(policy.consumeBeforeConsent(granted: false) == true)
    #expect(policy.consumeBeforeConsent(granted: false) == false)
    var relaunched = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: "new", isAdHoc: true,
                                                  previouslyLaunched: true, savedPending: policy.pending)
    #expect(relaunched.consumeBeforeConsent(granted: false) == false)
}

@Test func successfulCaptureClearsUpgradeRepairWithoutTouchingPermission() {
    var policy = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: "old", isAdHoc: true,
                                               previouslyLaunched: true, savedPending: false)
    policy.captureSucceeded()
    #expect(policy.consumeBeforeConsent(granted: false) == false)
}

@Test func legacyInstallAndUnattemptedUpgradeRetainOneRepairOpportunity() {
    let legacy = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: nil, isAdHoc: true,
                                               previouslyLaunched: true, savedPending: false)
    #expect(legacy.pending)
    var relaunched = ScreenPermissionRepairPolicy(identity: "new", previousIdentity: "new", isAdHoc: true,
                                                  previouslyLaunched: true, savedPending: legacy.pending)
    #expect(relaunched.consumeBeforeConsent(granted: false) == true)
}

@Test func nativeRequestWaitsWithoutAnAppAlertOrAutomaticRetry() {
    var prompt = ScreenPermissionPrompt()
    var requests = 0
    #expect(prompt.actionAfterDenial(using: { requests += 1; return false }) == .waitForSystem)
    #expect(prompt.actionAfterDenial(using: { requests += 1; return false }) == .openSettings)
    #expect(requests == 1)
    var granted = ScreenPermissionPrompt()
    #expect(granted.actionAfterDenial(using: { true }) == .retryCapture)
    #expect(granted.actionAfterDenial(using: { true }) == .openSettings)
}
