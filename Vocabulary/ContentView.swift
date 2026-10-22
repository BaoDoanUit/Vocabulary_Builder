//
//  ContentView.swift
//  Vocabulary
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WordListView()
                .tabItem { Label("Words", systemImage: "list.bullet") }
            FlashcardView()
                .tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }
            QuizView()
                .tabItem { Label("Quiz", systemImage: "questionmark.circle") }
        }
    }
}

#Preview {
    ContentView().environmentObject(WordStore())
}
