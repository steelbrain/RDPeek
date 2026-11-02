import Dispatch

/// Runs Keychain calls off the main thread and off Swift's cooperative
/// pool: a call can block on the access-approval dialog for as long as the
/// user takes to answer it.
enum KeychainQueue {
    private static let queue = DispatchQueue(
        label: "RDPeek.keychain",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func run<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
