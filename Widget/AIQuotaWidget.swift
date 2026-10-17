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
            .configurationDisplayName("Arcmeter")
            .description("Arcmeter shows remaining 5-hour quota as a ring, with weekly quota and reset, for Claude, Codex, and agy.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct AIQuotaLedgerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.ledger, provider: QuotaTimeline()) { LedgerWidgetView(entry: $0) }
            .configurationDisplayName("Arcmeter Ledger")
            .description("Arcmeter with one row per provider and 5-hour and weekly bars side by side.")
            .supportedFamilies([.systemLarge])
            .contentMarginsDisabled()
    }
}
