//
//  OcrFlowView.swift
//  vocabulary_builder
//
//  Five-step wizard that takes a photo of a page, asks the API to OCR
//  it, lets the user pick which words to import, optionally enriches
//  them with AI, and saves the chosen ones to the library. Mirrors the
//  state machine in OcrPage.tsx. See API.md §13 and IOS_PORTING_GUIDE.md
//  §7.3.
//

import SwiftUI

enum OcrStep: Int {
    case upload
    case extracting
    case pick
    case edit
    case done
}

struct OcrFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: APIClient
    let onSaved: () -> Void

    @State private var step: OcrStep = .upload
    @State private var sourceImage: UIImage?
    @State private var imageData: Data?
    @State private var extraction: OcrExtraction?
    @State private var selected: Set<Int> = []
    @State private var targetLevel: String = "B1"
    @State private var isWorking: Bool = false
    @State private var error: String?
    @State private var savedCount: Int = 0
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var editingIndex: Int? = nil
    @State private var editedItem: OcrVocabularyItem? = nil
    @State private var enrichedFields: [String: EnrichedWord] = [:]
    @State private var isEnriching: Bool = false
    @State private var startedAt: Date = Date()

    var body: some View {
        NavigationView {
            VStack {
                if let err = error {
                    ErrorBanner(message: err) { error = nil }
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                switch step {
                case .upload:      uploadStep
                case .extracting:  extractingStep
                case .pick:        pickStep
                case .edit:        editStep
                case .done:        doneStep
                }
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Add from photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                applyImage(image)
            }
        }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(sourceType: .photoLibrary) { image in
                applyImage(image)
            }
        }
    }

    // MARK: - Steps

    private var uploadStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primary)
            Text("Take a photo of a vocabulary list").font(.title3.bold())
            Text("We will read the words, then ask you to pick which ones to import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Picker("Target level", selection: $targetLevel) {
                ForEach(["A1", "A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0).tag($0) }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Button {
                    showLibrary = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.primary.opacity(0.15))
                        .foregroundStyle(Theme.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private var extractingStep: some View {
        VStack(spacing: 16) {
            Spacer()
            if let image = sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ProgressView()
            Text("Reading the page…")
                .font(.headline)
            if let extraction {
                Text("OCR \(extraction.ocrDurationMs)ms · LLM \(extraction.llmDurationMs)ms")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var pickStep: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Extracted \(extraction?.vocabulary.count ?? 0) word\(extraction?.vocabulary.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button {
                    if let extraction, selected.count == extraction.vocabulary.count {
                        selected.removeAll()
                    } else if let extraction {
                        selected = Set(extraction.vocabulary.indices.map { $0 })
                    }
                } label: {
                    Text(selected.count == extraction?.vocabulary.count ? "Deselect all" : "Select all")
                        .font(.subheadline)
                }
            }
            .padding()

            if let extraction, !extraction.vocabulary.isEmpty {
                List {
                    ForEach(Array(extraction.vocabulary.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .top) {
                            Image(systemName: selected.contains(idx) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(idx) ? Theme.primary : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.wordOrPhrase).font(.headline)
                                if !item.meaningEn.isEmpty {
                                    Text(item.meaningEn).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if !item.meaningVi.isEmpty {
                                    Text(item.meaningVi).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(idx) { selected.remove(idx) }
                            else { selected.insert(idx) }
                        }
                    }
                }
                .listStyle(.plain)
            } else if let extraction, extraction.vocabulary.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "No vocabulary found",
                    message: "The OCR could not find vocabulary on this page. Try a clearer photo."
                )
            }

            HStack(spacing: 12) {
                Button {
                    step = .upload
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await saveSelected() }
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else {
                        Text("Import \(selected.count)")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || isWorking)
            }
            .padding()
        }
    }

    private var editStep: some View {
        // Simple per-item editor. iOS-only nicety: pick an entry to enrich
        // with AI before saving.
        VStack {
            if let idx = editingIndex, let item = editedItem {
                Form {
                    Section("Word") {
                        TextField("Headword", text: Binding(
                            get: { item.wordOrPhrase },
                            set: { editedItem?.wordOrPhrase = $0 }
                        ))
                    }
                    Section("Meaning") {
                        MultiLineTextField(text: Binding(
                            get: { item.meaningEn },
                            set: { editedItem?.meaningEn = $0 }
                        ), placeholder: "Definition (English)")
                        TextField("Translation (Vietnamese)", text: Binding(
                            get: { item.meaningVi },
                            set: { editedItem?.meaningVi = $0 }
                        ))
                        Picker("Part of speech", selection: Binding(
                            get: { item.type },
                            set: { editedItem?.type = $0 }
                        )) {
                            ForEach(["noun", "verb", "adjective", "adverb", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    }
                    Section("Example") {
                        MultiLineTextField(text: Binding(
                            get: { item.exampleSentence },
                            set: { editedItem?.exampleSentence = $0 }
                        ), placeholder: "Example sentence")
                    }
                    Section {
                        Button {
                            Task { await enrich(idx: idx) }
                        } label: {
                            if isEnriching {
                                HStack { ProgressView(); Text("Enriching…") }
                            } else {
                                Label("Enrich with AI", systemImage: "sparkles")
                            }
                        }
                        .disabled(isEnriching)
                    }
                }
                .navigationTitle("Edit word")
            } else {
                EmptyState(icon: "pencil", title: "No item selected", message: "Pick a word from the list to edit.")
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.primary)
            Text("Saved \(savedCount) word\(savedCount == 1 ? "" : "s")")
                .font(.title2.bold())
            Text("They are now in your Library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onSaved()
                dismiss()
            } label: {
                Text("Back to Home").bold().frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Actions

    private func applyImage(_ image: UIImage) {
        sourceImage = image
        imageData = image.jpegData(compressionQuality: 0.9)
        Task { await extract() }
    }

    private func extract() async {
        guard let data = imageData else { return }
        step = .extracting
        startedAt = Date()
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let prepared = try ImageProcessor.prepare(data)
            let result = try await api.extractFromImage(
                base64: prepared.base64,
                targetLevel: targetLevel
            )
            extraction = result
            // Pre-select all vocabulary entries.
            selected = Set(result.vocabulary.indices.map { $0 })
            step = .pick
        } catch let api as APIError {
            error = api.errorDescription
            step = .upload
        } catch {
            self.error = error.localizedDescription
            step = .upload
        }
    }

    private func enrich(idx: Int) async {
        guard var current = extraction?.vocabulary[safe: idx] else { return }
        isEnriching = true
        defer { isEnriching = false }
        do {
            let context = current.meaningInContext.isEmpty ? current.meaningEn : current.meaningInContext
            let result = try await api.enrichWord(word: current.wordOrPhrase, context: context)
            current.wordOrPhrase = result.word.isEmpty ? current.wordOrPhrase : result.word
            current.ipa = result.ipa.isEmpty ? current.ipa : result.ipa
            current.type = result.partOfSpeech.isEmpty ? current.type : result.partOfSpeech
            current.meaningEn = result.definition.isEmpty ? current.meaningEn : result.definition
            current.meaningVi = result.translation.isEmpty ? current.meaningVi : result.translation
            current.difficultyLevel = result.difficulty.isEmpty ? current.difficultyLevel : result.difficulty
            current.exampleSentence = result.exampleSentence.isEmpty ? current.exampleSentence : result.exampleSentence
            current.synonyms = result.synonyms.isEmpty ? current.synonyms : result.synonyms
            current.collocations = result.collocations.isEmpty ? current.collocations : result.collocations
            editedItem = current
            if extraction != nil, extraction!.vocabulary.indices.contains(idx) {
                extraction!.vocabulary[idx] = current
            }
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveSelected() async {
        guard let extraction else { return }
        let toSave = extraction.vocabulary.enumerated()
            .filter { selected.contains($0.offset) }
            .map { $0.element.toVocabularyWrite() }
        guard !toSave.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            for write in toSave {
                _ = try await api.createWord(write)
            }
            savedCount = toSave.count
            step = .done
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
