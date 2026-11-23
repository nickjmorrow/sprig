import SwiftUI

/// A small rounded square with the source's first letter, colored from its name so each site keeps its color.
struct SourceBadge: View {
    let site: String
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.56, weight: .bold, design: .rounded))
                    .foregroundStyle(isX ? Theme.bg : .white)
            }
            .accessibilityHidden(true)
    }

    private var letter: String {
        let name = isX ? "X" : site.replacingOccurrences(of: "www.", with: "")
        return String(name.prefix(1)).uppercased()
    }

    private var color: Color {
        if isX { return Theme.text }
        // djb2: stable across launches, unlike Hasher.
        let hash = site.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.6, brightness: 0.55)
    }

    /// X handles start with @; their tile is drawn in the label color so it shows in light and dark.
    private var isX: Bool { site.hasPrefix("@") }
}
