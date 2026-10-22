//
//  ContentView.swift
//  vocabulary_builder
//
//  Five-tab shell. Mirrors the web app's `BottomNav`. See
//  IOS_PORTING_GUIDE.md §3 and §10 phase 1.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            StudyView()
                .tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }
            QuizView()
                .tabItem { Label("Quiz", systemImage: "questionmark.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient(baseURL: AppSettings.defaultBaseURL))
        .environmentObject(SessionStore())
        .environmentObject(LibraryStore())
        .environmentObject(AppSettings())
}
