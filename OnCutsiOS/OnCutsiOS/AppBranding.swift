//
//  AppBranding.swift
//  OnCuts
//
//  User-facing product name (App Store / home screen / in-app copy). Keep in sync with
//  `CFBundleDisplayName` and `CFBundleName` in `GoogleSignInURL.plist`.
//  Google Sign-In’s system sheet uses CFBundleName (not display name).
//

import Foundation

enum AppBranding {
    /// Consumer product brand — app icon label, in-app copy, OAuth system name.
    static let displayName = "OnCuts"
    /// Internal repo / docs product label (App Store bundle ID: `com.oncutsclient.app`).
    static let bundleIdentifier = "com.oncutsclient.app"
    static let applePayMerchantIdentifier = "merchant.com.oncuts"
    static let productName = "OnCuts"
    /// Legal entity / company behind the product (Terms, support, provider platform references).
    static let companyName = "OnCuts"
    static let companyWebsiteHost = "oncuts.com"
    static let supportEmail = "support@oncuts.com"

    static var companyWebsiteURL: URL {
        URL(string: "https://\(companyWebsiteHost)")!
    }

    static var termsOfServiceURL: URL {
        URL(string: "https://\(companyWebsiteHost)/terms")!
    }

    static var privacyPolicyURL: URL {
        URL(string: "https://\(companyWebsiteHost)/privacy")!
    }
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
