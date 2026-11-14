// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import NebulaCore

// Own fixture processes only: never opens Nebula, requests permission, or posts input.
MainActor.assumeIsolated {
    let args = CommandLine.arguments
    let executable = URL(fileURLWithPath: args[0])
    func waitForFile(_ url: URL, seconds: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return FileManager.default.fileExists(atPath: url.path)
    }
    func launch(_ arguments: [String]) throws -> Process {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }
    if args.count == 6 && args[1] == "--observe" {
        let token = URL(fileURLWithPath: args[3]), ready = token.appendingPathExtension("ready")
        let output = URL(fileURLWithPath: args[4])
        let text: String
        do {
            let status = try AppRelauncher.waitForExit(pid: Int32(args[2])!, token: token, ready: ready,
                                                      timeout: args[5] == "timeout" ? 0.2 : 4)
            text = "exit:\(status):\(PermissionRelaunchPolicy.isCleanExit(status))"
        } catch { text = "cancelled" }
        try! text.write(to: output, atomically: true, encoding: .utf8)
        exit(0)
    }
    if args.count == 5 && args[1] == "--parent" {
        let mode = args[2], token = URL(fileURLWithPath: args[3]), output = URL(fileURLWithPath: args[4])
        do {
            let observer = try launch(["--observe", String(getpid()), token.path, output.path, mode])
            guard waitForFile(token.appendingPathExtension("ready")) else { observer.terminate(); exit(1) }
            switch mode {
            case "clean": exit(0)
            case "signal": raise(SIGKILL); exit(1)
            case "cancel": try FileManager.default.removeItem(at: token)
            default: break
            }
            guard waitForFile(output) else { observer.terminate(); exit(1) }
            exit(0)
        } catch { fputs("\(error)\n", stderr); exit(1) }
    }
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nebula relaunch checks \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in ["clean", "signal", "cancel", "timeout"] {
            let token = directory.appendingPathComponent("\(mode).token"), output = directory.appendingPathComponent("\(mode).result")
            try Data().write(to: token)
            let parent = try launch(["--parent", mode, token.path, output.path])
            parent.waitUntilExit()
            guard waitForFile(output) else { throw NSError(domain: "Missing observer result", code: 1) }
            let result = try String(contentsOf: output, encoding: .utf8)
            let expected = mode == "clean" ? "exit:0:true" : (mode == "signal" ? "exit:9:false" : "cancelled")
            guard result == expected else { throw NSError(domain: "\(mode): \(result), expected \(expected)", code: 2) }
            print("PASS: permission parent handoff \(mode): \(result)")
        }
    } catch { fputs("\(error)\n", stderr); exit(1) }
}
