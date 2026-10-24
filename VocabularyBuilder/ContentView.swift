//
//  ContentView.swift
//  vocabulary_builder
//
//  Five-tab shell. Mirrors the web app's `BottomNav`. See
//  IOS_PORTING_GUIDE.md §3 and §10 phase 1.
//
//  Each tab owns exactly ONE `NavigationView`, declared here.
//
//  It used to be the other way round: every tab view wrapped its own
//  content in a `NavigationView`. Two consequences followed:
//
//  * A `NavigationLink` pushed into a tab's own `NavigationView` had
//    nowhere to go — the Library tab could not open a word.
//  * Nesting a `NavigationView` inside a pushed view nests two
//    navigation stacks, which shrinks the content into a card with a
//    shadow and leaves it short of the full screen.
//
//  Declaring the stack once, at the tab root, fixes both: a pushed
//  view now shares the tab's stack and fills the screen.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationView {
                HomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationView {
                LibraryView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Library", systemImage: "books.vertical.fill") }

            NavigationView {
                StudyView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }

            NavigationView {
                QuizView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Quiz", systemImage: "questionmark.circle") }

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
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
