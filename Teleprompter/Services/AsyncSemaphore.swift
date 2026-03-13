// Teleprompter/Services/AsyncSemaphore.swift
import Foundation

/// A simple async-compatible semaphore for limiting concurrency in TaskGroups.
actor AsyncSemaphore {
    private let limit: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.count = limit
    }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        if waiters.isEmpty {
            count = min(count + 1, limit)
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
