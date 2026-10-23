//
//  StubAPIClient.swift
//  VocabularyBuilderTests
//
//  A scriptable APIClientProtocol implementation, so the store can be
//  tested without a network. Each endpoint can be told to succeed or
//  fail, which is how the "one endpoint fails, the others survive"
//  behaviour is exercised.
//

import Foundation
@testable import VocabularyBuilder

@MainActor
final class StubAPIClient: APIClientProtocol {
    var wordsResult: Result<[Vocabulary], APIError> = .success([])
    var collectionsResult: Result<[WordCollection], APIError> = .success([])
    var progressResult: Result<[WordProgress], APIError> = .success([])
    var createWordResult: Result<Vocabulary, APIError>?

    /// Records the order the endpoints were called in.
    private(set) var calls: [String] = []

    /// Artificial delay for `listWords`, used to make overlapping
    /// requests actually overlap.
    var listWordsDelay: TimeInterval = 0

    func listWords() async throws -> [Vocabulary] {
        calls.append("listWords")
        if listWordsDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(listWordsDelay * 1_000_000_000))
        }
        return try wordsResult.get()
    }

    func createWord(_ word: VocabularyWrite) async throws -> Vocabulary {
        calls.append("createWord")
        if let createWordResult { return try createWordResult.get() }
        return StubAPIClient.sampleWord(word: word.word)
    }

    func updateWord(id: UUID, _ word: VocabularyWrite) async throws -> Vocabulary {
        calls.append("updateWord")
        return StubAPIClient.sampleWord(word: word.word)
    }

    func deleteWord(id: UUID) async throws {
        calls.append("deleteWord")
    }

    func listCollections() async throws -> [WordCollection] {
        calls.append("listCollections")
        return try collectionsResult.get()
    }

    func createCollection(_ c: CollectionWrite) async throws -> WordCollection {
        calls.append("createCollection")
        throw APIError.network("not needed for these tests")
    }

    func deleteCollection(id: UUID) async throws {
        calls.append("deleteCollection")
    }

    func listProgress() async throws -> [WordProgress] {
        calls.append("listProgress")
        return try progressResult.get()
    }

    func upsertProgress(_ p: WordProgress) async throws -> WordProgress {
        calls.append("upsertProgress")
        return p
    }

    func getSettings(userId: UUID) async throws -> UserSettings {
        calls.append("getSettings")
        throw APIError.network("not needed for these tests")
    }

    func updateSettings(userId: UUID, _ s: UpdateUserSettingsRequest) async throws -> UserSettings {
        calls.append("updateSettings")
        throw APIError.network("not needed for these tests")
    }

    // MARK: - Fixtures

    static func sampleWord(
        id: UUID = UUID(),
        word: String = "resilient",
        definition: String = "Able to recover quickly.",
        translation: String = "kiên cường",
        category: String = "Personality",
        createdAt: Date = Date()
    ) -> Vocabulary {
        Vocabulary(
            id: id,
            word: word,
            definition: definition,
            translation: translation,
            partOfSpeech: "adjective",
            exampleSentence: "She is resilient.",
            category: category,
            source: "manual",
            imageId: nil,
            audioId: nil,
            difficultyLevel: "B1",
            ipa: "/rɪˈzɪliənt/",
            aiFieldsJson: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
