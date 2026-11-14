// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import NebulaCore

@MainActor private final class MetadataReply {
    var continuation: CheckedContinuation<Int, Error>?
    var requests = 0
    func load() async throws -> Int {
        requests += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ result: Result<Int, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    try #require(condition(), "Asynchronous metadata request did not start")
}

@Test @MainActor func canceledCaptureDoesNotCancelMetadataSharedByNextCapture() async throws {
    let cache = CaptureMetadataCache<Int>()
    for value in 0..<100 {
        cache.invalidate()
        let reply = MetadataReply()
        let canceled = Task { try await cache.value { try await reply.load() } }
        try await waitFor { reply.requests == 1 }
        canceled.cancel()
        let next = Task { try await cache.value { try await reply.load() } }
        await Task.yield()
        reply.complete(.success(value))
        do { _ = try await canceled.value; Issue.record("Canceled capture received metadata") }
        catch { #expect(error is CancellationError) }
        #expect(try await next.value == value)
        #expect(try await cache.value { Issue.record("Warm cache reloaded"); return -1 } == value)
        #expect(reply.requests == 1)
    }
}

@Test @MainActor func invalidatedMetadataCannotReachJoinedWaitersOrOverwriteNewCache() async throws {
    let cache = CaptureMetadataCache<Int>()
    let oldReply = MetadataReply(), newReply = MetadataReply()
    let first = Task { try await cache.value { try await oldReply.load() } }
    try await waitFor { oldReply.requests == 1 }
    let joined = Task { try await cache.value { try await oldReply.load() } }
    // Ensure the second caller is suspended on the shared task before invalidation.
    for _ in 0..<20 { await Task.yield() }
    cache.invalidate()
    let current = Task { try await cache.value { try await newReply.load() } }
    try await waitFor { newReply.requests == 1 }
    newReply.complete(.success(42))
    #expect(try await current.value == 42)
    oldReply.complete(.success(1)) // Models a system API replying after cancellation.
    for task in [first, joined] {
        do { _ = try await task.value; Issue.record("Stale metadata escaped to a waiter") }
        catch { #expect(error is CancellationError) }
    }
    #expect(try await cache.value { Issue.record("New cache was cleared by old completion"); return -1 } == 42)
}

@Test @MainActor func failedMetadataCanRetryAndAlreadyCanceledCallerDoesNoWork() async throws {
    enum Failure: Error { case unavailable }
    let cache = CaptureMetadataCache<Int>()
    do { _ = try await cache.value { throw Failure.unavailable }; Issue.record("Expected load failure") }
    catch { #expect(error is Failure) }
    #expect(!cache.isLoading)
    #expect(try await cache.value { 7 } == 7)
    let canceled = Task { try await cache.value { Issue.record("Canceled caller loaded metadata"); return -1 } }
    canceled.cancel()
    do { _ = try await canceled.value; Issue.record("Canceled caller received cached metadata") }
    catch { #expect(error is CancellationError) }
    #expect(try await cache.value { -1 } == 7)
}
