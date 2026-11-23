import SprigCore
import SwiftUI

/// The reader's bottom toolbar.
struct ReaderBar: ToolbarContent {
    let item: Item
    @Binding var fontStep: Int
    let onFavorite: () -> Void
    let onArchive: () -> Void
    let onEditTopics: () -> Void
    let onMarkUnread: () -> Void
    let onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if item.kind == .tweet {
                button("Open in X", systemImage: "arrow.up.right.square") { openOriginal() }
            } else {
                Menu {
                    ControlGroup {
                        Button("Smaller Text", systemImage: "textformat.size.smaller") { fontStep = max(fontStep - 1, 0) }
                            .disabled(fontStep <= 0)
                        Button("Larger Text", systemImage: "textformat.size.larger") {
                            fontStep = min(fontStep + 1, ArticlePage.fontSizes.count - 1)
                        }
                        .disabled(fontStep >= ArticlePage.fontSizes.count - 1)
                    }
                } label: {
                    Label("Text Size", systemImage: "textformat.size")
                }
            }
            Spacer()
            button(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.fill" : "star", action: onFavorite)
                .tint(item.favorite ? Theme.star : nil)
                .sensoryFeedback(.impact(weight: .light), trigger: item.favorite)
            Spacer()
            if item.location != .archive {
                button("Archive", systemImage: "archivebox", action: onArchive)
                Spacer()
            }
            Menu {
                Button("Mark as Unread", systemImage: "circlebadge", action: onMarkUnread)
                Button("Open Original", systemImage: "safari") { openOriginal() }
                if let url = URL(string: item.url) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Edit Topics", systemImage: "tag", action: onEditTopics)
                if item.status == .failed {
                    Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func button(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: systemImage, action: action)
    }

    private func openOriginal() {
        if let url = URL(string: item.url) { openURL(url) }
    }
}
