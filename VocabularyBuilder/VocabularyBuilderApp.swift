//
//  VocabularyBuilderApp.swift
//  vocabulary_builder
//
//  App entry. Wires up the APIClient + AppSettings + SessionStore +
//  LibraryStore and switches between AuthView and ContentView based on
//  the persisted session. Mirrors the React AuthProvider shell.
//

import SwiftUI

@main
struct VocabularyBuilderApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appSettings)
                .environmentObject(session)
                .environmentObject(makeApiClient())
                .environmentObject(makeLibraryStore())
        }
    }

    private func makeApiClient() -> APIClient {
        APIClient(baseURL: appSettings.baseURL)
    }

    private func makeLibraryStore() -> LibraryStore {
        LibraryStore()
    }
}
