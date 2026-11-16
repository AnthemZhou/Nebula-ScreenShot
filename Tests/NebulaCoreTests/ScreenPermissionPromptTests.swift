// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import NebulaCore

@Test func deniedConsentDoesNotPromptAgainWhenOpeningSettingsOrRetrying() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.beginRequest() == true)
    // Claim is held while the framework is still awaiting its callback.
    #expect(prompt.beginRequest() == false)
    prompt.completeRequest(granted: false)
    #expect(prompt.beginRequest() == false)
    #expect(prompt.actionBeforeCapture(granted: false) == .waitForConsent)
}

@Test func grantedConsentAllowsOnlyOneImmediateCaptureRetry() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.beginRequest() == true)
    prompt.completeRequest(granted: true)
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
    #expect(prompt.beginRequest() == false)
}

@Test func newProcessCanRequestConsentAgainAfterPermissionRecovery() {
    var previousProcess = ScreenPermissionPrompt()
    #expect(previousProcess.beginRequest() == true)
    previousProcess.completeRequest(granted: false)
    var relaunchedProcess = ScreenPermissionPrompt()
    #expect(relaunchedProcess.beginRequest() == true)
}

@Test func implicitSystemPromptIsNotFollowedByExplicitPromptOrAnotherCapture() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
    prompt.captureDenied()
    for _ in 0..<10 {
        #expect(prompt.actionBeforeCapture(granted: false) == .waitForConsent)
        #expect(prompt.beginRequest() == false)
    }
}

@Test func waitingForNativeConsentBlocksCaptureUntilPermissionRestart() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.actionBeforeCapture(granted: false) == .requestConsent)
    #expect(prompt.beginRequest() == true)
    prompt.completeRequest(granted: false)
    for granted in [false, false, true] {
        #expect(prompt.actionBeforeCapture(granted: granted) == .waitForConsent)
    }
    let replacement = ScreenPermissionPrompt()
    #expect(replacement.actionBeforeCapture(granted: true) == .capture)
}

@Test func startingConsentDoesNotCountAsGrantingScreenAccess() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.beginRequest() == true)
    #expect(prompt.isWaiting)
    #expect(prompt.actionBeforeCapture(granted: false) == .waitForConsent)
    prompt.completeRequest(granted: true)
    #expect(!prompt.isWaiting)
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
}
