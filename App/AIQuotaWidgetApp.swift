import SwiftUI
import WidgetKit
import QuotaCore

@MainActor
@Observable
final class QuotaModel {
    var snapshot = SnapshotStore.read()
    var refreshing = false
    var error: String?
    private let reader = QuotaReader()
    private var polling: Task<Void, Never>?

    func start() {
        guard polling == nil else { return }
        polling = Task {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let result = try await reader.read()
            try SnapshotStore.write(result)
            snapshot = result
            error = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Could not decode or save quota data. Check quota-axi and the snapshot folder, then refresh."
            // Keep the last good timestamp so failure cannot make old data look fresh.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

@main
struct AIQuotaWidgetApp: App {
    @State private var model = QuotaModel()
    var body: some Scene {
        WindowGroup("AI Quota Widget") {
            ContentView(model: model)
                .onAppear { model.start() }
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 520, height: 490)
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    let model: QuotaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("AI quota").font(.largeTitle.bold())
                    Text("Remaining usage, at a glance").foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.refreshing ? "Refreshing…" : "Refresh") {
                    Task { await model.refresh() }
                }.disabled(model.refreshing)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let snapshot = model.snapshot {
                    VStack(spacing: 14) {
                        ForEach(snapshot.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).bold()
                                    Spacer()
                                    Text(row.percentRemaining.map { "\(Int($0.rounded()))% remaining" } ?? row.status)
                                }
                                if let percent = row.percentRemaining {
                                    ProgressView(value: percent, total: 100)
                                        .tint(row.runsOutBeforeReset ? .orange : .accentColor)
                                }
                                HStack(spacing: 4) {
                                    Text(row.limitingWindow.map { "\($0) limit ·" } ?? "Limit unknown ·")
                                    if let reset = row.resetsAt {
                                        Text("Resets")
                                        Text(reset, style: .relative)
                                    } else { Text("Reset unknown") }
                                    if let runout = row.projectedExhaustedAt {
                                        Text("· Runs out")
                                        Text(runout, style: .relative).foregroundStyle(.orange)
                                    }
                                    if row.isStale(at: context.date) { Text("· Stale").foregroundStyle(.orange) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        Text(snapshot.isStale(at: context.date) ? "Stale · Updated" : "Updated")
                        Text(snapshot.generatedAt, style: .relative)
                        Text("ago")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                } else {
                    Text("No snapshot yet. Refresh to read Claude, Codex, and agy.")
                        .foregroundStyle(.secondary).frame(height: 180)
                }
            }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.orange) }
            if model.snapshot?.rows.contains(where: { $0.provider == "claude" && $0.status == "authorization needed" }) == true {
                Text("Claude: re-authorize by running /usr/local/bin/quota-axi --provider claude --allow-keychain-prompt in Terminal. Approve Keychain access with Always Allow, then Refresh.")
                    .font(.callout).textSelection(.enabled)
            }
            Divider()
            Text("Refreshes every 5 minutes while the app is running. Keep the app running. Add AI Quota Widget using the desktop’s Edit Widgets gallery.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 520)
    }
}
