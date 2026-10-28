import BouquetCore
import SwiftUI

/// The floating glass bar at the bottom of the reader.
struct ReaderBar: View {
    let item: Item
    let onFontSize: () -> Void
    let onFavorite: () -> Void
    let onArchive: () -> Void
    let onEditTopics: () -> Void
    let onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 26) {
            if item.kind == .tweet {
                button("Open in X", systemImage: "arrow.up.right.square") { openOriginal() }
            } else {
                button("Text size", systemImage: "textformat.size", action: onFontSize)
            }
            button(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.fill" : "star", action: onFavorite)
                .foregroundStyle(item.favorite ? Theme.accent : Theme.text)
            if item.location != .archive {
                button("Archive", systemImage: "archivebox", action: onArchive)
            }
            Menu {
                Button("Open original", systemImage: "safari") { openOriginal() }
                if let url = URL(string: item.url) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Edit topics", systemImage: "tag", action: onEditTopics)
                if item.status == .failed {
                    Button("Try again", systemImage: "arrow.clockwise", action: onRetry)
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
            .accessibilityLabel("More")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.bottom, 14)
    }

    private func button(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 28, height: 28)
        }
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: item.favorite)
    }

    private func openOriginal() {
        if let url = URL(string: item.url) { openURL(url) }
    }
}
