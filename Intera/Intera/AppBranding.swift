//
//  AppBranding.swift
//  Intera
//
//  User-facing product name (App Store / home screen / in-app copy). Keep in sync with
//  `CFBundleDisplayName` and `CFBundleName` in `GoogleSignInURL.plist`.
//  Google Sign-In’s system sheet uses CFBundleName (not display name).
//

import Foundation

enum AppBranding {
    /// Platform brand shown under the app icon and in user-visible strings (Guideline 2.3.8).
    static let displayName = "Pismo"
    /// Repo / Xcode product label — not renamed in the target to avoid breaking bundle IDs and schemes.
    static let productName = "PismoiOS"
}

extension Bundle {
    /// Resolved display name for Settings deep-link copy and alerts.
    var appDisplayName: String {
        let fromPlist =
            (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromPlist, !fromPlist.isEmpty { return fromPlist }
        return AppBranding.displayName
    }
}
