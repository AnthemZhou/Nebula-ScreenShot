// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import OSLog
import NebulaCore

/// Short-lived, same-bundle helper; no launch agent, login item, or screen capture.
@MainActor enum AppRelauncher {
    enum Mode: String { case requestPermission = "--request-screen-permission", resume = "--resume-after-permission" }
    static let bundleIdentifier = "io.github.anthemzhou.NebulaScreenShot"
    private static let logger = Logger(subsystem: bundleIdentifier, category: "Permission")

    final class Session {
        let token: URL
        let ready: URL
        let process: Process
        var isRunning: Bool { process.isRunning && FileManager.default.fileExists(atPath: token.path) }

        init(token: URL, process: Process) {
            self.token = token; self.ready = token.appendingPathExtension("ready"); self.process = process
        }

        func waitUntilReady() async throws {
            for _ in 0..<200 {
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: ready.path) { return }
                guard process.isRunning else { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            cancel()
            throw RelaunchError.helperUnavailable
        }

        func cancel() {
            try? FileManager.default.removeItem(at: token)
            try? FileManager.default.removeItem(at: ready)
        }
    }

    static func prepare(_ mode: Mode) throws -> Session {
        guard Bundle.main.bundleIdentifier == bundleIdentifier, Bundle.main.bundleURL.pathExtension == "app",
              let executable = Bundle.main.executableURL else { throw RelaunchError.invalidBundle }
        let id = UUID().uuidString
        let token = tokenURL(id)
        let pid = ProcessInfo.processInfo.processIdentifier
        try Data("\(pid)\n\(mode.rawValue)".utf8).write(to: token, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: token.path)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--permission-relaunch-helper", String(pid), mode.rawValue, id]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let session = Session(token: token, process: process)
        do { try process.run() } catch { session.cancel(); throw error }
        return session
    }

    static func tokenURL(_ id: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nebula-permission-\(id)")
    }

    /// Runs before NSApplication is created, so the helper owns no menu or hotkey.
    static func runHelper(arguments: [String]) -> Int32 {
        guard arguments.count == 5, let pid = Int32(arguments[2]), pid > 1,
              let mode = Mode(rawValue: arguments[3]), UUID(uuidString: arguments[4]) != nil,
              Bundle.main.bundleIdentifier == bundleIdentifier else { return 1 }
        let token = tokenURL(arguments[4]), ready = token.appendingPathExtension("ready")
        guard (try? String(contentsOf: token, encoding: .utf8)) == "\(pid)\n\(mode.rawValue)" else { return 1 }
        defer { try? FileManager.default.removeItem(at: token); try? FileManager.default.removeItem(at: ready) }
        let status: Int
        do {
            status = try waitForExit(pid: pid, token: token, ready: ready,
                                     timeout: mode == .resume ? 600 : 15)
        } catch {
            logger.notice("Permission relaunch helper ended: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        guard PermissionRelaunchPolicy.isCleanExit(status), FileManager.default.fileExists(atPath: token.path) else { return 0 }
        if mode == .resume && !CGPreflightScreenCaptureAccess() {
            logger.notice("Permission was not granted; no automatic relaunch")
            return 0
        }
        // Consume the handoff before launch; it can never start an endless restart loop.
        try? FileManager.default.removeItem(at: token)
        try? FileManager.default.removeItem(at: ready)
        let application = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let existing = NSWorkspace.shared.runningApplications.contains {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated &&
            $0.bundleIdentifier == bundleIdentifier && $0.bundleURL?.resolvingSymlinksInPath() == application
        }
        if existing { logger.notice("Permission relaunch already handled by macOS"); return 0 }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        configuration.activates = mode == .requestPermission
        configuration.arguments = [mode.rawValue]
        let logger = self.logger
        NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, error in
            if let error { logger.error("Permission relaunch failed: \(error.localizedDescription, privacy: .public)") }
            else { logger.notice("Application reopened after permission handoff") }
            exit(error == nil ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(1) }
        RunLoop.main.run()
        return 1
    }

    /// Event-driven parent monitoring preserves the exit status (unlike polling kill -0).
    static func waitForExit(pid: Int32, token: URL, ready: URL, timeout: TimeInterval) throws -> Int {
        let queue = kqueue()
        guard queue >= 0 else { throw RelaunchError.helperUnavailable }
        defer { close(queue) }
        var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                            fflags: UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS), data: 0, udata: nil)
        guard kevent(queue, &change, 1, nil, 0, nil) == 0 else { throw RelaunchError.parentUnavailable }
        try Data().write(to: ready, options: .atomic)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while FileManager.default.fileExists(atPath: token.path) && ProcessInfo.processInfo.systemUptime < deadline {
            var event = kevent()
            var interval = timespec(tv_sec: 0, tv_nsec: 250_000_000)
            let count = kevent(queue, nil, 0, &event, 1, &interval)
            if count > 0 {
                guard event.flags & UInt16(EV_ERROR) == 0 else { throw RelaunchError.parentUnavailable }
                return event.data
            }
            if count < 0 && errno != EINTR { throw RelaunchError.parentUnavailable }
        }
        throw RelaunchError.cancelled
    }

    enum RelaunchError: LocalizedError {
        case invalidBundle, helperUnavailable, parentUnavailable, cancelled
        var errorDescription: String? {
            switch self {
            case .invalidBundle: return "请从完整的 Nebula ScreenShot.app 启动应用。"
            case .helperUnavailable: return "无法准备授权后的自动重启，请重试。"
            case .parentUnavailable: return "原应用已退出或无法监听其退出。"
            case .cancelled: return "授权重启等待已取消或到期。"
            }
        }
    }
}
