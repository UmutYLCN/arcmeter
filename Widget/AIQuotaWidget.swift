import SwiftUI
import WidgetKit

@main
struct AIQuotaWidget: Widget {
    let kind = "AIQuotaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaTimeline()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("AI Quota Widget")
            .description("Remaining Claude, Codex, and agy usage, resets, and projected run-out times.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}
