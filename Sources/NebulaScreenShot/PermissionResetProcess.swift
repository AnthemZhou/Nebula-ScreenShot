// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

/// One-shot operation. Only the owned subprocess is stopped on timeout/cancellation. Launch
/// and termination never block AppKit, and the continuation completes once.
final class PermissionResetProcess: @unchecked Sendable {
    struct Result: Sendable { let status: Int32; let wasSignaled: Bool }
    enum Failure: Error { case timedOut }
    private let lock = NSLock()
    private var process: Process?
    private var continuation: CheckedContinuation<Result, Error>?
    private var stopReason: Error?
    private var finished = false
    private var deadline: DispatchWorkItem?

    func run(executable: URL, arguments: [String], timeout: TimeInterval = 45) async throws -> Result {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let cancelled = stopReason
                lock.unlock()
                if let cancelled { finish(.failure(cancelled)); return }
                let timer = DispatchWorkItem { [weak self] in self?.stop(Failure.timedOut) }
                lock.lock(); deadline = timer; lock.unlock()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let child = Process()
                    child.executableURL = executable; child.arguments = arguments
                    child.standardInput = FileHandle.nullDevice
                    child.standardOutput = FileHandle.nullDevice
                    child.standardError = FileHandle.nullDevice
                    child.terminationHandler = { [weak self] child in
                        self?.finish(.success(Result(status: child.terminationStatus,
                                                     wasSignaled: child.terminationReason == .uncaughtSignal)))
                    }
                    lock.lock(); process = child; let reason = stopReason; lock.unlock()
                    if let reason { finish(.failure(reason)); return }
                    do {
                        try child.run()
                        lock.lock(); let reason = stopReason; lock.unlock()
                        if let reason { stop(reason) }
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: { self.stop(CancellationError()) }
    }

    private func stop(_ reason: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if stopReason == nil { stopReason = reason }
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        let reason = stopReason
        let timer = deadline
        deadline = nil
        process = nil
        lock.unlock()
        timer?.cancel()
        continuation.resume(with: reason.map { .failure($0) } ?? result)
    }
}
