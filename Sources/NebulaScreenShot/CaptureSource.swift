// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import OSLog
import NebulaCore

/// Reuses display filters only. Every capture requests fresh pixels; no background screen stream.
@MainActor final class CaptureSource {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")
    private struct DisplayFilters {
        let values: [CGDirectDisplayID: SCContentFilter]
        let excludesOwnApplication: Bool
    }
    private var filters: DisplayFilters?
    private var loading: Task<DisplayFilters, Error>?
    private var warmup: Task<Void, Never>?
    private var generation = 0

    func prepareIfAllowed() {
        // This preflight controls optional metadata warmup only, never a user-requested capture.
        guard filters == nil, loading == nil, warmup == nil, CGPreflightScreenCaptureAccess() else { return }
        warmup = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.loadFilters()
            self.warmup = nil
        }
    }

    func invalidate() {
        generation += 1
        filters = nil
        loading?.cancel(); loading = nil
        warmup?.cancel(); warmup = nil
    }

    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)] {
        let started = ProcessInfo.processInfo.systemUptime
        let usedCache = filters?.excludesOwnApplication == true
        do {
            let displayFilters = try await safeFilters()
            let setupFinished = ProcessInfo.processInfo.systemUptime
            let output = try await capture(screens, filters: displayFilters)
            let setupMS = Int((setupFinished - started) * 1000)
            let pixelsMS = Int((ProcessInfo.processInfo.systemUptime - setupFinished) * 1000)
            logger.notice("Capture timings: metadata \(setupMS, privacy: .public) ms; pixels \(pixelsMS, privacy: .public) ms; cached \(usedCache, privacy: .public)")
            return output
        } catch {
            invalidate()
            // A stale display filter may follow a display/Space transition. Refresh once;
            // permission errors must go straight to the normal native consent flow.
            guard usedCache, !ScreenCaptureFailure.isPermissionDenied(error), !(error is CancellationError) else { throw error }
            logger.notice("Refreshing stale display filters once")
            return try await capture(screens, filters: safeFilters())
        }
    }

    private func safeFilters() async throws -> [CGDirectDisplayID: SCContentFilter] {
        var result = try await loadFilters()
        if !result.excludesOwnApplication {
            // Warmup can precede our first visible window. Reload after the shade is shown.
            invalidate()
            result = try await loadFilters()
        }
        guard result.excludesOwnApplication else { throw CaptureCoordinator.CaptureError.missingOverlayExclusion }
        return result.values
    }

    private func loadFilters() async throws -> DisplayFilters {
        if let filters { return filters }
        if let loading { return try await loading.value }
        let expectedGeneration = generation
        let task = Task { @MainActor in
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let values = Dictionary(uniqueKeysWithValues: content.displays.map {
                ($0.displayID, SCContentFilter(display: $0, excludingApplications: ownApps, exceptingWindows: []))
            })
            return DisplayFilters(values: values, excludesOwnApplication: !ownApps.isEmpty)
        }
        loading = task
        do {
            let result = try await task.value
            guard expectedGeneration == generation else { throw CancellationError() }
            filters = result
            loading = nil
            return result
        } catch {
            if expectedGeneration == generation { loading = nil }
            throw error
        }
    }

    private func capture(_ screens: [NSScreen], filters: [CGDirectDisplayID: SCContentFilter]) async throws -> [(NSScreen, CGImage)] {
        var tasks: [Task<CGImage, Error>] = []
        for screen in screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let filter = filters[id] else {
                tasks.forEach { $0.cancel() }
                throw CaptureCoordinator.CaptureError.noDisplay
            }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            // All displays start together instead of serially waiting for each screenshot.
            tasks.append(Task { @MainActor in
                try Task.checkCancellation()
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                return image
            })
        }
        return try await withTaskCancellationHandler {
            defer { tasks.forEach { $0.cancel() } }
            var result: [(NSScreen, CGImage)] = []
            for (screen, task) in zip(screens, tasks) { result.append((screen, try await task.value)) }
            return result
        } onCancel: { [tasks] in tasks.forEach { $0.cancel() } }
    }
}
