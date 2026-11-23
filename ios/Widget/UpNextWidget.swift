import SprigCore
import SwiftUI
import WidgetKit

/// Home-screen widget: what you were reading, then a few random unread picks. Tapping a row
/// opens it in the app's reader.
@main
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: PicksProvider()) { entry in
            PicksView(picks: entry.picks)
                .containerBackground(for: .widget) { Plate.ink }
        }
        .configurationDisplayName("Up next")
        .description("Pick up where you left off, or try something new.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// The "engraved plate" home-screen theme, in the app icon's colors: its deep teal tile, a sage
/// frame, brass hairlines, a vermilion pip, bone and muted serif text.
private enum Plate {
    static let ink = Color(red: 0x0F / 255, green: 0x23 / 255, blue: 0x21 / 255)
    static let brass = Color(red: 0xC9 / 255, green: 0xA8 / 255, blue: 0x5C / 255)
    static let sage = Color(red: 0x6A / 255, green: 0xA8 / 255, blue: 0x9A / 255)
    static let vermilion = Color(red: 0xCF / 255, green: 0x6F / 255, blue: 0x45 / 255)
    static let bone = Color(red: 0xE8 / 255, green: 0xDC / 255, blue: 0xC0 / 255)
    static let muted = Color(red: 0x8D / 255, green: 0x8A / 255, blue: 0x80 / 255)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static let meta = Font.system(size: 11, design: .serif).italic()
    static let eyebrow = Font.system(size: 8.5, weight: .semibold)

    /// Where text starts: 23pt inside the inset frame line.
    static let textInset: CGFloat = 30
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
        ZStack {
            PlateFrame()
            if picks.continueReading.isEmpty && picks.suggestions.isEmpty {
                Text("Inbox is clear").font(Plate.meta).foregroundStyle(Plate.muted)
            } else if family == .systemSmall {
                small
            } else {
                list(picks.limited(to: family == .systemLarge ? 8 : 3))
            }
        }
    }

    @ViewBuilder
    private var small: some View {
        let isStarted = !picks.continueReading.isEmpty
        if let item = picks.continueReading.first ?? picks.suggestions.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(isStarted ? "CONTINUE" : "TRY THIS")
                    .font(Plate.eyebrow)
                    .tracking(1.8)
                    .foregroundStyle(Plate.brass)
                Text(item.displayTitle)
                    .font(Plate.title(16))
                    .foregroundStyle(isStarted ? Plate.brass : Plate.bone)
                    .lineLimit(3)
                Spacer(minLength: 0)
                MetaLine(item: item, showsSource: false)
                if isStarted { ProgressRule(progress: item.progress) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .widgetURL(item.link)
        }
    }

    /// One list, no headings, on an even rhythm: the first row in brass, the rest in bone, with
    /// a brass rule between rows.
    private func list(_ shown: WidgetPicks) -> some View {
        let rows = shown.continueReading + shown.suggestions
        let slots = family == .systemLarge ? 8 : 3
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowRule() }
                PickRow(item: item, isFirst: index == 0)
                    .frame(maxHeight: .infinity)
            }
            // Keep the rhythm when there are fewer items than rows.
            ForEach(rows.count..<max(rows.count, slots), id: \.self) { _ in
                Color.clear.frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, Plate.textInset)
        .padding(.top, 20)
        .padding(.bottom, 21)
    }
}

private struct PickRow: View {
    let item: Item
    let isFirst: Bool

    var body: some View {
        Link(destination: item.link) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(Plate.title(15))
                    .foregroundStyle(isFirst ? Plate.brass : Plate.bone)
                    .lineLimit(1)
                    .truncationMode(.tail)
                MetaLine(item: item)
            }
            // Sits a touch below center, closer to the rule under it, as in the mockup.
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

/// "@handle · 7 min left" or "author · 12 min"; "Read" once it's finished.
private struct MetaLine: View {
    let item: Item
    var showsSource = true

    var body: some View {
        Text(showsSource ? "\(source) · \(time)" : time)
            .font(Plate.meta)
            .foregroundStyle(Plate.muted)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// Tweets carry the handle as their site; articles show the author when there is one.
    private var source: String {
        if let site = item.site, site.hasPrefix("@") { return site }
        return item.author ?? item.displaySite
    }

    private var time: String {
        if item.isFinished { return "Read" }
        guard item.progress >= WidgetPicks.startedProgress else { return "\(item.minutes) min" }
        let left = (Double(item.minutes) * (1 - item.progress)).rounded(.up)
        return "\(max(1, Int(left))) min left"
    }
}

/// The frame: a sage hairline inset 7pt from the edge, with a brass dot on each side 23pt
/// from the top and the bottom.
private struct PlateFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Plate.sage, lineWidth: 0.6)
                    .opacity(0.7)
                    .padding(7)
                Path { path in
                    for point in [CGPoint(x: 7, y: 23), CGPoint(x: w - 7, y: 23),
                                  CGPoint(x: 7, y: h - 23), CGPoint(x: w - 7, y: h - 23)] {
                        path.addEllipse(in: CGRect(x: point.x - 1.3, y: point.y - 1.3, width: 2.6, height: 2.6))
                    }
                }
                .fill(Plate.brass)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A row rule: brass hairline with a small dot at both ends.
private struct RowRule: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, y = proxy.size.height / 2
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
            .stroke(Plate.brass.opacity(0.45), lineWidth: 0.4)
            Path { path in
                for x in [0, w] { path.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)) }
            }
            .fill(Plate.brass.opacity(0.8))
        }
        .frame(height: 1.8)
    }
}

/// Reading progress as a brass hairline: solid up to where he stopped, ending in a vermilion dot.
private struct ProgressRule: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, y = proxy.size.height / 2
            let end = w * min(max(progress, 0), 1)
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
            .stroke(Plate.brass.opacity(0.45), lineWidth: 0.4)
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: end, y: y))
            }
            .stroke(Plate.brass, lineWidth: 1)
            Path { path in
                path.addEllipse(in: CGRect(x: end - 1.3, y: y - 1.3, width: 2.6, height: 2.6))
            }
            .fill(Plate.vermilion)
        }
        .frame(height: 2.6)
    }
}

extension Item {
    /// Opens the item in the app's reader.
    var link: URL { URL(string: "sprig://item/\(id)")! }
}
