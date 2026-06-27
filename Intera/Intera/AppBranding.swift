//
//  AppBranding.swift
//  Intera
//
//  User-facing product name (App Store / home screen / in-app copy). Keep in sync with
//  `INFOPLIST_KEY_CFBundleDisplayName` and `INFOPLIST_KEY_CFBundleName` in the Intera target.
//  Google Sign-In’s system sheet uses CFBundleName (not display name).
//

import Foundation

enum AppBranding {
    /// Shown under the app icon and in user-visible strings (Guideline 2.3.8).
    static let displayName = "Avila Platforms"
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
