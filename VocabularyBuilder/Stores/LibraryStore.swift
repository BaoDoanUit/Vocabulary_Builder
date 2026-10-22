//
//  LibraryStore.swift
//  vocabulary_builder
//
//  The shared words / collections / progress cache. Mirrors what
//  hooks/useData.ts does in the web app: every screen filters the same
//  in-memory array rather than refetching. See IOS_PORTING_GUIDE.md §4
//  and §9.
//

import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var words: [Vocabulary] = []
    @Published private(set) var collections: [WordCollection] = []
    @Published private(set) var progress: [UUID: WordProgress] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: APIError?

    var sortedWords: [Vocabulary] {
        // API.md §16: updatedAt ?? createdAt desc, then word alphabetical.
        words.sorted { lhs, rhs in
            if lhs.displaySortKey != rhs.displaySortKey {
                return lhs.displaySortKey > rhs.displaySortKey
            }
            return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
        }
    }

    var categories: [String] {
        Array(Set(words.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    var wordCount: Int { words.count }
    var weakCount: Int { progress.values.filter(\.isWeak).count }

    /// Bucket the catalogue using a mastery threshold (typically the
    /// user's `strongThreshold` from settings). Mirrors the web app's
    /// "WORDS / DUE / WEAK" stat tiles.
    func stats(strongThreshold: Int) -> (new: Int, learning: Int, known: Int) {
        var n = 0, l = 0, k = 0
        for word in words {
            if isMastered(word, strongThreshold: strongThreshold) { k += 1 }
            else if progress[word.id] != nil { l += 1 }
            else { n += 1 }
        }
        return (n, l, k)
    }

    func words(in category: String) -> [Vocabulary] {
        words.filter { $0.category == category }
    }

    func progress(for word: Vocabulary) -> WordProgress? {
        progress[word.id]
    }

    /// Mastery = correct >= strongThreshold and not weak. Mirrors the
    /// web app's logic exactly.
    func isMastered(_ word: Vocabulary, strongThreshold: Int = 3) -> Bool {
        guard let p = progress[word.id] else { return false }
        return p.correct >= strongThreshold && !p.isWeak
    }

    func collection(id: UUID) -> WordCollection? {
        collections.first { $0.id == id }
    }

    func collections(containing wordId: UUID) -> [WordCollection] {
        collections.filter { $0.wordIds.contains(wordId) }
    }

    // MARK: - Loading

    func reload(api: APIClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let wordsTask = api.listWords()
            async let collectionsTask = api.listCollections()
            async let progressTask = api.listProgress()
            let (loadedWords, loadedCollections, loadedProgress) = try await (wordsTask, collectionsTask, progressTask)
            self.words = loadedWords
            self.collections = loadedCollections
            self.progress = Dictionary(uniqueKeysWithValues: loadedProgress.map { ($0.wordId, $0) })
            self.lastError = nil
        } catch let error as APIError {
            self.lastError = error
        } catch {
            self.lastError = .network(error.localizedDescription)
        }
    }

    // MARK: - Word mutations

    @discardableResult
    func createWord(api: APIClient, _ write: VocabularyWrite) async throws -> Vocabulary {
        let created = try await api.createWord(write)
        // Adopt the server-assigned id (and any field changes). See API.md §17.4.
        upsertLocal(created)
        return created
    }

    func updateWord(api: APIClient, _ word: Vocabulary) async throws -> Vocabulary {
        let write = VocabularyWrite(
            word: word.word,
            definition: word.definition,
            translation: word.translation,
            partOfSpeech: word.partOfSpeech,
            exampleSentence: word.exampleSentence,
            category: word.category,
            source: word.source,
            imageId: word.imageId,
            audioId: word.audioId,
            difficultyLevel: word.difficultyLevel,
            ipa: word.ipa,
            aiFieldsJson: word.aiFieldsJson
        )
        return try await updateWord(api: api, id: word.id, with: write)
    }

    /// Full-replace update from a `VocabularyWrite` body. The stored
    /// `id` and `createdAt` win over the body; `updatedAt` is set to the
    /// server time. See API.md §7.
    func updateWord(api: APIClient, id: UUID, with write: VocabularyWrite) async throws -> Vocabulary {
        let updated = try await api.updateWord(id: id, write)
        upsertLocal(updated)
        return updated
    }

    /// Optimistic delete: remove from local state immediately, then call
    /// the API. Matches the web app's `useData.removeWords` flow. See
    /// API.md §16 + IOS_PORTING_GUIDE.md §7.4.
    func deleteWord(api: APIClient, id: UUID) async {
        let saved = words
        words.removeAll { $0.id == id }
        progress.removeValue(forKey: id)
        do {
            try await api.deleteWord(id: id)
        } catch {
            // Roll back on failure.
            words = saved
            lastError = (error as? APIError) ?? .network(error.localizedDescription)
        }
    }

    // MARK: - Collection mutations

    @discardableResult
    func createCollection(api: APIClient, _ write: CollectionWrite) async throws -> WordCollection {
        let created = try await api.createCollection(write)
        collections.append(created)
        return created
    }

    func deleteCollection(api: APIClient, id: UUID) async throws {
        try await api.deleteCollection(id: id)
        collections.removeAll { $0.id == id }
    }

    // MARK: - Progress

    /// Local-only counter update. Persists to the server with the full
    /// counters (the body is a full replace, not a delta). See API.md §9.
    func recordStudyOpen(api: APIClient, for word: Vocabulary) async {
        let existing = progress[word.id] ?? WordProgress(
            wordId: word.id, attempts: 0, correct: 0, incorrect: 0,
            studyCount: 0, lastSeenAt: nil, isWeak: false, consecutiveCorrect: 0
        )
        var next = existing
        next.studyCount += 1
        next.lastSeenAt = Date()
        progress[word.id] = next
        do {
            let stored = try await api.upsertProgress(next)
            progress[stored.wordId] = stored
        } catch {
            progress[word.id] = existing
        }
    }

    /// Apply the mastery logic from API.md §16 + IOS_PORTING_GUIDE.md §7.6
    /// and persist.
    func recordQuizAnswer(
        api: APIClient,
        for word: Vocabulary,
        correct: Bool,
        strongThreshold: Int
    ) async {
        let existing = progress[word.id] ?? WordProgress(
            wordId: word.id, attempts: 0, correct: 0, incorrect: 0,
            studyCount: 0, lastSeenAt: nil, isWeak: false, consecutiveCorrect: 0
        )
        var next = existing
        next.attempts += 1
        if correct {
            next.correct += 1
            next.consecutiveCorrect += 1
        } else {
            next.incorrect += 1
            next.consecutiveCorrect = 0
            next.isWeak = true
        }
        // A correct answer at strongThreshold clears weakness.
        if correct, next.correct >= strongThreshold {
            next.isWeak = false
        }
        next.lastSeenAt = Date()
        progress[word.id] = next
        do {
            let stored = try await api.upsertProgress(next)
            progress[stored.wordId] = stored
        } catch {
            progress[word.id] = existing
        }
    }

    // MARK: - Helpers

    private func upsertLocal(_ word: Vocabulary) {
        if let idx = words.firstIndex(where: { $0.id == word.id }) {
            words[idx] = word
        } else {
            words.append(word)
        }
    }
}
