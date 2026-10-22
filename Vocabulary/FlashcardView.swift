//
//  FlashcardView.swift
//  Vocabulary
//

import SwiftUI

struct FlashcardView: View {
    @EnvironmentObject var store: WordStore
    @State private var deck: [Word] = []
    @State private var index: Int = 0
    @State private var revealed: Bool = false

    var body: some View {
        NavigationView {
            VStack {
                if let word = current {
                    card(for: word)
                        .padding(.horizontal)
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            store.setStatus(.learning, for: word)
                            advance()
                        } label: {
                            Label("Learning", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button {
                            store.setStatus(.known, for: word)
                            advance()
                        } label: {
                            Label("Known", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.18))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Study")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shuffleDeck()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                }
            }
        }
        .onAppear { if deck.isEmpty { shuffleDeck() } }
    }

    private var current: Word? {
        guard index < deck.count else { return nil }
        return deck[index]
    }

    private func card(for word: Word) -> some View {
        VStack(spacing: 16) {
            Text(word.category)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(word.english)
                .font(.system(size: 44, weight: .bold))
                .multilineTextAlignment(.center)
            if let p = word.pronunciation {
                Text(p).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 8)
            if revealed {
                VStack(spacing: 8) {
                    Text(word.vietnamese)
                        .font(.title.weight(.semibold))
                    if let ex = word.example {
                        Text("\u{201C}\(ex)\u{201D}")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation { revealed = true }
                } label: {
                    Label("Tap to reveal", systemImage: "hand.tap")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                }
            }
            Spacer().frame(height: 4)
            ProgressView(value: Double(index + 1), total: Double(max(deck.count, 1)))
                .tint(.accentColor)
            Text("\(index + 1) / \(deck.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No words to study").font(.title3).bold()
            Text("Add more words or reset progress.").font(.subheadline).foregroundStyle(.secondary)
            Button("Shuffle deck") { shuffleDeck() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func advance() {
        revealed = false
        if index + 1 < deck.count {
            index += 1
        } else {
            // End of deck: reshuffle for a new round, prioritizing unknowns
            shuffleDeck()
        }
    }

    private func shuffleDeck() {
        deck = store.studyDeck()
        index = 0
        revealed = false
    }
}

#Preview {
    FlashcardView().environmentObject(WordStore())
}
