// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ScreenCaptureKit
import OSLog

/// The global shareable-app list can omit an accessory app even with visible panels.
/// Resolve our own process explicitly, without recording or requesting extra access.
@MainActor final class CaptureExclusion {
    private var cachedApplication: SCRunningApplication?
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")

    func resolve(applications: [SCRunningApplication], windows: [SCWindow]) async throws -> SCRunningApplication? {
        if let cachedApplication { return cachedApplication }
        let pid = ProcessInfo.processInfo.processIdentifier
        func ownApplication(_ apps: [SCRunningApplication], _ windows: [SCWindow]) -> SCRunningApplication? {
            apps.first { $0.processID == pid } ?? windows.compactMap(\.owningApplication).first { $0.processID == pid }
        }
        if let app = ownApplication(applications, windows) {
            cachedApplication = app
            return app
        }
        let ownContent: SCShareableContent
        if #available(macOS 14.4, *) {
            ownContent = try await SCShareableContent.currentProcess
        } else {
            ownContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
        try Task.checkCancellation()
        cachedApplication = ownApplication(ownContent.applications, ownContent.windows)
        if cachedApplication != nil {
            logger.notice("Resolved overlay exclusion through own-process metadata; PID: \(pid, privacy: .public)")
        }
        return cachedApplication
    }
}
