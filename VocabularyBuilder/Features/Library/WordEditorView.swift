//
//  WordEditorView.swift
//  vocabulary_builder
//
//  Create + edit words. Mirrors `WordEditorPage`. See IOS_PORTING_GUIDE.md
//  §7.7. POST /api/words generates a new server-side id, so we always
//  adopt the id from the response. See API.md §17.4.
//

import SwiftUI

enum WordEditorMode {
    case create
    case edit(Vocabulary)
}

struct WordEditorView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @Environment(\.dismiss) private var dismiss

    let mode: WordEditorMode

    @State private var word: String = ""
    @State private var definition: String = ""
    @State private var translation: String = ""
    @State private var partOfSpeech: String = "noun"
    @State private var exampleSentence: String = ""
    @State private var category: String = ""
    @State private var ipa: String = ""
    @State private var difficultyLevel: String = ""
    @State private var imageData: Data?
    @State private var imageMime: String = "image/jpeg"
    @State private var showPhotoPicker: Bool = false
    @State private var isWorking: Bool = false
    @State private var error: String?
    @State private var enrichWord: String = ""
    @State private var enrichContext: String = ""
    @State private var isEnriching: Bool = false
    @State private var enrichError: String?

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existing: Vocabulary? {
        if case .edit(let v) = mode { return v }
        return nil
    }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespaces).isEmpty &&
        !definition.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isWorking
    }

    var body: some View {
        Form {
            Section("Word") {
                TextField("Headword (English)", text: $word)
                    .textInputAutocapitalization(.never)
                TextField("IPA, e.g. /rɪˈzɪliənt/", text: $ipa)
                    .textInputAutocapitalization(.never)
            }
            Section("Meaning") {
                MultiLineTextField(text: $definition, placeholder: "Definition (English)")
                TextField("Translation (Vietnamese)", text: $translation)
                Picker("Part of speech", selection: $partOfSpeech) {
                    ForEach(["noun", "verb", "adjective", "adverb", "other"], id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
            }
            Section("Example") {
                MultiLineTextField(text: $exampleSentence, placeholder: "Example sentence")
            }
            Section("Classification") {
                TextField("Category, e.g. Personality", text: $category)
                Picker("CEFR level", selection: $difficultyLevel) {
                    Text("None").tag("")
                    ForEach(["A1", "A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Image") {
                if let imageData, let img = UIImage(data: imageData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label(imageData == nil ? "Add image" : "Replace image", systemImage: "photo")
                }
                if imageData != nil {
                    Button(role: .destructive) {
                        imageData = nil
                    } label: {
                        Label("Remove image", systemImage: "trash")
                    }
                }
            }
            if !isEdit {
                Section("Enrich with AI") {
                    TextField("Word (defaults to headword)", text: $enrichWord)
                    MultiLineTextField(text: $enrichContext, placeholder: "Context, e.g. \"A river bank.\"")
                    Button {
                        Task { await runEnrich() }
                    } label: {
                        if isEnriching {
                            HStack { ProgressView(); Text("Enriching…") }
                        } else {
                            Label("Enrich", systemImage: "sparkles")
                        }
                    }
                    .disabled(isEnriching)
                    if let enrichError {
                        Text(enrichError).font(.caption).foregroundStyle(Theme.danger)
                    }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
        }
        .fullBleedForm()
        .navigationTitle(isEdit ? "Edit word" : "New word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Save").bold()
                    }
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: prefill)
        .fullScreenCover(isPresented: $showPhotoPicker) {
            ImagePicker(sourceType: .photoLibrary) { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    imageData = data
                    imageMime = "image/jpeg"
                }
            }
            .ignoresSafeArea()
        }
    }

    private func prefill() {
        guard let v = existing else { return }
        word = v.word
        definition = v.definition
        translation = v.translation
        partOfSpeech = v.partOfSpeech.isEmpty ? "noun" : v.partOfSpeech
        exampleSentence = v.exampleSentence
        category = v.category
        ipa = v.ipa ?? ""
        difficultyLevel = v.difficultyLevel ?? ""
    }

    private func runEnrich() async {
        let target = enrichWord.trimmingCharacters(in: .whitespaces).isEmpty
            ? word.trimmingCharacters(in: .whitespaces)
            : enrichWord.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            enrichError = "Enter a word to enrich."
            return
        }
        isEnriching = true
        enrichError = nil
        defer { isEnriching = false }
        do {
            let enriched = try await api.enrichWord(
                word: target,
                context: enrichContext.isEmpty ? target : enrichContext
            )
            if word.isEmpty { word = enriched.word }
            if let ip = enriched.ipa.nonEmpty, ipa.isEmpty { ipa = ip }
            if definition.isEmpty { definition = enriched.definition }
            if translation.isEmpty { translation = enriched.translation }
            if partOfSpeech.isEmpty || partOfSpeech == "noun" {
                if let pos = enriched.partOfSpeech.nonEmpty { partOfSpeech = pos }
            }
            if exampleSentence.isEmpty { exampleSentence = enriched.exampleSentence }
            if category.isEmpty { category = enriched.category }
            if difficultyLevel.isEmpty { difficultyLevel = enriched.difficulty }
        } catch let api as APIError {
            enrichError = api.errorDescription
        } catch {
            enrichError = error.localizedDescription
        }
    }

    private func save() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            var imageId: String? = existing?.imageId
            if let data = imageData {
                let prepared = try ImageProcessor.prepare(data)
                let mediaId = UUID().uuidString.lowercased()
                let response = try await api.uploadImage(
                    id: mediaId,
                    data: prepared.data,
                    mimeType: imageMime
                )
                imageId = response.id
            }
            let write = VocabularyWrite(
                word: word.trimmingCharacters(in: .whitespaces),
                definition: definition,
                translation: translation,
                partOfSpeech: partOfSpeech,
                exampleSentence: exampleSentence,
                category: category,
                source: existing?.source ?? "manual",
                imageId: imageId,
                audioId: existing?.audioId,
                difficultyLevel: difficultyLevel.isEmpty ? nil : difficultyLevel,
                ipa: ipa.isEmpty ? nil : ipa,
                aiFieldsJson: existing?.aiFieldsJson
            )
            switch mode {
            case .create:
                _ = try await library.createWord(api: api, write)
            case .edit(let original):
                _ = try await library.updateWord(api: api, id: original.id, with: write)
            }
            dismiss()
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
