import BouquetCore
import SwiftUI

struct ReaderView: View {
    let itemID: String

    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("reader.fontStep") private var fontStep = 0
    @State private var item: Item?
    @State private var progress = 0.0
    @State private var startProgress = 0.0
    @State private var editingTopics = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            if let item {
                content(item)
                progressBar
                VStack {
                    Spacer()
                    ReaderBar(
                        item: item,
                        onFontSize: { fontStep = (fontStep + 1) % ArticleWebView.fontSizes.count },
                        onFavorite: { engine.update(item, PatchChanges(favorite: !item.favorite)) },
                        onArchive: archive,
                        onEditTopics: { editingTopics = true },
                        onRetry: { retry(item) }
                    )
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $editingTopics) {
            if let item { TopicsSheet(item: item) }
        }
        .task { await observe() }
        .onDisappear(perform: saveProgress)
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        if item.status == .ready, !item.contentHtml.isEmpty {
            ArticleWebView(
                item: item,
                fontSize: ArticleWebView.fontSizes[fontStep % ArticleWebView.fontSizes.count],
                initialProgress: startProgress,
                onProgress: { progress = $0 }
            )
            .ignoresSafeArea(edges: .bottom)
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

    private func saveProgress() {
        guard let item, abs(progress - item.progress) > 0.01 else { return }
        engine.update(item, PatchChanges(progress: progress))
    }

    private func archive() {
        guard let item else { return }
        saveProgress()
        engine.update(item, PatchChanges(location: .archive))
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

/// Pages Bouquet couldn't read itself: paywalls, PDFs, failed fetches.
private struct LinkOnlyView: View {
    let item: Item
    let onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.displaySite).font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
            Text(item.displayTitle)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(Theme.text)
            Text(message).font(.callout).foregroundStyle(Theme.dim)
            if item.status == .pending {
                ProgressView().tint(Theme.dim)
            } else {
                Button { if let url = URL(string: item.url) { openURL(url) } } label: {
                    Label(item.kind == .tweet ? "Open in X" : "Read on the web", systemImage: "safari")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.accent))
                }
                if item.status == .failed {
                    Button("Try again", action: onRetry).foregroundStyle(Theme.accent)
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
        case .failed: "Bouquet couldn't fetch this page."
        case .ready, .webOnly: "This one reads best on the web."
        }
    }
}
