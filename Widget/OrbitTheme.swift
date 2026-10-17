import QuotaCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Arcmeter's palette: glossy black with white gauges that turn orange, then red, as quota runs out.
enum OrbitTheme {
    static let top = Color(hex: 0x17171A)
    static let bottom = Color(hex: 0x030304)
    static let text = Color.white
    static let muted = Color.white.opacity(0.62)
    static let weekly = Color.white.opacity(0.9)
    static let logo = Color.white
    static let track = Color.white.opacity(0.17)
    static let gauge = Color.white
    static let warning = Color(hex: 0xFF9F0A)
    static let critical = Color(hex: 0xFF453A)
    /// Authorization and stale cues share the warning orange.
    static let stale = warning

    /// White while healthy; orange below 20% remaining, red below 10%.
    static func fill(_ percent: Double?) -> Color {
        switch QuotaLevel(remaining: percent) {
        case .normal: return gauge
        case .warning: return warning
        case .critical: return critical
        }
    }

    /// Deep black with a soft sheen across the top edge, as WidgetKit can render it.
    static var background: some View {
        ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0), .init(color: .white.opacity(0.03), location: 0.32),
                                   .init(color: .clear, location: 0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}
