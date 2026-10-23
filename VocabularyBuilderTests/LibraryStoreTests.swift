//
//  LibraryStoreTests.swift
//  vocabulary_builder
//
//  Regression tests for the "import -> library" handoff.
//
//  The OCR flow used to call `api.createWord` directly. That creates
//  the word on the server but never inserts it into the LibraryStore,
//  so the Library list stayed stale and the imported words appeared to
//  vanish. These tests pin the fixed behaviour: a created word lands
//  in the local list, an existing one is replaced rather than
//  duplicated, and a failing endpoint no longer discards the results
//  of the other two.
//

import XCTest
@testable import VocabularyBuilder

final class LibraryStoreTests: XCTestCase {

    // MARK: - LibraryStore: the import -> library handoff
    //
    // Regression tests for "imported words do not appear in the
    // Library". The OCR flow used to call `api.createWord` directly,
    // which creates the word on the server but never inserts it into
    // the store, so the Library list stayed stale.

    @MainActor
    func testCreateWordInsertsIntoTheLocalStore() async throws {
        let store = LibraryStore()
        let client = StubAPIClient()
        let created = try await store.createWord(
            api: client,
            VocabularyWrite(
                word: "versatile", definition: "Able to adapt.",
                translation: "đa năng", partOfSpeech: "adjective",
                exampleSentence: "A versatile tool.", category: "OCR",
                source: "ocr", imageId: nil, audioId: nil,
                difficultyLevel: "B1", ipa: "/vɜːrsətl/", aiFieldsJson: nil
            )
        )
        XCTAssertEqual(store.words.count, 1)
        XCTAssertEqual(store.words.first?.word, "versatile")
        XCTAssertEqual(store.words.first?.id, created.id)
    }

    @MainActor
    func testCreateWordUpdatesAnExistingWordInPlace() async throws {
        let store = LibraryStore()
        let client = StubAPIClient()
        let id = UUID()
        // Seed the store the way the app does: through a fetch.
        client.wordsResult = .success([StubAPIClient.sampleWord(id: id, word: "old")])
        await store.reloadWords(api: client)

        client.createWordResult = .success(StubAPIClient.sampleWord(id: id, word: "new"))
        _ = try await store.createWord(
            api: client,
            VocabularyWrite(
                word: "new", definition: "d", translation: "t", partOfSpeech: "noun",
                exampleSentence: "e", category: "c", source: "manual",
                imageId: nil, audioId: nil, difficultyLevel: nil, ipa: nil, aiFieldsJson: nil
            )
        )
        XCTAssertEqual(store.words.count, 1, "An existing word must be replaced, not duplicated")
        XCTAssertEqual(store.words.first?.word, "new")
    }

