// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Shares metadata loading without letting a canceled capture invalidate a newer request.
/// This cache must never hold captured screen pixels.
@MainActor public final class CaptureMetadataCache<Value> {
    private var cached: Value?
    private var loading: (id: UUID, task: Task<Value, Error>)?
    public private(set) var generation = 0
    public var hasValue: Bool { cached != nil }
    public var isLoading: Bool { loading != nil }

    public init() {}

    public func invalidate() {
        generation += 1
        cached = nil
        loading?.task.cancel()
        loading = nil
    }

    public func value(load: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let cached { return cached }
        let expectedGeneration = generation
        let task: Task<Value, Error>
        let loadID: UUID
        if let loading { task = loading.task; loadID = loading.id }
        else {
            loadID = UUID()
            task = Task { @MainActor in try await load() }
            loading = (loadID, task)
        }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard expectedGeneration == generation else { throw CancellationError() }
            cached = result
            if loading?.id == loadID { loading = nil }
            return result
        } catch {
            // Canceling a waiter does not cancel work shared by the next capture.
            if expectedGeneration == generation && loading?.id == loadID && !Task.isCancelled { loading = nil }
            throw error
        }
    }
}
