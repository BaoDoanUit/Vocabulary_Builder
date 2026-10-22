//
//  APIError.swift
//  vocabulary_builder
//
//  The API has exactly one error shape: `{ "error": "..." }` — except for
//  `500`, which returns an empty body because no exception-handling
//  middleware is registered. Handle that explicitly. See API.md §3 and
//  IOS_PORTING_GUIDE.md §5.4.
//

import Foundation

enum APIError: LocalizedError, Equatable {
    case server(status: Int, message: String)
    case decoding(String)
    case network(String)

    init(fromStatus status: Int, body: Data) {
        // 500s are always empty — never assume JSON.
        if status == 500 {
            self = .server(
                status: 500,
                message: "Something went wrong on the server. Please try again."
            )
            return
        }
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: body) {
            self = .server(status: status, message: payload.error)
        } else {
            self = .server(
                status: status,
                message: "Request failed (\(status))."
            )
        }
    }

    var errorDescription: String? {
        switch self {
        case .server(_, let m), .decoding(let m), .network(let m):
            return m
        }
    }

    /// True for transient failures that are safe to retry automatically.
    /// 4xx responses (except 408/429) are not retried.
    var isRetryable: Bool {
        switch self {
        case .server(let status, _):
            return status >= 500 || status == 408 || status == 429
        case .network:
            return true
        case .decoding:
            return false
        }
    }
}

private struct ErrorPayload: Decodable {
    let error: String
}
