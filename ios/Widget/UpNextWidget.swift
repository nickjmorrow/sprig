import BouquetCore
import SwiftUI
import WidgetKit

/// Home-screen widget: what you were reading, then a few random unread picks, each with a
/// button to mark it done.
@main
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: PicksProvider()) { entry in
            PicksView(picks: entry.picks)
                .containerBackground(Marigold.ink, for: .widget)
        }
        .configurationDisplayName("Up next")
        .description("Pick up where you left off, or try something new.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The Marigold Tarot widget's palette (~/Projects/tarot/app/Shared/Theme.swift): black card
/// stock, gold foil, warm white ink.
private enum Marigold {
    static let gold = Color(red: 194 / 255, green: 164 / 255, blue: 83 / 255)
    static let ink = Color(red: 11 / 255, green: 10 / 255, blue: 8 / 255)
    static let text = Color(red: 242 / 255, green: 237 / 255, blue: 227 / 255)
    static let muted = text.opacity(0.62)

    static func serif(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Baskerville-SemiBold" : "Baskerville", size: size)
    }
}

struct PicksEntry: TimelineEntry {
    let date: Date
    let picks: WidgetPicks
}

struct PicksProvider: TimelineProvider {
    func placeholder(in context: Context) -> PicksEntry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PicksEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Reloads on the hour so the suggestions turn over (the hour seeds the shuffle); the app
    /// reloads it after each sync.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PicksEntry>) -> Void) {
        let now = Date()
        let nextHour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry(at: now)], policy: .after(nextHour)))
    }

    private func entry(at date: Date) -> PicksEntry {
        let hour = UInt64(date.timeIntervalSince1970 / 3600)
        let picks = (try? LocalStore.shared().widgetPicks(seed: hour))
        return PicksEntry(date: date, picks: picks ?? WidgetPicks(continueReading: [], suggestions: []))
    }
}

struct PicksView: View {
    let picks: WidgetPicks
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if picks.continueReading.isEmpty && picks.suggestions.isEmpty {
            empty
        } else if family == .systemSmall {
            small
        } else {
            list(picks.limited(to: family == .systemLarge ? 8 : 3))
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Marigold.gold)
            Text("Inbox is clear").font(Marigold.serif(15)).foregroundStyle(Marigold.muted)
        }
    }

    @ViewBuilder
    private var small: some View {
        let isStarted = !picks.continueReading.isEmpty
        if let item = picks.continueReading.first ?? picks.suggestions.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(isStarted ? "CONTINUE" : "TRY THIS")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Marigold.gold.opacity(0.8))
                    Spacer()
                    DoneButton(itemID: item.id)
                }
                Text(item.displayTitle)
                    .font(Marigold.serif(17, bold: true))
                    .foregroundStyle(isStarted ? Marigold.gold : Marigold.text)
                    .lineLimit(3)
                Spacer(minLength: 0)
                // No room for the site beside "16 min left" at this size.
                MetaLine(item: item, showsSite: false)
                if isStarted { ProgressLine(progress: item.progress) }
            }
            .widgetURL(item.link)
        }
    }

    /// One list, no headings: started items sit on top in gold, suggestions follow in white.
    private func list(_ shown: WidgetPicks) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shown.continueReading) { PickRow(item: $0, isStarted: true) }
            ForEach(shown.suggestions) { PickRow(item: $0, isStarted: false) }
            Spacer(minLength: 0)
        }
    }
}

private struct PickRow: View {
    let item: Item
    let isStarted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: item.link) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle)
                        .font(Marigold.serif(15.5, bold: true))
                        .foregroundStyle(isStarted ? Marigold.gold : Marigold.text)
                        .lineLimit(1)
                    MetaLine(item: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DoneButton(itemID: item.id)
        }
    }
}

/// "site · 7 min left" for started items, "site · 12 min" for the rest.
private struct MetaLine: View {
    let item: Item
    var showsSite = true

    var body: some View {
        HStack(spacing: 4) {
            if showsSite {
                Text(item.displaySite).lineLimit(1)
                Text("·")
            }
            Text(time).foregroundStyle(Marigold.gold).fixedSize()
        }
        .font(.system(size: 11).italic())
        .foregroundStyle(Marigold.muted)
    }

    private var time: String {
        if item.progress >= 0.98 { return "Read" }
        guard item.progress >= WidgetPicks.startedProgress else { return "\(item.minutes) min" }
        let left = (Double(item.minutes) * (1 - item.progress)).rounded(.up)
        return "\(max(1, Int(left))) min left"
    }
}

private struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Marigold.gold.opacity(0.2))
                Capsule().fill(Marigold.gold).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 3)
    }
}

/// A gold-foil ring with a check, like the deck's card borders.
private struct DoneButton: View {
    let itemID: String

    var body: some View {
        Button(intent: MarkDoneIntent(itemID: itemID)) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Marigold.gold)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Marigold.gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension Item {
    /// Opens the item in the app's reader.
    var link: URL { URL(string: "bouquet://item/\(id)")! }
}
