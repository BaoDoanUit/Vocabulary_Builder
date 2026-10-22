//
//  Word.swift
//  Vocabulary
//

import Foundation

enum WordStatus: String, Codable, CaseIterable {
    case new
    case learning
    case known

    var label: String {
        switch self {
        case .new:      return "New"
        case .learning: return "Learning"
        case .known:    return "Known"
        }
    }
}

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let english: String
    let vietnamese: String
    let pronunciation: String?
    let example: String?
    let category: String

    init(id: String = UUID().uuidString,
         english: String,
         vietnamese: String,
         pronunciation: String? = nil,
         example: String? = nil,
         category: String = "General") {
        self.id = id
        self.english = english
        self.vietnamese = vietnamese
        self.pronunciation = pronunciation
        self.example = example
        self.category = category
    }
}
