// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import OSLog
import NebulaCore

/// Reuses display filters only. Every capture requests fresh pixels; no background screen stream.
@MainActor protocol CaptureProviding {
    func prepareIfAllowed()
    func invalidate()
    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)]
}

@MainActor final class CaptureSource: CaptureProviding {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")
    private struct DisplayFilters {
        let values: [CGDirectDisplayID: SCContentFilter]
        let excludesOwnApplication: Bool
    }
    private let cache = CaptureMetadataCache<DisplayFilters>()
    private var warmup: Task<Void, Never>?
    private let exclusion = CaptureExclusion()

    func prepareIfAllowed() {
        // This preflight controls optional metadata warmup only, never a user-requested capture.
        guard !cache.hasValue, !cache.isLoading, warmup == nil, CGPreflightScreenCaptureAccess() else { return }
        let generation = cache.generation
        warmup = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.loadFilters()
            if self.cache.generation == generation { self.warmup = nil }
        }
    }

    func invalidate() {
        cache.invalidate()
        warmup?.cancel(); warmup = nil
    }

    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)] {
        let started = ProcessInfo.processInfo.systemUptime
        let usedCache = cache.hasValue
        do {
            let displayFilters = try await safeFilters()
            try Task.checkCancellation()
            let setupFinished = ProcessInfo.processInfo.systemUptime
            let output = try await capture(screens, filters: displayFilters)
            let setupMS = Int((setupFinished - started) * 1000)
            let pixelsMS = Int((ProcessInfo.processInfo.systemUptime - setupFinished) * 1000)
            logger.notice("Capture timings: metadata \(setupMS, privacy: .public) ms; pixels \(pixelsMS, privacy: .public) ms; cached \(usedCache, privacy: .public)")
            return output
        } catch {
            // Esc → hotkey can begin another capture before ScreenCaptureKit finishes
            // the old request. Its cancellation/error must not clear the new cache.
            guard !Task.isCancelled, !(error is CancellationError) else { throw CancellationError() }
            invalidate()
            // A stale display filter may follow a display/Space transition. Refresh once;
            // permission errors must go straight to the normal native consent flow.
            guard usedCache, !ScreenCaptureFailure.isPermissionDenied(error) else { throw error }
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
        try await cache.value {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            let ownApp = try await self.exclusion.resolve(applications: content.applications, windows: content.windows)
            let ownApps = ownApp.map { [$0] } ?? []
            let values = Dictionary(uniqueKeysWithValues: content.displays.map {
                ($0.displayID, SCContentFilter(display: $0, excludingApplications: ownApps, exceptingWindows: []))
            })
            return DisplayFilters(values: values, excludesOwnApplication: !ownApps.isEmpty)
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
