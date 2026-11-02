import BouquetCore
import SwiftUI

/// Add, rename, reorder and delete topics. Saving re-tags what Claude tagged with a changed topic.
struct TopicsEditor: View {
    @EnvironmentObject private var engine: SyncEngine
    @State private var topics: [String] = []
    @State private var newTopic = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                ForEach(topics, id: \.self) { topic in
                    Button(topic) {
                        renaming = topic
                        renameText = topic
                    }
                    .foregroundStyle(Theme.text)
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onMove { topics.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { topics.remove(atOffsets: $0) }
            } footer: {
                Text("Tap to rename. Changing topics re-tags what Claude tagged with them.")
            }
            Section {
                HStack {
                    TextField("New topic", text: $newTopic).onSubmit(add)
                    Button("Add", action: add).disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Topics")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .bottomBar) { saveButton }
            #else
            ToolbarItem(placement: .confirmationAction) { saveButton }
            #endif
        }
        .alert("Rename topic", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let old = renaming, let index = topics.firstIndex(of: old) {
                    topics[index] = renameText.trimmingCharacters(in: .whitespaces)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onAppear { topics = (try? engine.store.topics()) ?? [] }
    }

    private var saveButton: some View {
        Button(isSaving ? "Saving…" : "Save changes", action: save)
            .disabled(isSaving || topics == ((try? engine.store.topics()) ?? []))
    }

    private func add() {
        let name = newTopic.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !topics.contains(name) else { return }
        topics.append(name)
        newTopic = ""
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = try await engine.api.putTopics(topics)
                try engine.store.setTopics(saved)
                topics = saved
                error = nil
                await engine.sync()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
