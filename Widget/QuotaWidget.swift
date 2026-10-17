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
            dates += transitions.map { $0.addingTimeInterval(Snapshot.staleInterval) }.filter { $0 > now }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("AI QUOTA").font(.system(size: small ? 8 : 10, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                if entry.snapshot == nil || entry.snapshot?.isStale(at: entry.date) == true {
                    Text("STALE").font(.system(size: small ? 7 : 9, weight: .bold)).foregroundStyle(.orange)
                }
            }
            if let snapshot = entry.snapshot {
                ForEach(snapshot.rows) { row in rowView(row) }
                HStack(spacing: 2) {
                    Text("* limit · Updated")
                    Text(snapshot.generatedAt, style: .relative)
                    Text("ago")
                }.font(.system(size: small ? 6.5 : 8)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                ForEach(["Claude", "Codex", "agy Gemini", "agy Claude/GPT"], id: \.self) { name in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).bold()
                        Text("5h —    7d —   ·   No data").foregroundStyle(.secondary)
                    }.font(.system(size: small ? 8 : 10))
                }
                Text("Open app to refresh").font(.system(size: small ? 7 : 9)).foregroundStyle(.secondary)
            }
        }
        .padding(small ? 7 : 10)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "aiquotawidget://open"))
        .accessibilityElement(children: .contain)
    }

    private func rowView(_ row: QuotaRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(row.name + (row.status == "authorization needed" ? ":" : ""))
                    .fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(forecast(row)).font(.system(size: small ? 6.5 : 8))
                    .foregroundStyle(row.runsOutBeforeReset && !row.isStale(at: entry.date) ? .orange : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }.font(.system(size: small ? 8 : 10))
            HStack(spacing: small ? 6 : 12) {
                ForEach(row.windows) { window in windowView(window) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func windowView(_ window: WindowQuota) -> some View {
        Group {
            if small {
                VStack(alignment: .leading, spacing: 1) {
                    meter(window)
                    Text(resetText(window)).font(.system(size: 6.5)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                HStack(spacing: 4) {
                    meter(window)
                    Text(resetText(window)).font(.system(size: 8)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((window.period == .fiveHour ? "5-hour" : "Weekly") + ": "
            + (window.percentRemaining.map { "\(Int($0.rounded())) percent remaining" } ?? window.status))
    }

    private func meter(_ window: WindowQuota) -> some View {
        HStack(spacing: 3) {
            Text(window.period.label + (window.isLimiting ? "*" : ""))
                .fontWeight(window.isLimiting ? .bold : .regular).fixedSize()
            Text(window.percentRemaining.map { "\(Int($0.rounded()))%" } ?? "—")
                .monospacedDigit().fixedSize()
            if let percent = window.percentRemaining {
                GeometryReader { geometry in
                    Capsule().fill(.quaternary).overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: geometry.size.width * percent / 100)
                    }
                }.frame(minWidth: small ? 10 : 20, maxWidth: .infinity).frame(height: 2)
            } else { Spacer(minLength: 0) }
        }.font(.system(size: small ? 7 : 9))
    }

    private func resetText(_ window: WindowQuota) -> String {
        guard let date = window.resetsAt else { return "↻ not reported" }
        return date <= entry.date ? "↻ due" : "↻ in " + relative(date)
    }

    private func forecast(_ row: QuotaRow) -> String {
        if row.status == "authorization needed" { return row.status }
        if row.isStale(at: entry.date) { return "Stale" }
        if row.status != "measured" { return row.status }
        if row.runwayStatus == "exhausted_now" { return "Empty now" }
        if let out = row.projectedExhaustedAt { return "Out ~" + relative(out) }
        if row.runwayStatus == "through_reset" { return "Lasts to reset" }
        return "No forecast"
    }

    private func relative(_ date: Date) -> String {
        let interval = date.timeIntervalSince(entry.date)
        guard interval > 0 else { return "now" }
        guard interval >= 60 else { return "<1m" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = small ? 1 : 2
        return formatter.string(from: interval) ?? "?"
    }
}
