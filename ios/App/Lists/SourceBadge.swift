import SwiftUI

/// A small rounded square with the source's first letter, colored from its name so each site keeps its color.
struct SourceBadge: View {
    let site: String

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                Text(letter)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.bg)
            }
    }

    private var letter: String {
        let name = site.hasPrefix("@") ? "𝕏" : site.replacingOccurrences(of: "www.", with: "")
        return String(name.prefix(1)).uppercased()
    }

    private var color: Color {
        if site.hasPrefix("@") { return Theme.text }
        // djb2: stable across launches, unlike Hasher.
        let hash = site.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.38, brightness: 0.95)
    }
}
