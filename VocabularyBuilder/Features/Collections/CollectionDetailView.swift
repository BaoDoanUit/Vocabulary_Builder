//
//  CollectionDetailView.swift
//  vocabulary_builder
//
//  Shows the words in a collection. Tapping a word goes to its detail
//  view. See IOS_PORTING_GUIDE.md §7.8.
//

import SwiftUI

struct CollectionDetailView: View {
    @EnvironmentObject var library: LibraryStore
    let collection: WordCollection

    private var words: [Vocabulary] {
        let byId = Dictionary(uniqueKeysWithValues: library.words.map { ($0.id, $0) })
        return collection.wordIds.compactMap { byId[$0] }
    }

    var body: some View {
        Group {
            if words.isEmpty {
                EmptyState(
                    icon: "tray",
                    title: "No words in this collection",
                    message: "Add words from the Library tab, then add them to this collection."
                )
            } else {
                List {
                    Section {
                        ForEach(words) { word in
                            NavigationLink {
                                // Page through the words in this collection.
                                WordDetailView(wordId: word.id, siblings: words)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(word.word).font(.headline)
                                    Text(word.definition)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } header: {
                        Text("\(collection.wordIds.count) word\(collection.wordIds.count == 1 ? "" : "s")")
                    }
                }
            }
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
