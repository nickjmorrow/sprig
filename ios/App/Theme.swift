import SwiftUI

/// Midnight Sun (dotfiles/themes/midnight-sun/palette.json).
enum Theme {
    static let bg = Color(hex: 0x0B1120)
    static let card = Color(hex: 0x131D33)
    static let control = Color(hex: 0x18233D)
    static let line = Color(hex: 0x22304F)
    static let text = Color(hex: 0xE3E8F2)
    static let dim = Color(hex: 0x9AA8C2)
    static let faint = Color(hex: 0x6B7A96)
    static let accent = Color(hex: 0xFFCC33)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
