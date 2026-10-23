//
//  HomeView.swift
//  vocabulary_builder
//
//  First tab. Mirrors `HomePage` from the web app:
//  1. Greeting + subtitle
//  2. Circular stat tiles (WORDS / DUE / WEAK)
//  3. "Upload photo" pill button → OcrFlowView as full-screen cover
//  4. Recent words with a "See all" link → LibraryView
//

import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var settings: UserSettings?
    @Published var isLoadingSettings: Bool = false

    let api: APIClient
    let session: SessionStore

    init(api: APIClient, session: SessionStore) {
        self.api = api
        self.session = session
    }

    func loadSettings() async {
        guard let user = session.user, settings == nil else { return }
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        do {
            settings = try await api.getSettings(userId: user.id)
        } catch {
            // Surface as banner; the screen still renders with defaults.
        }
    }

    var strongThreshold: Int { settings?.strongThreshold ?? 3 }
}

struct HomeView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @StateObject private var vm: HomeViewModel
    @State private var showOcr = false

    init() {
        // Placeholder; the real deps come from the environment and are
        // rebound in .task before any async work.
        _vm = StateObject(wrappedValue: HomeViewModel(
            api: APIClient(baseURL: AppSettings.defaultBaseURL),
            session: SessionStore()
        ))
    }

    init(api: APIClient, session: SessionStore) {
        _vm = StateObject(wrappedValue: HomeViewModel(api: api, session: session))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let err = library.lastError {
                        ErrorBanner(message: err.errorDescription ?? "Error") {
                            Task { await library.reload(api: api) }
                        }
                        .padding(.horizontal)
                    }
                    greeting
                    stats
                    uploadButton
                    recent
                }
                .padding(.vertical, 16)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.reload(api: api) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload")
                }
            }
            .task {
                await vm.loadSettings()
                // Refresh on appear, but skip the ~427 KB fetch when the
                // store was updated moments ago.
                if library.words.isEmpty || !library.wordsAreFresh {
                    await library.reloadWords(api: api)
                }
            }
            .refreshable {
                await library.reload(api: api)
                await vm.loadSettings()
            }
            .fullScreenCover(isPresented: $showOcr) {
                OcrFlowView {
                    // The OCR flow already refreshed the store, so the
                    // list is current. Only refetch if the refresh was
                    // skipped (e.g. the flow was dismissed without
                    // importing anything).
                    Task {
                        if !library.wordsAreFresh {
                            await library.reloadWords(api: api)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Subviews

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText).font(.subheadline).foregroundStyle(.secondary)
            if let user = session.user {
                Text(user.email)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
            }
            Text("Today is \(Date().formatted(date: .complete, time: .omitted)).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }

    private var stats: some View {
        let s = library.stats(strongThreshold: vm.strongThreshold)
        return HStack(spacing: 12) {
            StatCircle(value: library.wordCount, label: "WORDS", color: Theme.primary)
            StatCircle(value: library.weakCount, label: "WEAK", color: Theme.warning)
            StatCircle(value: s.known, label: "KNOWN", color: Theme.info)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private var uploadButton: some View {
        Button {
            showOcr = true
        } label: {
            HStack {
                Image(systemName: "camera.viewfinder")
                Text("Upload photo to extract vocabulary").bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primary)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(.horizontal)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent words").font(.headline)
                Spacer()
                NavigationLink("See all") { LibraryView() }
                    .font(.subheadline)
            }
            .padding(.horizontal)

            if library.sortedWords.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No words yet").font(.headline)
                        Text("Add words in the Library tab, or use Upload photo to extract them from a page.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            } else {
                let recent = Array(library.sortedWords.prefix(5))
                VStack(spacing: 8) {
                    ForEach(recent) { word in
                        NavigationLink {
                            WordDetailView(wordId: word.id)
                        } label: {
                            RecentWordRow(word: word, store: library)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct RecentWordRow: View {
    let word: Vocabulary
    let store: LibraryStore

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word).font(.headline)
                    Text(word.definition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if !word.category.isEmpty {
                            Chip(label: word.category, outlined: true)
                        }
                        if let pos = word.partOfSpeech.nonEmptyOptional {
                            Chip(label: pos, tint: Theme.info, outlined: true)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension String {
    var nonEmptyOptional: String? { isEmpty ? nil : self }
}
