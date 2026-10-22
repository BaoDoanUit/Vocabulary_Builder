//
//  WordStore.swift
//  Vocabulary
//
// Loads the bundled word list and persists per-word learning status to
// UserDefaults. State changes are published so SwiftUI views update live.
//

import Foundation
import Combine

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [Word] = []
    @Published var statusByWordID: [String: WordStatus] = [:]

    private let defaultsKey = "vocabulary.statusByWordID"

    init() {
        load()
        loadStatus()
    }

    // MARK: - Loading

    private func load() {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            assertionFailure("words.json missing from bundle")
            words = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            words = try JSONDecoder().decode([Word].self, from: data)
        } catch {
            assertionFailure("Failed to decode words.json: \(error)")
            words = []
        }
    }

    private func loadStatus() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let map = try? JSONDecoder().decode([String: WordStatus].self, from: data) {
            statusByWordID = map
        }
        // Words absent from the saved map default to .new
    }

    private func saveStatus() {
        if let data = try? JSONEncoder().encode(statusByWordID) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Queries

    func status(for word: Word) -> WordStatus {
        statusByWordID[word.id] ?? .new
    }

    func words(in category: String) -> [Word] {
        words.filter { $0.category == category }
    }

    var categories: [String] {
        Array(Set(words.map(\.category))).sorted()
    }

    func studyDeck() -> [Word] {
        // Prefer words that are .new or .learning; rotate .known into 1-in-3
        var deck: [Word] = []
        deck.append(contentsOf: words.filter { status(for: $0) == .new })
        deck.append(contentsOf: words.filter { status(for: $0) == .learning })
        let knownSample = words.filter { status(for: $0) == .known }
        if !knownSample.isEmpty {
            // Keep .known words in the deck at a lower frequency for review
            let stride = max(3, knownSample.count / 5)
            deck.append(contentsOf: knownSample.enumerated()
                .filter { $0.offset % stride == 0 }
                .map(\.element))
        }
        return deck.shuffled()
    }

    func quizChoices(for word: Word, count: Int = 4) -> [String] {
        // The correct answer plus `count - 1` distractors from the same category
        let sameCategory = words(in: word.category).filter { $0.id != word.id }
        var distractors = Array(Set(sameCategory.map(\.vietnamese))).shuffled()
        distractors = Array(distractors.prefix(count - 1))
        var choices = distractors + [word.vietnamese]
        choices.shuffle()
        return choices
    }

    // MARK: - Mutations

    func setStatus(_ status: WordStatus, for word: Word) {
        statusByWordID[word.id] = status
        saveStatus()
    }

    func resetProgress() {
        statusByWordID.removeAll()
        saveStatus()
    }

    // MARK: - Stats

    var counts: (new: Int, learning: Int, known: Int) {
        var n = 0, l = 0, k = 0
        for w in words {
            switch status(for: w) {
            case .new:      n += 1
            case .learning: l += 1
            case .known:    k += 1
            }
        }
        return (n, l, k)
    }
}
