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

@Test func staleLaunchServicesParentIsNotASuccessfulRelaunch() {
    // Reproduce a cleanly exited parent whose cached application entry still says running.
    let oldPID: Int32 = 50531, helperPID: Int32 = 55245, newPID: Int32 = 55246
    #expect(!PermissionRelaunchPolicy.isReplacementProcess(oldPID, exitedPID: oldPID,
        helperPID: helperPID, isTerminated: false, isAlive: true))
    #expect(!PermissionRelaunchPolicy.isReplacementProcess(helperPID, exitedPID: oldPID,
        helperPID: helperPID, isTerminated: false, isAlive: true))
    #expect(!PermissionRelaunchPolicy.isReplacementProcess(newPID, exitedPID: oldPID,
        helperPID: helperPID, isTerminated: false, isAlive: false))
    #expect(!PermissionRelaunchPolicy.isReplacementProcess(newPID, exitedPID: oldPID,
        helperPID: helperPID, isTerminated: true, isAlive: true))
    #expect(PermissionRelaunchPolicy.isReplacementProcess(newPID, exitedPID: oldPID,
        helperPID: helperPID, isTerminated: false, isAlive: true))
}

@Test func privacySecurityExtensionKeepsTheConsentHandoffArmed() {
    var policy = PermissionRelaunchPolicy()
    policy.begin(granted: false)
    for origin in ["com.apple.settings.PrivacySecurity.extension", "com.apple.systempreferences",
                   "com.apple.systemsettings"] {
        let settingsQuit = PermissionRelaunchPolicy.isSystemSettings(origin)
        #expect(policy.preserveForQuit(explicitQuit: false, sessionEnding: false, settingsQuit: settingsQuit))
        #expect(!policy.preserveForQuit(explicitQuit: true, sessionEnding: false, settingsQuit: settingsQuit))
        #expect(!policy.preserveForQuit(explicitQuit: false, sessionEnding: true, settingsQuit: settingsQuit))
    }
    #expect(!PermissionRelaunchPolicy.isSystemSettings("com.apple.Terminal"))
    #expect(!PermissionRelaunchPolicy.isSystemSettings("com.apple.settings.Unrelated.extension"))
    #expect(!PermissionRelaunchPolicy.isSystemSettings(nil))
}
