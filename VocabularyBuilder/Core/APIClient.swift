//
//  APIClient.swift
//  vocabulary_builder
//
//  URLSession-backed client for the .NET 10 vocabulary API. See API.md for
//  the full endpoint reference and IOS_PORTING_GUIDE.md §5 for the design
//  rationale. Every method goes through `send`, which centralises JSON
//  encoding, status-code handling, and the 500-empty-body special case.
//

import Foundation

@MainActor
final class APIClient: ObservableObject {
    @Published var baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // 180s matches the API's HttpClient timeout. AI endpoints can take
        // 10–30s and OCR up to 40s in practice.
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIDate.decode(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(raw)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(APIDate.encode(date))
        }
        self.encoder = encoder
    }

    // MARK: - URL helpers

    func mediaURL(_ kind: MediaKind, _ id: String) -> URL {
        baseURL.appendingPathComponent("/api/media/\(kind.rawValue)/\(id)")
    }

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    // MARK: - Core send

    /// Send a request and decode the response. Handles every wire-format
    /// quirk documented in API.md §3 + §17 in one place.
    private func send<Body: Encodable, T: Decodable>(
        _ method: String,
        _ path: String,
        body: Body? = nil
    ) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try encoder.encode(body) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(fromStatus: http.statusCode, body: data)
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("Could not decode server response (\(error))")
        }
    }

    /// Overload for endpoints with no request body. Uses a typed
    /// `NoBody` placeholder so we don't need `Optional<Never>` (which
    /// became Encodable only in iOS 17).
    private func send<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await send(method, path, body: NoBody())
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws -> AuthUser {
        let envelope: AuthUserEnvelope = try await send(
            "POST", "/api/auth/sign-up",
            body: AuthRequest(email: email.lowercased(), password: password)
        )
        return envelope.user
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        let envelope: AuthUserEnvelope = try await send(
            "POST", "/api/auth/sign-in",
            body: AuthRequest(email: email.lowercased(), password: password)
        )
        return envelope.user
    }

    // MARK: - Words

    func listWords() async throws -> [Vocabulary] {
        try await send("GET", "/api/words")
    }

    func getWord(id: UUID) async throws -> Vocabulary {
        try await send("GET", "/api/words/\(id.uuidString.lowercased())")
    }

    /// POST /api/words — adopt the server-assigned `id` from the response.
    /// See API.md §17.4.
    @discardableResult
    func createWord(_ word: VocabularyWrite) async throws -> Vocabulary {
        try await send("POST", "/api/words", body: word)
    }

    @discardableResult
    func updateWord(id: UUID, _ word: VocabularyWrite) async throws -> Vocabulary {
        try await send("PUT", "/api/words/\(id.uuidString.lowercased())", body: word)
    }

    func deleteWord(id: UUID) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/words/\(id.uuidString.lowercased())")
    }

    // MARK: - Collections

    func listCollections() async throws -> [WordCollection] {
        try await send("GET", "/api/collections")
    }

    @discardableResult
    func createCollection(_ c: CollectionWrite) async throws -> WordCollection {
        try await send("POST", "/api/collections", body: c)
    }

    @discardableResult
    func updateCollection(id: UUID, _ c: CollectionWrite) async throws -> WordCollection {
        try await send("PUT", "/api/collections/\(id.uuidString.lowercased())", body: c)
    }

    func deleteCollection(id: UUID) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/collections/\(id.uuidString.lowercased())")
    }

    // MARK: - Progress

    /// Returns `nil` when the server responds `200` + `null` (the documented
    /// shape for "no record yet"). See API.md §9 + §17.6.
    func getProgress(wordId: UUID) async throws -> WordProgress? {
        let url = url("/api/progress/\(wordId.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(fromStatus: http.statusCode, body: data)
        }
        // The server literally writes the JSON null token; `Data` is "null".
        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "null" { return nil }
        }
        do {
            return try decoder.decode(WordProgress.self, from: data)
        } catch {
            throw APIError.decoding("Could not decode progress (\(error))")
        }
    }

    /// POST is a full replace of the stored record, not a delta. Send
    /// complete counters. See API.md §9 + §17.
    @discardableResult
    func upsertProgress(_ p: WordProgress) async throws -> WordProgress {
        try await send("POST", "/api/progress", body: p)
    }

    func listProgress() async throws -> [WordProgress] {
        try await send("GET", "/api/progress")
    }

    // MARK: - Media

    @discardableResult
    func uploadImage(id: String, data: Data, mimeType: String = "image/jpeg") async throws -> MediaUploadResponse {
        let payload = MediaUploadRequest(
            id: id,
            mimeType: mimeType,
            data: data.base64EncodedString()
        )
        return try await send("POST", "/api/media/images", body: payload)
    }

    func deleteImage(id: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/media/images/\(id)")
    }

    @discardableResult
    func uploadAudio(id: String, data: Data, mimeType: String = "audio/mpeg") async throws -> MediaUploadResponse {
        let payload = MediaUploadRequest(
            id: id,
            mimeType: mimeType,
            data: data.base64EncodedString()
        )
        return try await send("POST", "/api/media/audio", body: payload)
    }

    func deleteAudio(id: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/media/audio/\(id)")
    }

    // MARK: - Storage / account

    func storageUsage() async throws -> StorageUsage {
        try await send("GET", "/api/storage/usage")
    }

    func resetAccount() async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/account/data")
    }

    // MARK: - Quiz

    /// At most 30 words are processed server-side; extras are silently
    /// dropped. See API.md §12.
    func ensureQuiz(words: [QuizWordRequest]) async throws -> QuizEnsureResponse {
        try await send("POST", "/api/quiz/ensure", body: QuizEnsureRequest(words: words))
    }

    // MARK: - AI

    func enrichWord(word: String, context: String) async throws -> EnrichedWord {
        try await send("POST", "/api/ai/enrich-word",
                       body: EnrichWordRequest(word: word, context: context))
    }

    func generateCollection(subject: String, count: Int) async throws -> [GeneratedWord] {
        let response: GenerateCollectionResponse = try await send(
            "POST", "/api/ai/generate-collection",
            body: GenerateCollectionRequest(subject: subject, count: count)
        )
        return response.words
    }

    func extractFromImage(base64: String, targetLevel: String) async throws -> OcrExtraction {
        struct Req: Encodable { let imageBase64: String; let targetLevel: String }
        return try await send("POST", "/api/ai/extract-from-image",
                              body: Req(imageBase64: base64, targetLevel: targetLevel))
    }

    func categorize(words: [CategorizeWordsRequest.CategorizeWord],
                    existingNames: [String]) async throws -> [WordGrouping] {
        let response: CategorizeWordsResponse = try await send(
            "POST", "/api/ai/categorize-words",
            body: CategorizeWordsRequest(words: words, existingCollectionNames: existingNames)
        )
        return response.collections
    }

    // MARK: - Settings

    func getSettings(userId: UUID) async throws -> UserSettings {
        try await send("GET", "/api/users/\(userId.uuidString.lowercased())/settings")
    }

    /// Re-read the response — the server sanitises values. See API.md §14.
    @discardableResult
    func updateSettings(userId: UUID, _ s: UpdateUserSettingsRequest) async throws -> UserSettings {
        try await send("PUT", "/api/users/\(userId.uuidString.lowercased())/settings", body: s)
    }
}

// MARK: - Supporting types

enum MediaKind: String {
    case images
    case audio
}

struct EmptyResponse: Decodable {}

/// iOS 15-compatible placeholder for "no request body" endpoints.
struct NoBody: Encodable {}
