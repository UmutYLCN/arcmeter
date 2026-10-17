import QuotaCore
import SwiftUI
import WidgetKit

/// Orbit / Ledger: one row per provider, 5h and 7d bars side by side.
struct LedgerLargeView: View {
    let entry: QuotaEntry

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ForEach(Array(entry.tiles.enumerated()), id: \.element.id) { index, tile in
                    if index > 0 { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
                    row(tile).frame(maxHeight: .infinity)
                }
            }.padding(.bottom, 17)
            OrbitFooter(entry: entry)
        }
        .padding(18).foregroundStyle(OrbitTheme.text)
    }

    private func row(_ tile: ProviderTile) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ProviderLogo(mark: tile.mark, size: 17)
                Text(tile.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                if tile.availability == .authorizationNeeded {
                    Text("Authorize").font(.system(size: 9)).foregroundStyle(OrbitTheme.stale)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                window("5h", limiting: tile.fiveHourIsLow, percent: tile.fiveHour, reset: nil, tile: tile,
                       valueSize: 22, weight: .semibold, fill: OrbitTheme.arc)
                window("7d", limiting: tile.weeklyIsLow, percent: tile.weekly,
                       reset: ResetCountdown.text(until: tile.weeklyReset, now: entry.date), tile: tile,
                       valueSize: 15, weight: .medium, fill: tile.weeklyIsLow ? OrbitTheme.limitingBar : OrbitTheme.weeklyBar)
            }
        }
        .padding(.vertical, 8)
        .opacity(tile.isStale ? 0.6 : 1)
    }

    private func window(_ label: String, limiting: Bool, percent: Double?, reset: String?, tile: ProviderTile,
                        valueSize: CGFloat, weight: Font.Weight, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label + (limiting ? "*" : "")).font(.system(size: 9)).foregroundStyle(OrbitTheme.muted)
                Text(percent.map { "\(PercentText.text($0))%" } ?? "—")
                    .font(.system(size: valueSize, weight: weight)).monospacedDigit()
                    .foregroundStyle(label == "5h" ? OrbitTheme.text : OrbitTheme.weekly)
                Spacer(minLength: 0)
                if let reset { Text("↻ " + reset).font(.system(size: 8)).foregroundStyle(OrbitTheme.muted).lineLimit(1) }
            }
            GeometryReader { geometry in
                Capsule().fill(OrbitTheme.track).overlay(alignment: .leading) {
                    Capsule().fill(fill).frame(width: geometry.size.width * RingGauge.fraction(percent))
                }
            }.frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) \(label == "5h" ? "5-hour" : "weekly"): "
            + (percent.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }
}
