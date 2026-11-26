import SprigCore
import SwiftUI

struct ItemRow: View {
    let item: Item
    /// While searching, the row shows the passage that matched with these words picked out.
    var searchTerms: [String] = []
    /// A selected row on the Mac sits on the accent highlight, where fixed colors wash out.
    @Environment(\.backgroundProminence) private var prominence
    private var isHighlighted: Bool { prominence == .increased }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                SourceBadge(site: item.displaySite)
                Text(item.displaySite)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if item.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? Theme.text : Theme.star)
                        .accessibilityLabel("Starred")
                }
            }
            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(isFinished ? Theme.dim : Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !searchTerms.isEmpty && !item.excerpt.isEmpty {
                Text(highlighted(item.excerpt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(3)
            }
            meta
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var isFinished: Bool { item.isFinished }

    private var meta: some View {
        HStack(spacing: 5) {
            switch item.status {
            case .pending:
                ProgressView().controlSize(.mini)
                Text("Fetching")
            case .failed:
                Label("Couldn't fetch", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
            case .webOnly:
                Label("Link only", systemImage: "link").labelStyle(.titleAndIcon)
            case .ready:
                readingTime
            }
            if let topic = item.topics.first {
                Text("·").accessibilityHidden(true)
                Text(topic)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.dim)
        .lineLimit(1)
    }

    @ViewBuilder
    private var readingTime: some View {
        if isFinished {
            Label("Read", systemImage: "checkmark").labelStyle(.titleAndIcon)
        } else if item.progress > 0.02 {
            Text("\(minutesLeft) min left")
                .fontWeight(.semibold)
                .foregroundStyle(isHighlighted ? Theme.text : Theme.accent)
                .monospacedDigit()
        } else {
            Text("\(item.minutes) min")
                .fontWeight(.semibold)
                .foregroundStyle(isHighlighted ? Theme.text : Theme.accent)
                .monospacedDigit()
        }
    }

    private var minutesLeft: Int {
        max(1, Int((Double(item.minutes) * (1 - item.progress)).rounded(.up)))
    }

    private func highlighted(_ passage: String) -> AttributedString {
        var text = AttributedString(passage)
        for term in searchTerms {
            var searchStart = text.startIndex
            while let match = text[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[match].foregroundColor = Theme.text
                text[match].font = .subheadline.weight(.semibold)
                if !isHighlighted { text[match].backgroundColor = Theme.accent.opacity(0.2) }
                searchStart = match.upperBound
            }
        }
        return text
    }
}

/// Puts the story's address on the clipboard.
@MainActor func copyLink(to item: Item) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(item.url, forType: .string)
    #else
    UIPasteboard.general.string = item.url
    #endif
}
