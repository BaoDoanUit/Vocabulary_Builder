//
//  VocabularyTests.swift
//  Vocabulary
//

import XCTest
@testable import Vocabulary

final class VocabularyTests: XCTestCase {
    @MainActor
    func testWordStoreLoads() {
        let store = WordStore()
        XCTAssertFalse(store.words.isEmpty, "Word list should not be empty")
    }

    @MainActor
    func testNewWordsDefaultToNewStatus() {
        let store = WordStore()
        if let first = store.words.first {
            XCTAssertEqual(store.status(for: first), .new)
        }
    }

    @MainActor
    func testMarkingWordAsKnownPersists() {
        let store = WordStore()
        guard let first = store.words.first else { return XCTFail("No words") }
        store.setStatus(.known, for: first)
        XCTAssertEqual(store.status(for: first), .known)

        // A new store should preserve the status (UserDefaults round trip)
        let store2 = WordStore()
        XCTAssertEqual(store2.status(for: first), .known)

        // Clean up so other tests start fresh
        store2.setStatus(.new, for: first)
    }

    @MainActor
    func testStudyDeckIncludesNewAndLearning() {
        let store = WordStore()
        guard let first = store.words.first else { return XCTFail("No words") }
        store.setStatus(.learning, for: first)
        let deck = store.studyDeck()
        XCTAssertTrue(deck.contains { $0.id == first.id }, "Learning word should appear in deck")
        // Clean up
        store.setStatus(.new, for: first)
    }

    @MainActor
    func testQuizChoicesIncludesCorrectAnswer() {
        let store = WordStore()
        guard let first = store.words.first else { return XCTFail("No words") }
        let choices = store.quizChoices(for: first, count: 4)
        XCTAssertEqual(choices.count, 4)
        XCTAssertTrue(choices.contains(first.vietnamese))
    }

    @MainActor
    func testCountStats() {
        let store = WordStore()
        let c = store.counts
        XCTAssertEqual(c.new + c.learning + c.known, store.words.count)
    }
}
