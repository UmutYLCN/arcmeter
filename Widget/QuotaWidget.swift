import SwiftUI
import WidgetKit
import QuotaCore

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    var providerIndex = 0

    var tiles: [ProviderTile] { ProviderTile.tiles(for: snapshot, at: date) }
    var isStale: Bool { snapshot == nil || snapshot?.isStale(at: date) == true }
}

struct QuotaTimeline: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        let snapshot = SnapshotStore.read()
        completion(QuotaEntry(date: .now, snapshot: snapshot, providerIndex: providerIndex(snapshot)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.read()
        // A future entry turns stale on time even if WidgetKit delays a reload.
        var dates = [now]
        if let snapshot {
            let transitions = [snapshot.generatedAt] + snapshot.rows.map(\.observedAt)
            dates += transitions.map { $0.addingTimeInterval(Snapshot.staleInterval) }.filter { $0 > now }
        }
        let index = providerIndex(snapshot)
        let entries = Array(Set(dates)).sorted().map { QuotaEntry(date: $0, snapshot: snapshot, providerIndex: index) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }

    private func providerIndex(_ snapshot: Snapshot?) -> Int {
        ProviderCursor.index(count: snapshot?.rows.count ?? ProviderTile.placeholders.count)
    }
}

/// Orbit ring layouts: small cycles one provider per tap, medium shows a row, large a 2x2 grid.
struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: OrbitSmallView(entry: entry)
            case .systemLarge: OrbitLargeView(entry: entry)
            default: OrbitMediumView(entry: entry)
            }
        }
        .containerBackground(for: .widget) { OrbitTheme.background }
        .widgetURL(URL(string: "aiquotawidget://open"))
        .accessibilityElement(children: .contain)
    }
}

struct LedgerWidgetView: View {
    let entry: QuotaEntry

    var body: some View {
        LedgerLargeView(entry: entry)
            .containerBackground(for: .widget) { OrbitTheme.background }
            .widgetURL(URL(string: "aiquotawidget://open"))
            .accessibilityElement(children: .contain)
    }
}
