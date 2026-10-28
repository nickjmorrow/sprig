import BouquetCore
import SwiftUI

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SourceBadge(site: item.displaySite)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                meta
            }
            Spacer(minLength: 0)
            if item.favorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 6)
        .opacity(item.progress >= 0.98 ? 0.6 : 1)
    }

    private var meta: some View {
        HStack(spacing: 4) {
            Text(([item.displaySite] + item.topics.prefix(1)).joined(separator: " · "))
                .lineLimit(1)
            Text("·")
            switch item.status {
            case .pending:
                ProgressView().controlSize(.mini).tint(Theme.dim)
            case .failed:
                Text("Couldn't fetch").foregroundStyle(Theme.faint)
            case .ready, .webOnly:
                Text("\(item.minutes) min").fontWeight(.semibold).foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.dim)
    }
}