    @MainActor
    func testReloadPopulatesAllThreeCollections() async {
        let store = LibraryStore()
        let client = StubAPIClient()
        let wordId = UUID()
        client.wordsResult = .success([StubAPIClient.sampleWord(id: wordId)])
        client.collectionsResult = .success([])
        client.progressResult = .success([
            WordProgress(
                wordId: wordId, attempts: 1, correct: 1, incorrect: 0,
                studyCount: 2, lastSeenAt: Date(), isWeak: false, consecutiveCorrect: 1
            )
        ])

        await store.reload(api: client)

        XCTAssertEqual(store.words.count, 1)
        XCTAssertEqual(store.collections.count, 0)
        XCTAssertEqual(store.progress.count, 1)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testReloadKeepsWordsWhenAnotherEndpointFails() async {
        // The three endpoints used to be awaited as one tuple, so a
        // failure in any one of them discarded all three results and
        // the Library silently kept a stale list.
        let store = LibraryStore()
        let client = StubAPIClient()
        client.wordsResult = .success([StubAPIClient.sampleWord(word: "kept")])
        client.collectionsResult = .failure(.network("collections down"))
        client.progressResult = .failure(.network("progress down"))

        await store.reload(api: client)

        XCTAssertEqual(store.words.count, 1, "Words must survive a failure in another endpoint")
        XCTAssertEqual(store.words.first?.word, "kept")
        XCTAssertNotNil(store.lastError, "The failure must still be reported")
    }

    @MainActor
    func testReloadKeepsOtherCollectionsWhenWordsFail() async {
        let store = LibraryStore()
        let client = StubAPIClient()
        client.wordsResult = .failure(.network("words down"))
        client.collectionsResult = .success([
            WordCollection(
                id: UUID(), name: "Exam 2026", description: "", wordIds: [],
                source: "manual", createdAt: Date(), updatedAt: Date()
            )
        ])
        client.progressResult = .success([])

        await store.reload(api: client)

        XCTAssertEqual(store.collections.count, 1, "Collections must survive a words failure")
        XCTAssertNotNil(store.lastError)
    }

    @MainActor
    func testReloadKeepsThePreviousWordListWhenTheFetchFails() async {
        let store = LibraryStore()
        let client = StubAPIClient()
        client.wordsResult = .success([StubAPIClient.sampleWord(word: "original")])
        await store.reload(api: client)
        XCTAssertEqual(store.words.count, 1)

        client.wordsResult = .failure(.network("offline"))
        await store.reload(api: client)

        XCTAssertEqual(store.words.count, 1, "The last good list must be kept")
        XCTAssertEqual(store.words.first?.word, "original")
    }

    @MainActor
    func testReloadHandlesDuplicateProgressWordIds() async {
        // Dictionary(uniqueKeysWithValues:) traps on a duplicate key.
        let store = LibraryStore()
        let client = StubAPIClient()
        let wordId = UUID()
        let record = WordProgress(
            wordId: wordId, attempts: 1, correct: 1, incorrect: 0,
            studyCount: 1, lastSeenAt: nil, isWeak: false, consecutiveCorrect: 1
        )
        client.progressResult = .success([record, record])

        await store.reload(api: client)

        XCTAssertEqual(store.progress.count, 1)
    }

    @MainActor
    func testFreshnessWindowTracksTheLastSuccessfulFetch() async {
        let store = LibraryStore()
        let client = StubAPIClient()
        XCTAssertFalse(store.wordsAreFresh, "A store that has never loaded is not fresh")

        client.wordsResult = .success([StubAPIClient.sampleWord()])
        await store.reloadWords(api: client)
        XCTAssertTrue(store.wordsAreFresh, "A just-loaded store is fresh")
    }

    @MainActor
    func testCreateWordMarksTheStoreFresh() async throws {
        // After an import the list must not be refetched, so a local
        // insert has to refresh the freshness stamp.
        let store = LibraryStore()
        let client = StubAPIClient()
        _ = try await store.createWord(
            api: client,
            VocabularyWrite(
                word: "w", definition: "d", translation: "t", partOfSpeech: "noun",
                exampleSentence: "e", category: "c", source: "manual",
                imageId: nil, audioId: nil, difficultyLevel: nil, ipa: nil, aiFieldsJson: nil
            )
        )
        XCTAssertTrue(store.wordsAreFresh)
    }

    @MainActor
    func testConcurrentReloadsShareOneWordRequest() async {
        // `GET /api/words` is ~427 KB. The root view, the home screen and
        // the library tab can all ask for it at once when the app opens,
        // so concurrent callers must share a single request.
        let store = LibraryStore()
        let client = StubAPIClient()
        client.wordsResult = .success([StubAPIClient.sampleWord(word: "shared")])
        // Slow the response down so the three calls really do overlap.
        client.listWordsDelay = 0.05

        async let a: Void = store.reloadWords(api: client)
        async let b: Void = store.reloadWords(api: client)
        async let c: Void = store.reload(api: client)
        _ = await (a, b, c)

        XCTAssertEqual(
            client.calls.filter { $0 == "listWords" }.count, 1,
            "Concurrent reloads must not each download the word list"
        )
        XCTAssertEqual(store.words.count, 1)
        XCTAssertEqual(store.words.first?.word, "shared")
    }
}
