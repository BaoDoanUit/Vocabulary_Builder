//
//  VocabularyApp.swift
//  Vocabulary
//

import SwiftUI

@main
struct VocabularyApp: App {
    @StateObject private var store = WordStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
