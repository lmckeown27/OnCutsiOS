//
//  ConsumerHiddenBookingsStore.swift
//  OnCuts
//
//  When the API `POST …/hide-from-list` is unavailable (404) or before the backend is deployed,
//  we still hide past rows locally so the Bookings timeline stays usable. Scoped per consumer user id.
//

import Foundation

enum ConsumerHiddenBookingsStore {
    private static let defaultsKey = "intera.consumerHiddenBookingIdsByUser.v1"

    private static func loadMap() -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return raw.mapValues { Set($0) }
    }

    private static func saveMap(_ map: [String: Set<String>]) {
        let encodable = map.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func recordHidden(bookingId: String, consumerUserId: String) {
        let bid = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = consumerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty, !uid.isEmpty else { return }
        var map = loadMap()
        var set = map[uid] ?? []
        set.insert(bid)
        map[uid] = set
        saveMap(map)
    }

    static func filterRows(_ rows: [ConsumerBookingSimpleRow], consumerUserId: String?) -> [ConsumerBookingSimpleRow] {
        guard let uid = consumerUserId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return rows
        }
        let hidden = loadMap()[uid] ?? []
        guard !hidden.isEmpty else { return rows }
        return rows.filter { !hidden.contains($0.id) }
    }

    /// Used when re-merging supplemental detail rows — **do not** resurrect a booking the consumer hid from their list.
    static func isBookingHidden(bookingId: String, consumerUserId: String?) -> Bool {
        guard let uid = consumerUserId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return false
        }
        let bid = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { return false }
        let hidden = loadMap()[uid] ?? []
        return hidden.contains { $0.caseInsensitiveCompare(bid) == .orderedSame }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
