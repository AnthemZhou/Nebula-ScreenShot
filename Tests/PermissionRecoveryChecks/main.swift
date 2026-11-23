// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import NebulaCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: message, code: 1) }
}

// Only our own child fixtures are launched. No tccutil, permission API, real
// screenshot, visible window, or synthetic input is used by these checks.
let arguments = CommandLine.arguments
if arguments.count > 2, arguments[1] == "--child" {
    switch arguments[2] {
    case "exit": exit(Int32(arguments[3])!)
    case "slow": usleep(350_000); exit(0)
    case "stubborn":
        signal(SIGTERM, SIG_IGN)
        try String(getpid()).write(toFile: arguments[3], atomically: true, encoding: .utf8)
        while true { sleep(1) }
    default: exit(2)
    }
}

@MainActor func checkProcesses() async throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nebula-recovery-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for status: Int32 in [0, 7] {
        let result = try await PermissionResetProcess().run(executable: executable, arguments: ["--child", "exit", String(status)])
        try require(result.status == status && !result.wasSignaled, "Preserve subprocess exit status")
    }
    do {
        _ = try await PermissionResetProcess().run(executable: directory.appendingPathComponent("missing"), arguments: [])
        throw NSError(domain: "Missing executable must fail", code: 1)
    } catch let error as NSError {
        try require(error.domain != "Missing executable must fail", error.domain)
    }
    print("PASS: successful, failed and missing reset subprocesses complete")

    var ticks = 0
    let heartbeat = Task { @MainActor in
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            ticks += 1
        }
    }
    _ = try await PermissionResetProcess().run(executable: executable, arguments: ["--child", "slow"])
    heartbeat.cancel()
    try require(ticks >= 10, "Main actor must keep responding while reset runs")
    print("PASS: main actor remains responsive during slow reset (\(ticks) ticks)")

    for mode in ["timeout", "cancel"] {
        let ready = directory.appendingPathComponent(mode)
        let operation = Task {
            try await PermissionResetProcess().run(executable: executable,
                arguments: ["--child", "stubborn", ready.path], timeout: mode == "timeout" ? 0.8 : 10)
        }
        let started = ProcessInfo.processInfo.systemUptime
        while !FileManager.default.fileExists(atPath: ready.path),
              ProcessInfo.processInfo.systemUptime - started < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let text = try? String(contentsOf: ready, encoding: .utf8), let pid = Int32(text) else {
            operation.cancel(); throw NSError(domain: "Child fixture did not become ready", code: 1)
        }
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        if mode == "cancel" { operation.cancel() }
        do {
            _ = try await operation.value
            throw NSError(domain: "Stopped child must throw", code: 1)
        } catch is CancellationError {
            try require(mode == "cancel", "Unexpected cancellation")
        } catch PermissionResetProcess.Failure.timedOut {
            try require(mode == "timeout", "Unexpected timeout")
        }
        try require(ProcessInfo.processInfo.systemUptime - started < 5, "Child stop must be bounded")
        try require(kill(pid, 0) == -1 && errno == ESRCH, "Stopped child must be reaped")
        print("PASS: \(mode) completes and reaps a child that ignores SIGTERM")
    }
    for _ in 0..<20 {
        let operation = Task {
            try await PermissionResetProcess().run(executable: executable, arguments: ["--child", "slow"])
        }
        operation.cancel()
        do {
            _ = try await operation.value
            throw NSError(domain: "Early cancellation must throw", code: 1)
        } catch is CancellationError { }
    }
    print("PASS: 20 cancellations before launch complete without a suspended continuation")
}

@MainActor func checkProgress() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let initialWindows = Set(NSApp.windows.map(\.windowNumber))
    let progress = PermissionProgressHUD(presentsWindows: false, slowNoticeDelay: .milliseconds(80))
    progress.show(.recovering)
    guard let panel = NSApp.windows.first(where: { !initialWindows.contains($0.windowNumber) }) as? NSPanel else {
        throw NSError(domain: "Progress panel missing", code: 1)
    }
    try require(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents,
                "Progress must never steal focus or intercept clicks")
    try require(panel.styleMask.contains(.nonactivatingPanel), "Progress must be nonactivating")
    try require(!progress.isVisible, "Fixture progress must remain hidden")
    for _ in 0..<5 {
        progress.showCurrent()
        try await Task.sleep(for: .milliseconds(25))
    }
    try require(progress.stage == .waitingForSystem, "Repeated hotkeys must not postpone slow notice")
    try require(NSApp.windows.filter { !initialWindows.contains($0.windowNumber) }.count == 1,
                "Repeated hotkeys must reuse a single panel")
    let label = panel.contentView!.subviews.compactMap { $0 as? NSTextField }.first!
    try require(label.frame.width >= label.intrinsicContentSize.width, "Progress text must fit")
    try require(panel.contentView!.bounds.contains(label.frame), "Progress text must remain inside panel")
    if let output = ProcessInfo.processInfo.environment["NEBULA_PROGRESS_PREVIEW"] {
        let view = panel.contentView!
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        }
    }
    progress.show(.recovering)
    progress.hide()
    try await Task.sleep(for: .milliseconds(110))
    try require(progress.stage == nil && !progress.isVisible, "Canceled timer must not resurrect progress")
    progress.show(.preparing)
    progress.hide() // the native consent dialog takes over here
    progress.showCurrent()
    try require(progress.stage == nil, "Native consent must not show duplicate progress")
    progress.show(.restarting)
    progress.hide()
    print("PASS: one nonactivating HUD, stable slow notice, fitting text and clean native-dialog handoff")
}

Task { @MainActor in
    do {
        try await checkProcesses()
        try await checkProgress()
        exit(0)
    } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
RunLoop.main.run()
