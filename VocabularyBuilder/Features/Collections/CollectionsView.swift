//
//  CollectionsView.swift
//  vocabulary_builder
//
//  List of collections. Reached from the Library tab. See
//  IOS_PORTING_GUIDE.md §7.8.
//

import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @State private var showCreate = false
    @State private var newName: String = ""
    @State private var newDescription: String = ""
    @State private var isWorking: Bool = false
    @State private var error: String?

    var body: some View {
        Group {
            if library.collections.isEmpty {
                EmptyState(
                    icon: "folder",
                    title: "No collections",
                    message: "Group words into a study set — e.g. \"Exam 2026\" or \"Travel\".",
                    action: ("Create", { showCreate = true })
                )
            } else {
                List {
                    ForEach(library.collections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection)
                        } label: {
                            row(collection)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New collection", isPresented: $showCreate) {
            TextField("Name", text: $newName)
            TextField("Description (optional)", text: $newDescription)
            Button("Cancel", role: .cancel) {
                newName = ""
                newDescription = ""
            }
            Button("Create") {
                Task { await create() }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        } message: {
            if let error {
                Text(error)
            }
        }
        .refreshable {
            await library.reload(api: api)
        }
    }

    private func row(_ collection: WordCollection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.name).font(.headline)
            if !collection.description.isEmpty {
                Text(collection.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(collection.wordIds.count) word\(collection.wordIds.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { library.collections[$0] }
        Task {
            for c in toDelete {
                do { try await library.deleteCollection(api: api, id: c.id) }
                catch { self.error = (error as? APIError)?.errorDescription }
            }
        }
    }

    private func create() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let write = CollectionWrite(
                name: newName,
                description: newDescription,
                wordIds: [],
                source: "manual"
            )
            _ = try await library.createCollection(api: api, write)
            newName = ""
            newDescription = ""
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
