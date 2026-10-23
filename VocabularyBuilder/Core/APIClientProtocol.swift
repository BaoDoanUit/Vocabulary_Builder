//
//  APIClientProtocol.swift
//  vocabulary_builder
//
//  The endpoint surface of the API, as a protocol. `APIClient` is the
//  production implementation; the protocol exists so `LibraryStore` and
//  the feature view models can be unit-tested without a network.
//
//  Only the endpoints the stores actually use are declared here. The
//  feature views keep using the concrete `APIClient`.
//

import Foundation

@MainActor
protocol APIClientProtocol: AnyObject {
    // Words
    func listWords() async throws -> [Vocabulary]
    func createWord(_ word: VocabularyWrite) async throws -> Vocabulary
    func updateWord(id: UUID, _ word: VocabularyWrite) async throws -> Vocabulary
    func deleteWord(id: UUID) async throws

    // Collections
    func listCollections() async throws -> [WordCollection]
    func createCollection(_ c: CollectionWrite) async throws -> WordCollection
    func deleteCollection(id: UUID) async throws

    // Progress
    func listProgress() async throws -> [WordProgress]
    func upsertProgress(_ p: WordProgress) async throws -> WordProgress

    // Settings
    func getSettings(userId: UUID) async throws -> UserSettings
    func updateSettings(userId: UUID, _ s: UpdateUserSettingsRequest) async throws -> UserSettings
}

extension APIClient: APIClientProtocol {}
