// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import NebulaCore

@Test func deniedConsentDoesNotPromptAgainWhenOpeningSettingsOrRetrying() {
    var prompt = ScreenPermissionPrompt()
    var requests = 0
    let request = { requests += 1; return false }
    #expect(prompt.requestOnce(using: request) == false)
    #expect(prompt.requestOnce(using: request) == nil)
    #expect(prompt.requestOnce(using: request) == nil)
    #expect(requests == 1)
}

@Test func grantedConsentAllowsOnlyOneImmediateCaptureRetry() {
    var prompt = ScreenPermissionPrompt()
    var retries = 0
    for _ in 0..<3 {
        if prompt.requestOnce(using: { true }) == true { retries += 1 }
    }
    #expect(retries == 1)
}

@Test func newProcessCanRequestConsentAgainAfterPermissionRecovery() {
    var previousProcess = ScreenPermissionPrompt()
    #expect(previousProcess.requestOnce(using: { false }) == false)
    var relaunchedProcess = ScreenPermissionPrompt()
    #expect(relaunchedProcess.requestOnce(using: { true }) == true)
}
