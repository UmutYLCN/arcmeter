import QuotaCore
import SwiftUI

/// Small stroked illustrations for the stale, no-data and authorization states (24-unit box).
enum StateIconKind { case clock, lock, cloudOff }

private struct IconShape: Shape {
    let kind: StateIconKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .clock:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 12, y: 7)); path.addLine(to: CGPoint(x: 12, y: 12)); path.addLine(to: CGPoint(x: 15.5, y: 14))
        case .lock:
            path.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 10), cornerSize: CGSize(width: 2.5, height: 2.5))
            path.move(to: CGPoint(x: 8, y: 11)); path.addLine(to: CGPoint(x: 8, y: 8))
            path.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 8, y: 3.6), control2: CGPoint(x: 16, y: 3.6))
            path.addLine(to: CGPoint(x: 16, y: 11))
        case .cloudOff:
            path.move(to: CGPoint(x: 7, y: 18.5))
            path.addCurve(to: CGPoint(x: 3.5, y: 14.9), control1: CGPoint(x: 4.9, y: 18.5), control2: CGPoint(x: 3.5, y: 16.9))
            path.addCurve(to: CGPoint(x: 6.6, y: 11.4), control1: CGPoint(x: 3.5, y: 13), control2: CGPoint(x: 4.9, y: 11.6))
            path.addCurve(to: CGPoint(x: 12, y: 6.7), control1: CGPoint(x: 7.2, y: 8.5), control2: CGPoint(x: 9.4, y: 6.7))
            path.addCurve(to: CGPoint(x: 17.4, y: 11.1), control1: CGPoint(x: 14.8, y: 6.7), control2: CGPoint(x: 16.9, y: 8.6))
            path.addCurve(to: CGPoint(x: 20.5, y: 14.8), control1: CGPoint(x: 19.3, y: 11.3), control2: CGPoint(x: 20.5, y: 12.7))
            path.addCurve(to: CGPoint(x: 17.5, y: 18.5), control1: CGPoint(x: 20.5, y: 16.9), control2: CGPoint(x: 19, y: 18.5))
            path.addLine(to: CGPoint(x: 7, y: 18.5))
            path.move(to: CGPoint(x: 4, y: 4)); path.addLine(to: CGPoint(x: 20, y: 20))
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
    }
}

struct StateIcon: View {
    let kind: StateIconKind
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            IconShape(kind: kind).stroke(color, style: StrokeStyle(lineWidth: size * 1.8 / 24, lineCap: .round, lineJoin: .round))
            if kind == .lock { Circle().fill(color).frame(width: size * 2.6 / 24, height: size * 2.6 / 24).offset(y: size * 4 / 24) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Tiny neutral clock beside a provider's name when its reading is older than the stale interval.
struct StaleMark: View {
    let tile: ProviderTile
    let size: CGFloat

    var body: some View {
        if tile.isStale && tile.availability == .measured {
            StateIcon(kind: .clock, size: size, color: OrbitTheme.muted)
        }
    }
}

extension ProviderTile {
    /// The illustration replacing the gauge when there is nothing measured to draw.
    var emptyIcon: StateIconKind? {
        switch availability {
        case .measured: return nil
        case .authorizationNeeded: return .lock
        case .unavailable: return .cloudOff
        }
    }
}
