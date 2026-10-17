import AppKit
import SwiftUI
import WidgetKit
import QuotaCore

@main
struct Preview {
    @MainActor
    static func main() throws {
        let fixture = URL(fileURLWithPath: "QuotaCore/Tests/QuotaCoreTests/Fixtures/quota-axi-v5.json")
        let snapshot = try QuotaDecoder.decode(Data(contentsOf: fixture))
        let output = URL(fileURLWithPath: "DerivedData/Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var authReport = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var authProviders = authReport["providers"] as! [[String: Any]]
        authProviders[0]["state"] = ["status": "auth_required", "stale": false]
        authReport["providers"] = authProviders
        let auth = try QuotaDecoder.decode(JSONSerialization.data(withJSONObject: authReport))
        for (name, family, width) in [("small", WidgetFamily.systemSmall, 164.0), ("medium", .systemMedium, 344.0)] {
            for state in ["fresh", "stale", "missing", "auth"] {
                let date = snapshot.generatedAt.addingTimeInterval(state == "stale" ? 1801 : 0)
                let entry = QuotaEntry(date: date, snapshot: state == "missing" ? nil : (state == "auth" ? auth : snapshot))
                let content = QuotaContentView(entry: entry, small: family == .systemSmall)
                    .frame(width: width, height: 164).background(Color(nsColor: .windowBackgroundColor))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try require(renderer.nsImage)
                let bitmap = try require(NSBitmapImageRep(data: require(image.tiffRepresentation)))
                let data = try require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("\(name)-\(state).png"))
            }
        }
        print("Rendered small and medium widgets, fresh/stale/missing/auth, to DerivedData/Previews.")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.fileReadUnknown) }
        return value
    }
}
