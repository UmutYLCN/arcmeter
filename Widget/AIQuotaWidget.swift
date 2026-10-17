import SwiftUI
import WidgetKit

@main
struct AIQuotaWidgets: WidgetBundle {
    var body: some Widget {
        AIQuotaWidget()
        AIQuotaLedgerWidget()
    }
}

struct AIQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.orbit, provider: QuotaTimeline()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("AI Quota Orbit")
            .description("Remaining 5-hour quota as a ring, with weekly quota and reset, for Claude, Codex, and agy.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct AIQuotaLedgerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.ledger, provider: QuotaTimeline()) { LedgerWidgetView(entry: $0) }
            .configurationDisplayName("AI Quota Orbit Ledger")
            .description("One row per provider with 5-hour and weekly bars side by side.")
            .supportedFamilies([.systemLarge])
            .contentMarginsDisabled()
    }
}
