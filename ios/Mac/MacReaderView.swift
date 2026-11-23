import SprigCore
import SwiftUI

/// The right column: one story, with its actions in the window toolbar. The caller sets `.id(itemID)`,
/// so each story gets fresh state and its own scroll position.
struct MacReaderView: View {
    let itemID: String

    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reader.fontStep") private var fontStep = 0
    @State private var item: Item?
    @State private var progress = 0.0
    /// What the store holds, so a change made elsewhere (Mark as Unread) isn't undone by closing.
    @State private var storedProgress = 0.0
    @State private var startProgress = 0.0
    @State private var editingTopics = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            if let item {
                content(item)
                progressBar
            }
        }
        .toolbar { if let item { toolbarItems(item) } }
        .sheet(isPresented: $editingTopics) {
            if let item { TopicsSheet(item: item) }
        }
        .task { await observe() }
        .onDisappear(perform: leave)
        .onChange(of: scenePhase) { if scenePhase != .active { saveProgress() } }
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        if item.status == .ready, !item.contentHtml.isEmpty {
            MacArticleWebView(
                item: item,
                fontSize: ArticlePage.fontSizes[min(max(fontStep, 0), ArticlePage.fontSizes.count - 1)],
                initialProgress: startProgress,
                onProgress: { progress = $0 }
            )
        } else {
            LinkOnlyView(item: item, onRetry: { retry(item) })
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Theme.accent)
                .frame(width: proxy.size.width * progress, height: 2)
                .animation(.linear(duration: 0.2), value: progress)
        }
        .frame(height: 2)
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ item: Item) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if item.kind != .tweet {
                Button("Smaller Text", systemImage: "textformat.size.smaller") { fontStep = max(fontStep - 1, 0) }
                    .disabled(fontStep <= 0)
                Button("Bigger Text", systemImage: "textformat.size.larger") {
                    fontStep = min(fontStep + 1, ArticlePage.fontSizes.count - 1)
                }
                .disabled(fontStep >= ArticlePage.fontSizes.count - 1)
            }
            Button(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.fill" : "star") {
                engine.update(item, PatchChanges(favorite: !item.favorite))
            }
            if item.location != .archive {
                Button("Archive", systemImage: "archivebox") { engine.archive(item) }
            }
            Button(item.kind == .tweet ? "Open in X" : "Open Original", systemImage: "safari", action: openOriginal)
            Menu {
                Button("Mark as Unread", systemImage: "circlebadge") { engine.update(item, PatchChanges(progress: 0)) }
                if let url = URL(string: item.url) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Edit Topics", systemImage: "tag") { editingTopics = true }
                if item.status == .failed {
                    Button("Try Again", systemImage: "arrow.clockwise") { retry(item) }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func openOriginal() {
        if let item, let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
    }

    private func observe() async {
        guard let first = try? engine.store.item(id: itemID) else { return }
        item = first
        progress = first.progress
        storedProgress = first.progress
        startProgress = first.progress
        // Keep the screen current while the server finishes fetching or re-tags it, and the toolbar
        // in step with changes made from the list or the Story menu.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard let latest = try? engine.store.item(id: itemID) else { continue }
            if latest.progress != storedProgress {
                // Changed outside the reader (Mark as Unread): follow it rather than overwrite it.
                storedProgress = latest.progress
                progress = latest.progress
            }
            if latest != item { item = latest }
        }
    }

    /// Moving to another story after reading this one to the end archives it (Undo is offered).
    private func leave() {
        if let item, Item.readToEnd(from: startProgress, to: progress, in: item.location),
           (try? engine.store.item(id: item.id))?.location == item.location {
            storedProgress = progress
            engine.archive(item, progress: progress, automatically: true)
        } else {
            saveProgress()
        }
    }

    private func saveProgress() {
        guard let item, abs(progress - storedProgress) > 0.01 else { return }
        storedProgress = progress
        engine.update(item, PatchChanges(progress: progress))
    }

    private func retry(_ item: Item) {
        Task {
            if let refreshed = try? await engine.api.retry(id: item.id) {
                try? engine.store.upsert([refreshed])
                self.item = refreshed
            }
        }
    }
}

/// Pages Sprig couldn't read itself: paywalls, PDFs, failed fetches.
private struct LinkOnlyView: View {
    let item: Item
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.displaySite).font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
            Text(item.displayTitle)
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(message).font(.callout).foregroundStyle(Theme.dim)
            if item.status == .pending {
                ProgressView().controlSize(.small)
            } else {
                Button { if let url = URL(string: item.url) { NSWorkspace.shared.open(url) } } label: {
                    Label(item.kind == .tweet ? "Open in X" : "Read on the Web", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if item.status == .failed {
                    Button("Try Again", action: onRetry)
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        switch item.status {
        case .pending: "Fetching…"
        case .failed: "Sprig couldn't fetch this page."
        case .ready, .webOnly: "This one reads best on the web."
        }
    }
}
