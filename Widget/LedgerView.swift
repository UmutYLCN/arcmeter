import QuotaCore
import SwiftUI
import WidgetKit

/// Orbit / Ledger: one row per provider, 5h and 7d bars side by side.
struct LedgerLargeView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(entry.tiles.enumerated()), id: \.element.id) { index, tile in
                    if index > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                    row(tile).frame(maxHeight: .infinity)
                }
            }
            OrbitFooter(entry: entry).padding(.top, 4)
        }
        .padding(18).foregroundStyle(OrbitTheme.text)
    }

    private func row(_ tile: ProviderTile) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ProviderLogo(mark: tile.mark, size: 20)
                Text(tile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                StaleMark(tile: tile, size: 10)
                if tile.availability == .authorizationNeeded {
                    Text("Authorize").font(.system(size: 10)).foregroundStyle(OrbitTheme.muted)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                window("5h", percent: tile.fiveHour, reset: nil, tile: tile, valueSize: 28, weight: .semibold)
                window("7d", percent: tile.weekly, reset: ResetCountdown.text(until: tile.weeklyReset, now: entry.date),
                       tile: tile, valueSize: 19, weight: .medium)
            }
        }
        .padding(.vertical, 8)
        .opacity(tile.isStale ? OrbitTheme.dimmed : 1)
    }

    private func window(_ label: String, percent: Double?, reset: String?, tile: ProviderTile,
                        valueSize: CGFloat, weight: Font.Weight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label).font(.system(size: 11)).foregroundStyle(OrbitTheme.muted)
                Text(percent.map { "\(PercentText.text($0))%" } ?? "—")
                    .font(.system(size: valueSize, weight: weight)).monospacedDigit()
                    .foregroundStyle(label == "5h" ? OrbitTheme.text : OrbitTheme.weekly)
                Spacer(minLength: 0)
                if let reset { Text("↻ " + reset).font(.system(size: 10)).foregroundStyle(OrbitTheme.muted).lineLimit(1) }
            }
            GeometryReader { geometry in
                Capsule().fill(OrbitTheme.track).overlay(alignment: .leading) {
                    Capsule().fill(OrbitTheme.fill(percent)).frame(width: geometry.size.width * RingGauge.fraction(percent))
                }
            }.frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) \(label == "5h" ? "5-hour" : "weekly"): "
            + (percent.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }
}
