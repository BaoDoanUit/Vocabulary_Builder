//
//  APIModels.swift
//  vocabulary_builder
//
//  Wire-format DTOs that mirror openapi.yaml verbatim. Field names are
//  load-bearing — a mismatch silently drops data. See API.md §15 for the
//  data model reference and §17 for the wire-format quirks (notably the
//  `aiFieldsJson` JSON-string-in-a-string wart and the
//  GET /api/progress/{wordId} returns 200 + null behaviour).
//

import Foundation

// MARK: - Date codec

/// All timestamps are ISO-8601 / RFC 3339 with an offset
/// (e.g. `2026-10-22T20:46:37.741+07:00`). The web app's reference
/// implementation parses them with `new Date(...)`, which accepts that
/// shape. Foundation's `ISO8601DateFormatter` does not include fractional
/// seconds by default — configure it to.
enum APIDate {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func encode(_ date: Date) -> String { formatter.string(from: date) }

    static func decode(_ raw: String) -> Date? {
        formatter.date(from: raw) ?? fallback.date(from: raw)
    }
}

// MARK: - Auth

struct AuthRequest: Encodable {
    let email: String
    let password: String
}

struct AuthUser: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let createdAt: Date
    let updatedAt: Date
}

struct AuthUserEnvelope: Decodable {
    let user: AuthUser
}

// MARK: - Vocabulary

/// Full server-side representation of a word. The server owns `id`,
/// `createdAt` and `updatedAt` — the write body uses `VocabularyWrite`.
struct Vocabulary: Codable, Identifiable, Hashable {
    let id: UUID
    var word: String
    var definition: String
    var translation: String
    var partOfSpeech: String
    var exampleSentence: String
    var category: String
    var source: String
    var imageId: String?
    var audioId: String?
    var difficultyLevel: String?
    var ipa: String?
    /// A JSON-encoded STRING, not a nested object. See API.md §17.2.
    var aiFieldsJson: String?
    let createdAt: Date
    var updatedAt: Date
}

/// Request body for word create/update. The server regenerates `id` and
/// timestamps on POST, so any values sent here are ignored.
struct VocabularyWrite: Encodable {
    var word: String
    var definition: String
    var translation: String
    var partOfSpeech: String
    var exampleSentence: String
    var category: String
    var source: String
    var imageId: String?
    var audioId: String?
    var difficultyLevel: String?
    var ipa: String?
    var aiFieldsJson: String?
}

// MARK: - Collection

struct WordCollection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var wordIds: [UUID]
    var source: String
    let createdAt: Date
    var updatedAt: Date
}

struct CollectionWrite: Encodable {
    var name: String
    var description: String
    var wordIds: [UUID]
    var source: String
}

struct CollectionReplaceRequest: Encodable {
    let collections: [CollectionWrite]
}

// MARK: - Progress

struct WordProgress: Codable, Hashable {
    var wordId: UUID
    var attempts: Int
    var correct: Int
    var incorrect: Int
    var studyCount: Int
    var lastSeenAt: Date?
    var isWeak: Bool
    var consecutiveCorrect: Int
}

// MARK: - Quiz

struct QuizChoice: Codable, Hashable {
    let options: [String]
    let correctAnswer: String
}

struct QuizFillGap: Codable, Hashable {
    let prompt: String
    let options: [String]
    let correctAnswer: String
}

struct QuizItem: Codable, Identifiable, Hashable {
    var id: UUID { wordId }
    let wordId: UUID
    /// Note the inversion: `wordToDef` shows the definition and asks for
    /// the word. `defToWord` is the reverse. The names read backwards from
    /// their meaning. See API.md §12.
    let wordToDef: QuizChoice
    let defToWord: QuizChoice
    let fillInGap: QuizFillGap
    let model: String
    let updatedAt: Date
}

struct QuizWordRequest: Encodable {
    let id: String
    let word: String
    let definition: String
    let category: String?
    let partOfSpeech: String?
    let exampleSentence: String?
    let difficulty: String?
    let candidateWords: [String]?
    let candidateDefinitions: [String]?
}

struct QuizEnsureRequest: Encodable {
    let words: [QuizWordRequest]
}

struct QuizEnsureResponse: Decodable {
    let quizzes: [QuizItem]
    let model: String
}

// MARK: - Media

struct MediaUploadRequest: Encodable {
    let id: String
    let mimeType: String
    let data: String // raw base64 (no data: prefix)
}

struct MediaUploadResponse: Decodable {
    let id: String
    let url: String
}

