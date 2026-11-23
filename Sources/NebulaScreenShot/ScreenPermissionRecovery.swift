// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import NebulaCore
import OSLog

@MainActor enum ScreenPermissionRecovery {
    private static let bundleIdentifier = "io.github.anthemzhou.NebulaScreenShot"
    private static let logger = Logger(subsystem: bundleIdentifier, category: "Permission")

    /// Invoked by explicit repair, or before consent for a denied ad-hoc upgrade.
    /// Returns once the relaunch helper has started; the caller can then quit safely.
    static func resetAndPrepareRelaunch() async throws -> AppRelauncher.Session {
        let bundle = Bundle.main
        let applicationURL = bundle.bundleURL.resolvingSymlinksInPath()
        guard bundle.bundleIdentifier == bundleIdentifier,
              applicationURL.pathExtension == "app",
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RecoveryError.invalidApplication
        }

        let started = ProcessInfo.processInfo.systemUptime
        logger.notice("Screen permission reset started; background subprocess; 45 second deadline")
        let result: PermissionResetProcess.Result
        do {
            result = try await PermissionResetProcess().run(executable: URL(fileURLWithPath: "/usr/bin/tccutil"),
                                                            arguments: ["reset", "ScreenCapture", bundleIdentifier])
        } catch is CancellationError { throw CancellationError()
        } catch PermissionResetProcess.Failure.timedOut { throw RecoveryError.timedOut
        } catch {
            throw RecoveryError.resetLaunchFailed(error.localizedDescription)
        }
        logger.notice("Screen permission reset finished in \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000), privacy: .public) ms; status: \(result.status, privacy: .public)")
        try Task.checkCancellation()
        guard result.status == 0, !result.wasSignaled else {
            throw RecoveryError.resetFailed(result.status, wasSignaled: result.wasSignaled)
        }

        do {
            return try AppRelauncher.prepare(.requestPermission)
        } catch {
            throw RecoveryError.relaunchFailed(error.localizedDescription)
        }
    }

    private enum RecoveryError: LocalizedError {
        case invalidApplication
        case resetLaunchFailed(String)
        case resetFailed(Int32, wasSignaled: Bool)
        case relaunchFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidApplication:
                return L10n.text("无法确认当前应用的位置，尚未重置权限。请从 Nebula ScreenShot.app 打开后重试。", "Unable to locate the app; permission has not been reset. Open Nebula ScreenShot.app and try again.")
            case .resetLaunchFailed(let detail):
                return L10n.text("无法启动屏幕录制权限重置：\(detail)", "Unable to reset screen recording permission: \(detail)")
            case .resetFailed(let code, let wasSignaled):
                let kind = wasSignaled ? L10n.text("终止信号", "signal") : L10n.text("退出代码", "exit code")
                return L10n.text("屏幕录制权限重置失败（\(kind)：\(code)）。请在系统设置中检查 Nebula ScreenShot 的权限后重试。", "Screen recording permission reset failed (\(kind): \(code)). Check Nebula ScreenShot permissions in System Settings and try again.")
            case .relaunchFailed(let detail):
                return L10n.text("旧的屏幕录制记录已清除，但无法自动重新启动。请退出并重新打开 Nebula ScreenShot。\n\(detail)", "The old screen recording permission was cleared, but automatic restart failed. Quit and reopen Nebula ScreenShot.\n\(detail)")
            case .timedOut:
                return L10n.text("系统处理屏幕录制权限超时。请稍后从菜单中的“重新授权屏幕录制…”重试。", "macOS took too long to restore screen recording permission. Retry later using Reauthorize Screen Recording in the menu.")
            }
        }
    }
}
