import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// System colors, so Sprig follows light and dark mode and Increase Contrast, plus one tint: the icon's sage and teal.
enum Theme {
    #if canImport(UIKit)
    static let bg = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    static let control = Color(uiColor: .tertiarySystemFill)
    static let line = Color(uiColor: .separator)
    #else
    static let bg = Color(nsColor: .textBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let control = Color(nsColor: .quaternaryLabelColor)
    static let line = Color(nsColor: .separatorColor)
    #endif
    static let text = Color.primary
    static let dim = Color.secondary
    static let faint = Color(white: 0.5).opacity(0.75)
    /// Interactive state and reading time. Dark enough for 4.5:1 on white, light enough on black.
    static let accent = Color(light: 0x1F6F62, dark: 0x6AA89A)
    /// Stars: darker gold on light backgrounds so the outline clears 3:1.
    static let star = Color(light: 0xB07A00, dark: 0xFFD60A)
    /// Text on an accent fill.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0F2321)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Color(hex: dark)) : NSColor(Color(hex: light))
        })
        #endif
    }
}
