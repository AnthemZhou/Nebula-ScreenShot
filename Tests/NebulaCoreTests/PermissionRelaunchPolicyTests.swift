// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import NebulaCore

@Test func consentGrantRequestsOnlyOneRestart() {
    var policy = PermissionRelaunchPolicy()
    policy.begin(granted: false)
    #expect(policy.observe(granted: false) == false)
    #expect(policy.observe(granted: true) == true)
    #expect(policy.observe(granted: true) == false)
}

@Test func existingPermissionDoesNotProduceARestartLoop() {
    var policy = PermissionRelaunchPolicy()
    policy.begin(granted: true)
    #expect(policy.observe(granted: true) == false)
    #expect(policy.observe(granted: false) == false)
    #expect(policy.observe(granted: true) == true)
}

@Test func explicitQuitShutdownAndUnrelatedQuitCancelTheHandoff() {
    var policy = PermissionRelaunchPolicy()
    policy.begin(granted: false)
    #expect(policy.preserveForQuit(explicitQuit: false, sessionEnding: false, settingsQuit: true))
    #expect(!policy.preserveForQuit(explicitQuit: true, sessionEnding: false, settingsQuit: true))
    #expect(!policy.preserveForQuit(explicitQuit: false, sessionEnding: true, settingsQuit: true))
    #expect(!policy.preserveForQuit(explicitQuit: false, sessionEnding: false, settingsQuit: false))
    policy.cancel()
    #expect(policy.observe(granted: true) == false)
    #expect(!policy.preserveForQuit(explicitQuit: false, sessionEnding: false, settingsQuit: true))
}

@Test func forceQuitAndFailedExitNeverRespawn() {
    #expect(PermissionRelaunchPolicy.isCleanExit(0))
    #expect(!PermissionRelaunchPolicy.isCleanExit(9))
    #expect(!PermissionRelaunchPolicy.isCleanExit(15))
    #expect(!PermissionRelaunchPolicy.isCleanExit(1 << 8))
}
