import SwiftUI
import WidgetKit
import QuotaCore

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct QuotaTimeline: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: .now, snapshot: SnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.read()
        // A future entry turns stale on time even if WidgetKit delays a reload.
        var dates = [now]
        if let snapshot {
            let transitions = [snapshot.generatedAt] + snapshot.rows.map(\.observedAt)
            dates += transitions.map { $0.addingTimeInterval(Snapshot.staleInterval) }
                .filter { $0 > now }
        }
        let entries = Array(Set(dates)).sorted().map { QuotaEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry
    var body: some View {
        QuotaContentView(entry: entry, small: family == .systemSmall)
    }
}

struct QuotaContentView: View {
    let entry: QuotaEntry
    let small: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 3 : 2) {
            HStack {
                Text("AI QUOTA").font(.system(size: small ? 9 : 10, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                if entry.snapshot == nil || entry.snapshot?.isStale(at: entry.date) == true {
                    Text("STALE").font(.system(size: small ? 8 : 9, weight: .bold)).foregroundStyle(.orange)
                }
            }
            if let snapshot = entry.snapshot {
                ForEach(snapshot.rows) { row in
                    rowView(row)
                }
                HStack(spacing: 2) {
                    Text("Updated")
                    Text(snapshot.generatedAt, style: .relative)
                    Text("ago")
                }.font(.system(size: small ? 8 : 9)).foregroundStyle(.secondary)
            } else {
                ForEach(["Claude", "Codex", "agy Gemini", "agy Claude/GPT"], id: \.self) { name in
                    HStack {
                        Text(name).bold()
                        Spacer(minLength: 2)
                        Text("No data").foregroundStyle(.secondary)
                    }.font(.system(size: small ? 9 : 12))
                }
                Text("Open app to refresh").font(.system(size: small ? 8 : 9)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "aiquotawidget://open"))
        .accessibilityElement(children: .contain)
    }

    private func quotaBar(percent: Double, warning: Bool) -> some View {
        GeometryReader { geometry in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule().fill(warning ? Color.orange : Color.accentColor)
                        .frame(width: geometry.size.width * percent / 100)
                }
        }
    }

    private func rowView(_ row: QuotaRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(row.name).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if !small, let percent = row.percentRemaining {
                    quotaBar(percent: percent, warning: row.runsOutBeforeReset)
                        .frame(width: 85, height: 3)
                }
                if let percent = row.percentRemaining {
                    Text("\(Int(percent.rounded()))%")
                        .monospacedDigit().foregroundStyle(row.runsOutBeforeReset ? .orange : .primary)
                } else {
                    Text(row.status).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                }
            }.font(.system(size: small ? 9 : 12))
            if let percent = row.percentRemaining {
                if small {
                    quotaBar(percent: percent, warning: row.runsOutBeforeReset).frame(height: 2)
                }
                HStack(spacing: 2) {
                    Text(row.limitingWindow ?? "?")
                    Text("· Reset")
                    if let reset = row.resetsAt { Text(reset, style: .relative) }
                    else { Text("unknown") }
                    if row.isStale(at: entry.date) { Text("· Stale").foregroundStyle(.orange) }
                    if !small, let runout = row.projectedExhaustedAt {
                        Text("· Out").foregroundStyle(.orange)
                        Text(runout, style: .relative).foregroundStyle(.orange)
                    }
                }.font(.system(size: small ? 7 : 9)).foregroundStyle(.secondary).lineLimit(1)
                if small, let runout = row.projectedExhaustedAt {
                    HStack(spacing: 2) {
                        Text("Out")
                        Text(runout, style: .relative)
                    }.font(.system(size: 7)).foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name + ": " + (row.percentRemaining.map { "\(Int($0.rounded())) percent remaining" } ?? row.status))
    }
}
