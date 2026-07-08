//
//  ProductionLogging.swift
//  OnCuts
//
//  Non-fatal error reporting to Firebase Crashlytics (when linked).
//

import Foundation

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum ProductionLogging {
    /// Records a non-fatal error for Crashlytics dashboards (e.g. live sign-in failures).
    static func recordNonFatal(_ error: Error, context: [String: String] = [:]) {
        #if canImport(FirebaseCrashlytics)
        let crashlytics = Crashlytics.crashlytics()
        for (key, value) in context {
            crashlytics.setCustomValue(value, forKey: key)
        }
        crashlytics.record(error: error)
        #else
        _ = error
        _ = context
        #endif
    }

    static func recordNonFatal(message: String, context: [String: String] = [:]) {
        recordNonFatal(NSError(domain: "OnCuts", code: -1, userInfo: [NSLocalizedDescriptionKey: message]), context: context)
    }
}
