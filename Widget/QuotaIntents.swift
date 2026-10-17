import AppIntents
import Foundation
import QuotaCore
import WidgetKit

enum WidgetKind {
    static let orbit = "AIQuotaWidget"
    static let ledger = "AIQuotaLedgerWidget"
}

/// The small widget's current provider. WidgetKit has no swipe, so a tap on › advances it.
/// The index lives in the widget extension's own preferences, not in the shared snapshot.
enum ProviderCursor {
    private static let key = "smallProviderIndex"

    static func index(count: Int) -> Int {
        ProviderCycle.clamped(UserDefaults.standard.integer(forKey: key), count: count)
    }

    static func advance(count: Int) {
        UserDefaults.standard.set(ProviderCycle.next(after: index(count: count), count: count), forKey: key)
    }
}

struct NextProviderIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Next Provider"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        ProviderCursor.advance(count: SnapshotStore.read()?.rows.count ?? ProviderTile.placeholders.count)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.orbit)
        return .result()
    }
}
