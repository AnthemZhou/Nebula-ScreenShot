// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import OSLog
import NebulaCore

/// Reuses display filters only. Every capture requests fresh pixels; no background screen stream.
@MainActor protocol CaptureProviding {
    func prepareIfAllowed(onPermissionDenied: @escaping () -> Void)
    func invalidate()
    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)]
}

@MainActor final class CaptureSource: CaptureProviding {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")
    private let cache = CaptureMetadataCache<[CGDirectDisplayID: SCContentFilter]>()
    private var warmup: Task<Void, Never>?

    func prepareIfAllowed(onPermissionDenied: @escaping () -> Void) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return } // Direct screenshots need no shareable-content enumeration.
        #endif
        // Warmup must not trigger a consent prompt in the background.
        guard !cache.hasValue, !cache.isLoading, warmup == nil, CGPreflightScreenCaptureAccess() else { return }
        let generation = cache.generation
        warmup = Task { @MainActor [weak self] in
            guard let self else { return }
            do { _ = try await self.loadFilters() }
            catch {
                if !Task.isCancelled, self.cache.generation == generation,
                   ScreenCaptureFailure.isPermissionDenied(error) { onPermissionDenied() }
            }
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
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let output = try await captureConcurrently(screens) { screen in
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                        throw CaptureCoordinator.CaptureError.noDisplay
                    }
                    let config = SCScreenshotConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false
                    config.ignoreShadows = false
                    config.ignoreClipping = false
                    config.dynamicRange = .sdr
                    config.displayIntent = .local
                    let result = try await SCScreenshotManager.captureScreenshot(rect: CGDisplayBounds(id), configuration: config)
                    guard let image = result.sdrImage else { throw CaptureCoordinator.CaptureError.noImage }
                    return image
                }
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                logger.notice("Direct desktop screenshot: \(elapsed, privacy: .public) ms; no metadata enumeration or overlay exclusion")
                return output
            }
            #endif
            let displayFilters = try await loadFilters()
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
            return try await capture(screens, filters: loadFilters())
        }
    }

    private func loadFilters() async throws -> [CGDirectDisplayID: SCContentFilter] {
        try await cache.value {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            // CaptureCoordinator keeps every editor panel hidden until all images
            // arrive. Capture the original desktop, without recomposing app layers.
            return Dictionary(uniqueKeysWithValues: content.displays.map {
                ($0.displayID, SCContentFilter(display: $0, excludingWindows: []))
            })
        }
    }

    private func capture(_ screens: [NSScreen], filters: [CGDirectDisplayID: SCContentFilter]) async throws -> [(NSScreen, CGImage)] {
        try await captureConcurrently(screens) { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let filter = filters[id] else {
                throw CaptureCoordinator.CaptureError.noDisplay
            }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.ignoreShadowsDisplay = false
            config.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
    }

    private func captureConcurrently(_ screens: [NSScreen],
        imageForScreen: @escaping @MainActor (NSScreen) async throws -> CGImage) async throws -> [(NSScreen, CGImage)] {
        let tasks = screens.map { screen in
            Task { @MainActor in
                try Task.checkCancellation()
                let image = try await imageForScreen(screen)
                try Task.checkCancellation()
                return image
            }
        }
        return try await withTaskCancellationHandler {
            defer { tasks.forEach { $0.cancel() } }
            var result: [(NSScreen, CGImage)] = []
            for (screen, task) in zip(screens, tasks) { result.append((screen, try await task.value)) }
            return result
        } onCancel: { [tasks] in tasks.forEach { $0.cancel() } }
    }
}
