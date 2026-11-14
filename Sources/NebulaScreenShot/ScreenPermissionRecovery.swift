// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import NebulaCore

@MainActor enum ScreenPermissionRecovery {
    private static let bundleIdentifier = "io.github.anthemzhou.NebulaScreenShot"

    /// Invoked by explicit repair, or once after an ad-hoc upgrade's actual capture denial.
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

        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", bundleIdentifier]
        reset.standardInput = FileHandle.nullDevice
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice

        let result: ProcessResult
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                reset.terminationHandler = { process in
                    continuation.resume(returning: ProcessResult(status: process.terminationStatus,
                                                                  wasSignaled: process.terminationReason == .uncaughtSignal))
                }
                do {
                    try reset.run()
                } catch {
                    reset.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            throw RecoveryError.resetLaunchFailed(error.localizedDescription)
        }
        guard result.status == 0, !result.wasSignaled else {
            throw RecoveryError.resetFailed(result.status, wasSignaled: result.wasSignaled)
        }

        do {
            return try AppRelauncher.prepare(.requestPermission)
        } catch {
            throw RecoveryError.relaunchFailed(error.localizedDescription)
        }
    }

    private struct ProcessResult {
        let status: Int32
        let wasSignaled: Bool
    }

    private enum RecoveryError: LocalizedError {
        case invalidApplication
        case resetLaunchFailed(String)
        case resetFailed(Int32, wasSignaled: Bool)
        case relaunchFailed(String)

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
            }
        }
    }
}
