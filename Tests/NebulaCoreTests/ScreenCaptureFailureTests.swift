// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ScreenCaptureKit
import Testing
@testable import NebulaCore

@Test func screenCaptureDenialIsRecognizedThroughNSError() {
    let error: Error = NSError(domain: SCStreamError.errorDomain,
                               code: SCStreamError.Code.userDeclined.rawValue)
    #expect(ScreenCaptureFailure.isPermissionDenied(error))
}

@Test func matchingCodeInAnotherDomainIsNotScreenCaptureDenial() {
    let error = NSError(domain: "io.github.anthemzhou.NebulaScreenShot.tests",
                        code: SCStreamError.Code.userDeclined.rawValue)
    #expect(!ScreenCaptureFailure.isPermissionDenied(error))
}

@Test func otherScreenCaptureFailuresAreNotPermissionDenials() {
    for code in [SCStreamError.Code.failedToStart, .missingEntitlements, .noDisplayList, .internalError] {
        let error = NSError(domain: SCStreamError.errorDomain, code: code.rawValue)
        #expect(!ScreenCaptureFailure.isPermissionDenied(error))
    }
}

@Test func foundationErrorsAreNotScreenCaptureDenials() {
    let error = CocoaError(.fileReadNoPermission)
    #expect(!ScreenCaptureFailure.isPermissionDenied(error))
}
