//
//  WordListView.swift
//  Vocabulary
//

import SwiftUI

struct WordListView: View {
    @EnvironmentObject var store: WordStore
    @State private var filter: WordStatus? = nil
    @State private var search = ""

    var filtered: [Word] {
        store.words.filter { word in
            (filter == nil || store.status(for: word) == filter)
            && (search.isEmpty
                || word.english.localizedCaseInsensitiveContains(search)
                || word.vietnamese.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ProgressHeader()
                FilterChips(filter: $filter)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                List(filtered) { word in
                    WordRow(word: word)
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: "Search words")
            }
            .navigationTitle("Vocabulary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reset progress", role: .destructive) {
                            store.resetProgress()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct ProgressHeader: View {
    @EnvironmentObject var store: WordStore
    var body: some View {
        let c = store.counts
        return HStack(spacing: 12) {
            stat(value: c.known,    label: "Known",    color: .green)
            stat(value: c.learning, label: "Learning", color: .orange)
            stat(value: c.new,      label: "New",      color: .gray)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
    @ViewBuilder
    private func stat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2).bold().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct FilterChips: View {
    @EnvironmentObject var store: WordStore
    @Binding var filter: WordStatus?
    var body: some View {
        HStack(spacing: 8) {
            Chip(label: "All", selected: filter == nil) { filter = nil }
            ForEach(WordStatus.allCases, id: \.self) { status in
                Chip(label: status.label,
                     selected: filter == status) { filter = status }
            }
        }
    }
}

private struct Chip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

private struct WordRow: View {
    @EnvironmentObject var store: WordStore
    let word: Word
    var status: WordStatus { store.status(for: word) }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.english).font(.headline)
                Text(word.vietnamese).font(.subheadline).foregroundStyle(.secondary)
                if let cat = word.category.isEmpty ? nil : word.category {
                    Text(cat).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            statusDot
        }
        .padding(.vertical, 4)
    }
    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
    private var color: Color {
        switch status {
        case .new:      return .gray
        case .learning: return .orange
        case .known:    return .green
        }
    }
}

#Preview {
    WordListView().environmentObject(WordStore())
}
