//
//  InteraRefreshCancellation.swift
//  Intera
//
//  Pull-to-refresh and navigation can cancel in-flight URLSession work. Those errors must not
//  surface as user-visible failures.
//

import Foundation

enum InteraRefreshCancellation {
    /// True for Swift concurrency cancellation or `NSURLErrorCancelled` (-999).
    static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlErr = error as? URLError, urlErr.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }
}
