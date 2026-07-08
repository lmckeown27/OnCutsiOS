import Foundation

/// SwiftUI's `.refreshable` can cancel its `async` work when the refresh gesture ends. For network
/// requests that must complete, run them on the main actor from a detached task so cancellation
/// does not tear down the request before it starts (same pattern as ``ConsumerBookingsHubView``).
enum OnCutsPullToRefresh {
    /// Runs `body` on the main actor without inheriting the refresh task's cancellation.
    static func runMainActorAsyncIsolatedFromRefreshableCancellation(
        _ body: @escaping @MainActor () async -> Void
    ) async {
        await Task.detached(priority: .userInitiated) { @MainActor in
            await body()
        }.value
    }
}
