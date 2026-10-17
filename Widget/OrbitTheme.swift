import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Orbit's dark palette, shared by the ring and ledger layouts.
enum OrbitTheme {
    static let top = Color(hex: 0x263A4A)
    static let bottom = Color(hex: 0x141D2A)
    static let text = Color(hex: 0xF0F5FB)
    static let muted = Color(hex: 0xB3C1CD)
    static let weekly = Color(hex: 0xDCE7EC)
    static let logo = Color(hex: 0xE3EDF3)
    static let track = Color(hex: 0x3B4F5E)
    static let arc = Color(hex: 0xA9D4D4)
    static let stale = Color(hex: 0xFFB570)
    static let weeklyBar = Color(hex: 0x819CAA)
    static let limitingBar = Color(hex: 0xDDA16E)

    static var background: some View {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
