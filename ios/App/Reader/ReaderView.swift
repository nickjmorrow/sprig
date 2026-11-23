import SprigCore
import SwiftUI

struct ReaderView: View {
    let itemID: String

    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("reader.fontStep") private var fontStep = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var item: Item?
    @State private var progress = 0.0
    @State private var startProgress = 0.0
    @State private var editingTopics = false

    var body: some View {
        Group {
            if let item {
                content(item)
                    .overlay(alignment: .top) { progressBar }
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let item {
                ReaderBar(
                    item: item,
                    fontStep: $fontStep,
                    onFavorite: { engine.update(item, PatchChanges(favorite: !item.favorite)) },
                    onArchive: archive,
                    onEditTopics: { editingTopics = true },
                    onMarkUnread: markUnread,
                    onRetry: { retry(item) }
                )
            }
        }
        .sheet(isPresented: $editingTopics) {
            if let item { TopicsSheet(item: item) }
        }
        .task { await observe() }
        .onDisappear(perform: leave)
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        if item.status == .ready, !item.contentHtml.isEmpty {
            ArticleWebView(
                item: item,
                fontSize: articleFontSize,
                initialProgress: startProgress,
                onProgress: { progress = $0 }
            )
        } else {
            LinkOnlyView(item: item, onRetry: { retry(item) })
        }
    }

    /// The chosen step scaled by the system text size, so Larger Text reaches the article too.
    private var articleFontSize: Int {
        _ = dynamicTypeSize
        let step = ArticlePage.fontSizes[min(max(fontStep, 0), ArticlePage.fontSizes.count - 1)]
        return Int(UIFontMetrics(forTextStyle: .body).scaledValue(for: CGFloat(step)).rounded())
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Theme.accent)
                .frame(width: proxy.size.width * progress, height: 2)
                .animation(.linear(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private func observe() async {
        guard let first = try? engine.store.item(id: itemID) else { return }
        item = first
        progress = first.progress
        startProgress = first.progress
        // Keep the screen current while the server finishes fetching or re-tags it.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if let latest = try? engine.store.item(id: itemID), latest != item {
                item = latest
            }
        }
    }

    /// Going back after reading to the end archives the story; the list offers Undo.
    private func leave() {
        if let item, Item.readToEnd(from: startProgress, to: progress, in: item.location),
           (try? engine.store.item(id: item.id))?.location == item.location {
            self.item?.progress = progress
            engine.archive(item, progress: progress, automatically: true)
        } else {
            saveProgress()
        }
    }

    private func saveProgress() {
        guard let item, abs(progress - item.progress) > 0.01 else { return }
        engine.update(item, PatchChanges(progress: progress))
    }

    private func archive() {
        guard let item else { return }
        engine.archive(item, progress: abs(progress - item.progress) > 0.01 ? progress : nil)
        // Leaving is now just leaving: the story is already archived.
        self.item?.location = .archive
        self.item?.progress = progress
        dismiss()
    }

    private func markUnread() {
        guard let item else { return }
        engine.update(item, PatchChanges(progress: 0))
        // Matching both copies leaves saveProgress nothing to send when the reader closes.
        progress = 0
        self.item?.progress = 0
        dismiss()
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.displaySite).font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
            Text(item.displayTitle)
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(message).font(.callout).foregroundStyle(Theme.dim)
            if item.status == .pending {
                ProgressView()
            } else {
                Button { if let url = URL(string: item.url) { openURL(url) } } label: {
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
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch item.status {
        case .pending: "Fetching…"
        case .failed: "Sprig couldn't fetch this page."
        case .ready, .webOnly: "This one reads best on the web."
        }
    }
}
