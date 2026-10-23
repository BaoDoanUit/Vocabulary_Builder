//
//  GenerateView.swift
//  vocabulary_builder
//
//  Asks the AI to generate a word list on a subject, then lets the user
//  pick which to import. Mirrors `GeneratePage` in the web app. See
//  API.md §13 and IOS_PORTING_GUIDE.md §7.8.
//

import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @State private var subject: String = ""
    @State private var count: Int = 10
    @State private var generated: [GeneratedWord] = []
    @State private var selected: Set<Int> = []
    @State private var isWorking: Bool = false
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var savedCount: Int = 0
    @State private var model: String = ""

    var body: some View {
        Form {
            if let err = error {
                Section {
                    Text(err).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            Section("Prompt") {
                TextField("Subject, e.g. \"Environmental vocabulary\"", text: $subject)
                    .textInputAutocapitalization(.words)
                Stepper("Words: \(count)", value: $count, in: 1...30)
                Button {
                    Task { await generate() }
                } label: {
                    if isWorking {
                        HStack { ProgressView(); Text("Generating…") }
                    } else {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
                .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            if !generated.isEmpty {
                Section {
                    ForEach(Array(generated.enumerated()), id: \.offset) { idx, word in
                        HStack(alignment: .top) {
                            Image(systemName: selected.contains(idx) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(idx) ? Theme.primary : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(word.word).font(.headline)
                                if !word.definition.isEmpty {
                                    Text(word.definition).font(.subheadline).foregroundStyle(.secondary)
                                }
                                HStack {
                                    if !word.category.isEmpty {
                                        Chip(label: word.category, outlined: true)
                                    }
                                    if !word.difficulty.isEmpty {
                                        Chip(label: word.difficulty, tint: Theme.warning, outlined: true)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(idx) { selected.remove(idx) }
                            else { selected.insert(idx) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Generated words")
                        Spacer()
                        Button {
                            if selected.count == generated.count { selected.removeAll() }
                            else { selected = Set(generated.indices.map { $0 }) }
                        } label: {
                            Text(selected.count == generated.count ? "Deselect all" : "Select all")
                                .font(.caption)
                        }
                    }
                } footer: {
                    if !model.isEmpty {
                        Text("Model: \(model)")
                    }
                }
                Section {
                    Button {
                        Task { await saveSelected() }
                    } label: {
                        if isSaving {
                            HStack { ProgressView(); Text("Saving…") }
                        } else {
                            Text("Import \(selected.count) word\(selected.count == 1 ? "" : "s")").bold()
                        }
                    }
                    .disabled(selected.isEmpty || isSaving)
                }
            }
            if savedCount > 0 {
                Section {
                    Label("Saved \(savedCount) words", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .navigationTitle("Generate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generate() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let result = try await api.generateCollection(subject: subject, count: count)
            self.generated = result
            self.selected = Set(result.indices.map { $0 })
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveSelected() async {
        let toSave = generated.enumerated()
            .filter { selected.contains($0.offset) }
            .map { $0.element }
        guard !toSave.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        var imported = 0
        var failures = 0
        var lastFailure: String?
        for word in toSave {
            let write = VocabularyWrite(
                word: word.word,
                definition: word.definition,
                translation: word.translation,
                partOfSpeech: word.partOfSpeech,
                exampleSentence: word.exampleSentence,
                category: word.category,
                source: "ai",
                imageId: nil,
                audioId: nil,
                difficultyLevel: word.difficulty.isEmpty ? nil : word.difficulty,
                ipa: word.ipa.isEmpty ? nil : word.ipa,
                aiFieldsJson: nil
            )
            do {
                _ = try await library.createWord(api: api, write)
                imported += 1
            } catch let apiError as APIError {
                // Most often a duplicate. Keep going, but report it.
                failures += 1
                lastFailure = apiError.errorDescription
            } catch {
                failures += 1
                lastFailure = error.localizedDescription
            }
        }
        savedCount = imported
        if failures > 0 {
            error = "\(failures) of \(toSave.count) word\(toSave.count == 1 ? "" : "s") could not be saved."
                + (lastFailure.map { " \($0)" } ?? "")
        }
    }
}
