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

@Test func implicitSystemPromptIsNotFollowedByExplicitPromptOrAnotherCapture() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
    // Access changed after preflight; ScreenCaptureKit showed the native prompt.
    prompt.captureDenied()
    var requests = 0
    for _ in 0..<10 {
        #expect(prompt.actionBeforeCapture(granted: false) == .waitForConsent)
        #expect(prompt.actionAfterDenial(using: { requests += 1; return false }) == .openSettings)
    }
    #expect(requests == 0)
}

@Test func waitingForNativeConsentBlocksCaptureUntilPermissionRestart() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.actionBeforeCapture(granted: false) == .requestConsent)
    #expect(prompt.actionAfterDenial(using: { false }) == .waitForSystem)
    for granted in [false, false, true] {
        #expect(prompt.actionBeforeCapture(granted: granted) == .waitForConsent)
    }
    // The replacement process can capture after the system grants consent.
    let replacement = ScreenPermissionPrompt()
    #expect(replacement.actionBeforeCapture(granted: true) == .capture)
}

@Test func synchronousConsentGrantDoesNotBlockImmediateCapture() {
    var prompt = ScreenPermissionPrompt()
    #expect(prompt.actionAfterDenial(using: { true }) == .retryCapture)
    #expect(!prompt.isWaiting)
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
    prompt.captureSucceeded()
    #expect(prompt.actionBeforeCapture(granted: true) == .capture)
}
