//
//  HTTPJSONBodyValidation.swift
//  Intera
//
//  Rejects HTML / plain-text bodies (e.g. nginx maintenance pages with HTTP 200) before JSONDecoder runs.
//

import Foundation

enum HTTPJSONBodyValidation {
    enum Error: LocalizedError {
        case notJSONObject(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .notJSONObject:
                return "CampusCuts couldn’t load data because the server returned an unexpected response. The service may be under maintenance — please try again later."
            }
        }
    }

    /// Ensures `data` begins with `{` or `[` after optional ASCII whitespace (valid JSON object/array).
    static func validateJSONObjectData(_ data: Data, httpResponse: URLResponse?) throws {
        guard !data.isEmpty else { return }
        var index = 0
        while index < data.count {
            let byte = data[index]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n")
                || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                index += 1
                continue
            }
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                return
            }
            break
        }
        let status = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        throw Error.notJSONObject(statusCode: status)
    }
}