struct StorageUsage: Decodable, Hashable {
    let imageBytes: Int64
    let audioBytes: Int64
    let totalBytes: Int64
}

// MARK: - AI

struct EnrichWordRequest: Encodable {
    let word: String
    let context: String
}

struct EnrichedWord: Decodable, Hashable {
    let word: String
    let ipa: String
    let definition: String
    let translation: String
    let partOfSpeech: String
    let exampleSentence: String
    let category: String
    let difficulty: String
    /// Comma-separated strings, not arrays.
    let synonyms: String
    let collocations: String
}

struct GenerateCollectionRequest: Encodable {
    let subject: String
    let count: Int
}

struct GenerateCollectionResponse: Decodable {
    let words: [GeneratedWord]
}

struct GeneratedWord: Decodable, Hashable {
    let word: String
    let ipa: String
    let definition: String
    let translation: String
    let partOfSpeech: String
    let exampleSentence: String
    let category: String
    let difficulty: String
}

/// `POST /api/ai/extract-from-image` is the one endpoint that returns
/// snake_case vocabulary items. See API.md §13 and §17.
struct OcrExtraction: Decodable {
    var extractedText: String
    var vocabulary: [OcrVocabularyItem]
    let model: String
    let providerError: String
    let ocrDurationMs: Int
    let llmDurationMs: Int
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case extractedText = "extracted_text"
        case vocabulary
        case model
        case providerError
        case ocrDurationMs
        case llmDurationMs
        case durationMs
    }
}

struct OcrVocabularyItem: Decodable, Hashable {
    var wordOrPhrase: String
    var ipa: String
    var type: String
    var meaningEn: String
    var meaningVi: String
    var difficultyLevel: String
    var meaningInContext: String
    var exampleSentence: String
    var synonyms: String
    var collocations: String

    enum CodingKeys: String, CodingKey {
        case wordOrPhrase = "word_or_phrase"
        case ipa
        case type
        case meaningEn = "meaning_en"
        case meaningVi = "meaning_vi"
        case difficultyLevel = "difficulty_level"
        case meaningInContext = "meaning_in_context"
        case exampleSentence = "example_sentence"
        case synonyms
        case collocations
    }

    init(wordOrPhrase: String, ipa: String, type: String, meaningEn: String,
         meaningVi: String, difficultyLevel: String, meaningInContext: String,
         exampleSentence: String, synonyms: String, collocations: String) {
        self.wordOrPhrase = wordOrPhrase
        self.ipa = ipa
        self.type = type
        self.meaningEn = meaningEn
        self.meaningVi = meaningVi
        self.difficultyLevel = difficultyLevel
        self.meaningInContext = meaningInContext
        self.exampleSentence = exampleSentence
        self.synonyms = synonyms
        self.collocations = collocations
    }

    /// Map to the canonical Vocabulary shape for display in the picker
    /// before the user has enriched/saved any of them.
    func toVocabularyWrite(source: String = "ocr") -> VocabularyWrite {
        VocabularyWrite(
            word: wordOrPhrase,
            definition: meaningEn,
            translation: meaningVi,
            partOfSpeech: type,
            exampleSentence: exampleSentence,
            category: "OCR",
            source: source,
            imageId: nil,
            audioId: nil,
            difficultyLevel: difficultyLevel.isEmpty ? nil : difficultyLevel,
            ipa: ipa.isEmpty ? nil : ipa,
            aiFieldsJson: nil
        )
    }
}

struct WordGrouping: Decodable, Hashable {
    let name: String
    let description: String
    let wordIds: [UUID]
}

struct CategorizeWordsRequest: Encodable {
    let words: [CategorizeWord]
    let existingCollectionNames: [String]

    struct CategorizeWord: Encodable, Hashable {
        let id: String
        let word: String
    }
}

struct CategorizeWordsResponse: Decodable {
    let collections: [WordGrouping]
}

// MARK: - Settings

struct UserSettings: Codable, Hashable {
    var userId: UUID
    var weakThreshold: Int
    var strongThreshold: Int
    var quizSize: Int
    var vocabularyLevel: String
    var hasCompletedOnboarding: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct UpdateUserSettingsRequest: Encodable {
    let weakThreshold: Int
    let strongThreshold: Int
    let quizSize: Int
    let vocabularyLevel: String
    let hasCompletedOnboarding: Bool
}

// MARK: - Helpers

extension Vocabulary {
    /// Web app display order: `updatedAt ?? createdAt` descending, then
    /// `word` alphabetical. See API.md §16.
    var displaySortKey: Date { updatedAt }

    var hasImage: Bool { imageId?.isEmpty == false }
}
