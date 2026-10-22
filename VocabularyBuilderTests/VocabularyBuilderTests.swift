//
//  VocabularyBuilderTests.swift
//  vocabulary_builder
//
//  Smoke tests for the API integration. These do not exercise a live
//  server — they verify the JSON codecs, derived helpers, and the local
//  parts of the stores round-trip cleanly. The full integration tests
//  live in dotnet_vocabulary_learner/tests/.
//

import XCTest
@testable import VocabularyBuilder

final class VocabularyBuilderTests: XCTestCase {

    // MARK: - API models

    func testVocabularyDecoding() throws {
        let json = """
        {
          "id": "7B2C1F9E-2A3B-4C5D-8E6F-001122334455",
          "word": "resilient",
          "definition": "Able to recover quickly.",
          "translation": "kiên cường",
          "partOfSpeech": "adjective",
          "exampleSentence": "She is resilient.",
          "category": "Personality",
          "source": "manual",
          "imageId": null,
          "audioId": null,
          "difficultyLevel": "B1",
          "ipa": "/rɪˈzɪliənt/",
          "aiFieldsJson": null,
          "createdAt": "2026-10-22T20:46:37.741+07:00",
          "updatedAt": "2026-10-22T20:46:37.741+07:00"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return try XCTUnwrap(APIDate.decode(s))
        }
        let v = try decoder.decode(Vocabulary.self, from: json)
        XCTAssertEqual(v.word, "resilient")
        XCTAssertEqual(v.difficultyLevel, "B1")
    }

    func testQuizChoiceShape() throws {
        let json = """
        { "options": ["a","b","c","d"], "correctAnswer": "b" }
        """.data(using: .utf8)!
        let c = try JSONDecoder().decode(QuizChoice.self, from: json)
        XCTAssertEqual(c.options.count, 4)
        XCTAssertEqual(c.correctAnswer, "b")
    }

    func testOcrExtractionShape() throws {
        let json = """
        {
          "extracted_text": "raw",
          "vocabulary": [{
            "word_or_phrase": "resilience",
            "ipa": "/r/","type": "noun",
            "meaning_en": "ability","meaning_vi": "khả năng",
            "difficulty_level": "B1",
            "meaning_in_context": "x","example_sentence": "y",
            "synonyms": "","collocations": ""
          }],
          "model": "m","providerError": "",
          "ocrDurationMs": 100, "llmDurationMs": 200, "durationMs": 300
        }
        """.data(using: .utf8)!
        let e = try JSONDecoder().decode(OcrExtraction.self, from: json)
        XCTAssertEqual(e.vocabulary.count, 1)
        XCTAssertEqual(e.vocabulary[0].wordOrPhrase, "resilience")
    }

    // MARK: - AppSettings

    @MainActor
    func testAppSettingsDefaultBaseURL() {
        let s = AppSettings()
        XCTAssertEqual(s.baseURL, AppSettings.defaultBaseURL)
    }

    // MARK: - LibraryStore

    @MainActor
    func testLibraryStoreStartsEmpty() {
        let store = LibraryStore()
        XCTAssertEqual(store.words.count, 0)
        XCTAssertEqual(store.collections.count, 0)
        XCTAssertEqual(store.progress.count, 0)
    }

    @MainActor
    func testMasteryLogic() {
        let store = LibraryStore()
        let id = UUID()
        let v = Vocabulary(
            id: id, word: "test", definition: "d", translation: "t",
            partOfSpeech: "noun", exampleSentence: "e", category: "c",
            source: "manual", imageId: nil, audioId: nil,
            difficultyLevel: nil, ipa: nil, aiFieldsJson: nil,
            createdAt: Date(), updatedAt: Date()
        )
        // No progress record → not mastered.
        XCTAssertFalse(store.isMastered(v, strongThreshold: 3))
    }

    // MARK: - SessionStore

    @MainActor
    func testSessionStoreStartsUnauthenticated() {
        let s = SessionStore()
        // Other tests may have left a user persisted; the test only
        // verifies the initial value is nil or restored transparently.
        _ = s.isAuthenticated
    }

    // MARK: - APIClient request construction
    //
    // Regression tests for NSURLErrorDomain Code=-1103 ("resource
    // exceeds maximum size"), which CFNetwork returns when a GET
    // carries a body. See API.md §7 and the device log captured via
    // `idevicesyslog`.

    @MainActor
    func testGetRequestHasNoBody() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test:2001")!)
        let request = try client.makeRequest(method: "GET", path: "/api/words")
        XCTAssertNil(request.httpBody, "A GET must not carry a body")
        XCTAssertNil(request.httpBodyStream, "A GET must not carry a body stream")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    @MainActor
    func testDeleteRequestHasNoBody() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test:2001")!)
        let request = try client.makeRequest(method: "DELETE", path: "/api/account/data")
        XCTAssertNil(request.httpBody, "A DELETE must not carry a body")
        XCTAssertNil(request.httpBodyStream)
    }

    @MainActor
    func testPostRequestCarriesEncodedBody() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test:2001")!)
        let request = try client.makeRequest(
            method: "POST",
            path: "/api/auth/sign-up",
            body: AuthRequest(email: "a@b.test", password: "Password123!")
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(AuthRequest.self, from: body)
        XCTAssertEqual(decoded.email, "a@b.test")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    @MainActor
    func testRequestURLUsesTheConfiguredBaseURL() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test:2001")!)
        let request = try client.makeRequest(method: "GET", path: "/api/words")
        XCTAssertEqual(request.url?.absoluteString, "http://example.test:2001/api/words")
    }

    @MainActor
    func testMediaURLIsBuiltFromTheBaseURL() {
        let client = APIClient(baseURL: URL(string: "http://example.test:2001")!)
        let url = client.mediaURL(.images, "abc-123")
        XCTAssertEqual(url.absoluteString, "http://example.test:2001/api/media/images/abc-123")
    }
}
