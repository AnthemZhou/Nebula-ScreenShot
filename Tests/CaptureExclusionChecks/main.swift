// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import Darwin

@MainActor final class ExclusionFixture: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 80, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        let shade = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        panel.contentView = shade
        panel.orderFrontRegardless() // Offscreen, no activation and no desktop pixels.
        self.panel = panel
        Task { @MainActor in
            do {
                guard #available(macOS 14.4, *) else {
                    self.finish("SKIP: current-process metadata requires macOS 14.4+")
                    return
                }
                let resolver = CaptureExclusion()
                // Reproduce the missing entry returned by the global shareable list.
                guard let owner = try await resolver.resolve(applications: [], windows: []),
                      owner.processID == getpid(), owner.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw NSError(domain: "Missing owned app after global-list omission", code: 1)
                }
                let again = try await resolver.resolve(applications: [], windows: [])
                guard again === owner else { throw NSError(domain: "Own-process exclusion should be reusable", code: 2) }
                let content = try await SCShareableContent.currentProcess
                guard let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }) else {
                    throw NSError(domain: "Missing fixture panel", code: 3)
                }
                let byWindow = try await CaptureExclusion().resolve(applications: [], windows: [ownWindow])
                guard byWindow?.processID == getpid() else { throw NSError(domain: "Window owner fallback failed", code: 4) }
                self.finish("PASS: missing global entry resolved through current-process metadata; cached owner and window owner both valid; no screen capture or consent request")
            } catch { self.finish("FAIL: \(error)") }
        }
    }

    private func finish(_ result: String) {
        if let path = Bundle.main.object(forInfoDictionaryKey: "FixtureResultPath") as? String {
            try? result.write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = ExclusionFixture()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
