//
//  WordDetailView.swift
//  vocabulary_builder
//
//  Read-only view of one word + entry points to edit/delete. Mirrors
//  `WordDetailPage`. See IOS_PORTING_GUIDE.md §7.7.
//

import SwiftUI

struct WordDetailView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    let wordId: UUID

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var word: Vocabulary? {
        library.words.first(where: { $0.id == wordId })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let word {
                    header(word: word)
                    imageBlock(word: word)
                    body_(word: word)
                    progress(word: word)
                } else {
                    Card {
                        Text("This word no longer exists on the server.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle("Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if word != nil {
                        Menu {
                            Button {
                                showEdit = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let word {
                NavigationView {
                    WordEditorView(mode: .edit(word))
                }
                .navigationViewStyle(.stack)
            }
        }
        .confirmationDialog(
            "Delete this word?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await library.deleteWord(api: api, id: wordId) }
            }
        } message: {
            Text("This permanently removes the word and its progress from the server.")
        }
    }

    private func header(word: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.word)
                .font(.system(size: 36, weight: .bold))
            if let ipa = word.ipa, !ipa.isEmpty {
                Text(ipa).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if !word.category.isEmpty {
                    Chip(label: word.category, outlined: true)
                }
                if let pos = word.partOfSpeech.nonEmpty {
                    Chip(label: pos, tint: Theme.info, outlined: true)
                }
                if let level = word.difficultyLevel?.nonEmpty {
                    Chip(label: level, tint: Theme.warning, outlined: true)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func imageBlock(word: Vocabulary) -> some View {
        if word.hasImage {
            let url = api.mediaURL(.images, word.imageId!)
            CachedImage(url: url)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
        }
    }

    private func body_(word: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Definition").font(.caption).foregroundStyle(.secondary)
                    Text(word.definition)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Translation").font(.caption).foregroundStyle(.secondary)
                    Text(word.translation)
                }
            }
            if !word.exampleSentence.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Example").font(.caption).foregroundStyle(.secondary)
                        Text("\u{201C}\(word.exampleSentence)\u{201D}")
                            .italic()
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func progress(word: Vocabulary) -> some View {
        if let p = library.progress(for: word) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Progress").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        stat("Attempts", "\(p.attempts)")
                        stat("Correct", "\(p.correct)")
                        stat("Wrong", "\(p.incorrect)")
                        stat("Streak", "\(p.consecutiveCorrect)")
                    }
                    if p.isWeak {
                        Chip(label: "Weak", icon: "exclamationmark.circle", tint: Theme.danger)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
