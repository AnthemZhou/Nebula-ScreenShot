// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureFailure {
    public static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamError.errorDomain &&
            error.code == SCStreamError.Code.userDeclined.rawValue
    }
}
