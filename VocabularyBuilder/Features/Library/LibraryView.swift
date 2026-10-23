//
//  LibraryView.swift
//  vocabulary_builder
//
//  Browse, search, filter, multi-select, swipe-delete, and create words.
//  Mirrors `LibraryPage` in the web app. See IOS_PORTING_GUIDE.md §7.4.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @State private var search: String = ""
    @State private var categoryFilter: String? = nil
    @State private var selection: Set<UUID> = []
    @State private var isEditing: Bool = false
    @State private var showCreate: Bool = false

    private var categories: [String] { library.categories }

    private var filtered: [Vocabulary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.sortedWords.filter { word in
            (categoryFilter == nil || word.category == categoryFilter) &&
            (q.isEmpty
             || word.word.localizedCaseInsensitiveContains(q)
             || word.definition.localizedCaseInsensitiveContains(q)
             || word.category.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = library.lastError {
                ErrorBanner(message: err.errorDescription ?? "Error") {
                    Task { await library.reload(api: api) }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            categoryStrip
            wordList
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle(isEditing ? "\(selection.count) selected" : "Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search word, definition, category")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCreate) {
            NavigationView {
                WordEditorView(mode: .create)
            }
            .navigationViewStyle(.stack)
        }
        .refreshable {
            await library.reload(api: api)
        }
        .task {
            // The list is a snapshot unless it is refreshed when the tab
            // is opened. Skip the fetch when the store was updated
            // moments ago — `GET /api/words` is ~427 KB.
            guard !library.wordsAreFresh else { return }
            await library.reloadWords(api: api)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(isEditing ? "Done" : "Select") {
                if isEditing { selection.removeAll() }
                isEditing.toggle()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        if selection.count == filtered.count {
                            selection.removeAll()
                        } else {
                            selection = Set(filtered.map(\.id))
                        }
                    } label: {
                        Text(selection.count == filtered.count ? "Deselect all" : "Select all")
                            .font(.subheadline)
                    }
                    Button(role: .destructive) {
                        let ids = selection
                        Task {
                            for id in ids { await library.deleteWord(api: api, id: id) }
                            selection.removeAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selection.isEmpty)
                } else {
                    Menu {
                        NavigationLink("Collections") { CollectionsView() }
                        NavigationLink("Generate with AI") { GenerateView() }
                        Button {
                            showCreate = true
                        } label: {
                            Label("New word", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    label: "All",
                    selected: categoryFilter == nil
                ) { categoryFilter = nil }
                ForEach(categories, id: \.self) { cat in
                    CategoryChip(
                        label: cat,
                        selected: categoryFilter == cat
                    ) { categoryFilter = (categoryFilter == cat) ? nil : cat }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var wordList: some View {
        if filtered.isEmpty {
            EmptyState(
                icon: "tray",
                title: library.words.isEmpty ? "No words yet" : "No matches",
                message: library.words.isEmpty
                    ? "Tap the + menu to add a word or generate with AI."
                    : "Try a different search or category filter."
            )
        } else {
            List {
                ForEach(filtered) { word in
                    row(for: word)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(for word: Vocabulary) -> some View {
        if isEditing {
            HStack {
                Image(systemName: selection.contains(word.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(word.id) ? Theme.primary : .secondary)
                    .font(.title3)
                rowContent(word)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selection.contains(word.id) { selection.remove(word.id) }
                else { selection.insert(word.id) }
            }
        } else {
            NavigationLink {
                WordDetailView(wordId: word.id)
            } label: {
                rowContent(word)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await library.deleteWord(api: api, id: word.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func rowContent(_ word: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.word).font(.headline)
                if let ipa = word.ipa, !ipa.isEmpty {
                    Text(ipa).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Text(word.definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if !word.category.isEmpty {
                    Chip(label: word.category, outlined: true)
                }
                if let pos = word.partOfSpeech.nonEmpty {
                    Chip(label: pos, tint: Theme.info, outlined: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.primary : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
