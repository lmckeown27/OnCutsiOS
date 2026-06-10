//
//  MessagingCommunitySafety.swift
//  Intera
//
//  Terms gate + blocked-user set for messaging (App Store UGC / Guideline 1.2).
//

import Foundation

enum MessagingCommunitySafety {
    private static let termsAcceptedKey = "InteraMessagingUGCTermsAcceptedV1"
    private static let blockedUsersKey = "InteraMessagingBlockedUserIdsV1"

    static var hasAcceptedMessagingTerms: Bool {
        UserDefaults.standard.bool(forKey: termsAcceptedKey)
    }

    static func setMessagingTermsAccepted() {
        UserDefaults.standard.set(true, forKey: termsAcceptedKey)
    }

    /// Locally cached blocked user IDs (messaging account UUIDs). Merged with server on inbox load.
    static func locallyBlockedUserIds() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: blockedUsersKey) ?? []
        return Set(arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    static func addLocallyBlockedUserId(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        var s = locallyBlockedUserIds()
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: blockedUsersKey)
    }

    /// Overwrites the cached set with **exactly** what `GET /messages/blocks` returns.
    ///
    /// Previously this **unioned** server ids with the existing cache, so a user who unblocked on the web
    /// (or another client) still appeared blocked on iOS until the stale id was manually cleared.
    static func replaceLocallyBlockedUserIdsFromServer(_ ids: [String]) {
        let next = Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        UserDefaults.standard.set(Array(next), forKey: blockedUsersKey)
    }

    static func shouldHideConversation(otherUserId: String?) -> Bool {
        guard let o = otherUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty else { return false }
        return locallyBlockedUserIds().contains(o)
    }

    /// Whether this **messaging user id** (sender / counterparty UUID) is blocked for the current account.
    static func isMessagingUserBlocked(_ messagingUserId: String) -> Bool {
        let id = messagingUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        return locallyBlockedUserIds().contains(id)
    }
}

enum InteraMessagingContentFilter {
    /// Lightweight client-side filter for obvious abuse (not a substitute for human moderation).
    static func textViolatesCommunityRules(_ raw: String) -> Bool {
        let s = raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let banned = [
            "kill yourself", "kys", "nazi", "child porn", "cp ", "rape ",
            "child abuse", "sexual assault", "terrorist attack", "mass shooting",
            "school shooting", "bomb threat", "i will kill you", "i'll kill you",
            "commit suicide", "end your life", "sextortion", "revenge porn",
        ]
        return banned.contains { s.contains($0) }
    }

    /// Replaces clearly violating **incoming** message text so objectionable content is not shown verbatim.
    static func displayTextForIncomingCommunity(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return raw }
        if textViolatesCommunityRules(t) {
            return "This message was hidden because it may violate community guidelines."
        }
        return raw
    }
}
