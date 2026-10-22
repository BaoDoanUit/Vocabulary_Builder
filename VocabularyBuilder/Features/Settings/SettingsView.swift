//
//  SettingsView.swift
//  vocabulary_builder
//
//  Per-user study settings, base URL, storage usage, and the destructive
//  reset. Mirrors `SettingsPage` in the web app. See API.md §14 and
//  IOS_PORTING_GUIDE.md §7.8.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var session: SessionStore

    @State private var settings: UserSettings?
    @State private var edited: UserSettings?
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var saveOK: Bool = false
    @State private var baseURLDraft: String = ""
    @State private var storage: StorageUsage?
    @State private var isComputingStorage: Bool = false
    @State private var showResetConfirm = false
    @State private var showSignOutConfirm = false
    @State private var resetError: String?
    @State private var showExport = false
    @State private var exportData: Data?

    var body: some View {
        NavigationView {
            Form {
                accountSection
                if settings != nil { studySection }
                apiSection
                storageSection
                dangerSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar(content: toolbarContent)
        }
        .navigationViewStyle(.stack)
        .task { await reload() }
        .confirmationDialog(
            "Erase all data on the server?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                Task { await resetAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every word, collection, progress record, and media file on the server. Your account survives, but everything you have stored is gone for good.")
        }
        .confirmationDialog(
            "Sign out?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                session.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data stays on the server. You can sign back in any time.")
        }
        .sheet(isPresented: $showExport) {
            if let data = exportData {
                ShareSheet(items: [data])
            }
        }
    }

    // MARK: - Sections

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if edited != nil, edited != settings {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let user = session.user {
                row("Signed in as", value: user.email)
                Button("Sign out", role: .destructive) {
                    showSignOutConfirm = true
                }
            } else {
                Text("Not signed in").foregroundStyle(.secondary)
            }
        }
    }

    /// iOS 15-compatible replacement for `LabeledContent`.
    @ViewBuilder
    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder
    private var studySection: some View {
        Section("Study") {
            if let s = edited ?? settings {
                Stepper("Weak threshold: \(s.weakThreshold)",
                        value: Binding(
                            get: { s.weakThreshold },
                            set: { newValue in
                                var copy = s
                                copy.weakThreshold = max(1, newValue)
                                edited = copy
                            }
                        ),
                        in: 1...20)
                Stepper("Strong threshold: \(s.strongThreshold)",
                        value: Binding(
                            get: { s.strongThreshold },
                            set: { newValue in
                                var copy = s
                                copy.strongThreshold = max(1, newValue)
                                edited = copy
                            }
                        ),
                        in: 1...20)
                Stepper("Quiz size: \(s.quizSize)",
                        value: Binding(
                            get: { s.quizSize },
                            set: { newValue in
                                var copy = s
                                copy.quizSize = min(30, max(1, newValue))
                                edited = copy
                            }
                        ),
                        in: 1...30)
                Picker("CEFR level", selection: Binding(
                    get: { s.vocabularyLevel },
                    set: { newValue in
                        var copy = s
                        copy.vocabularyLevel = newValue
                        edited = copy
                    }
                )) {
                    ForEach(["A1", "A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private var apiSection: some View {
        Section {
            TextField("Base URL", text: $baseURLDraft)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("Apply") {
                guard let url = URL(string: baseURLDraft), !baseURLDraft.isEmpty else { return }
                appSettings.baseURL = url
                api.baseURL = url
                Task { await library.reload(api: api) }
            }
            .disabled(URL(string: baseURLDraft) == nil)
            Text("Default: \(AppSettings.defaultBaseURL.absoluteString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } header: {
            Text("API")
        } footer: {
            Text("Use the Tailscale MagicDNS hostname from a real device. iOS ATS cannot grant an exception to a raw IP.")
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                Text("Images")
                Spacer()
                if let s = storage {
                    Text(formatBytes(s.imageBytes)).foregroundStyle(.secondary).monospacedDigit()
                } else if isComputingStorage {
                    ProgressView()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Audio")
                Spacer()
                if let s = storage {
                    Text(formatBytes(s.audioBytes)).foregroundStyle(.secondary).monospacedDigit()
                } else if isComputingStorage {
                    ProgressView()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Total")
                Spacer()
                if let s = storage {
                    Text(formatBytes(s.totalBytes)).bold().monospacedDigit()
                } else if isComputingStorage {
                    ProgressView()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await loadStorage() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                exportJson()
            } label: {
                Label("Export words as JSON", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Storage usage is global, not per user.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Erase all data on the server", systemImage: "trash.fill")
            }
            if let err = resetError {
                Text(err).font(.caption).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Danger zone")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            row("API", value: api.baseURL.absoluteString)
            row("Words", value: "\(library.words.count)")
            row("Collections", value: "\(library.collections.count)")
        }
    }

    // MARK: - Actions

    private func reload() async {
        await loadSettings()
        await loadStorage()
        baseURLDraft = appSettings.baseURL.absoluteString
    }

    private func loadSettings() async {
        guard settings == nil, let user = session.user else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getSettings(userId: user.id)
            edited = settings
        } catch {
            // Stay on defaults.
        }
    }

    private func save() async {
        guard let user = session.user, let edited else { return }
        isSaving = true
        saveError = nil
        saveOK = false
        defer { isSaving = false }
        let request = UpdateUserSettingsRequest(
            weakThreshold: edited.weakThreshold,
            strongThreshold: edited.strongThreshold,
            quizSize: edited.quizSize,
            vocabularyLevel: edited.vocabularyLevel,
            hasCompletedOnboarding: edited.hasCompletedOnboarding
        )
        do {
            let stored = try await api.updateSettings(userId: user.id, request)
            settings = stored
            self.edited = stored
            saveOK = true
        } catch let api as APIError {
            saveError = api.errorDescription
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func loadStorage() async {
        isComputingStorage = true
        defer { isComputingStorage = false }
        do { storage = try await api.storageUsage() } catch { /* ignore */ }
    }

    private func resetAccount() async {
        do {
            try await api.resetAccount()
            await library.reload(api: api)
        } catch let api as APIError {
            resetError = api.errorDescription
        } catch {
            resetError = error.localizedDescription
        }
    }

    private func exportJson() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        struct Export: Encodable {
            let words: [Vocabulary]
            let collections: [WordCollection]
            let progress: [WordProgress]
        }
        let payload = Export(
            words: library.words,
            collections: library.collections,
            progress: Array(library.progress.values)
        )
        if let data = try? encoder.encode(payload) {
            exportData = data
            showExport = true
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
