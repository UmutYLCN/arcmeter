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
        let sizes: [(String, CGSize)] = [("small", CGSize(width: 170, height: 170)), ("medium", CGSize(width: 364, height: 170)),
                                         ("large", CGSize(width: 364, height: 382)), ("ledger", CGSize(width: 364, height: 382))]
        var count = 0
        for (name, size) in sizes {
            for state in ["fresh", "stale", "missing", "auth"] {
                // Small shows one provider per tap, so render every frame the button cycles through.
                let indexes = name == "small" && state == "fresh" ? Array(0..<4) : [0]
                for index in indexes {
                    let date = snapshot.generatedAt.addingTimeInterval(state == "stale" ? 1801 : 0)
                    let entry = QuotaEntry(date: date, snapshot: state == "missing" ? nil : (state == "auth" ? auth : snapshot),
                                           providerIndex: index)
                    let content: AnyView
                    switch name {
                    case "small": content = AnyView(OrbitSmallView(entry: entry))
                    case "medium": content = AnyView(OrbitMediumView(entry: entry))
                    case "large": content = AnyView(OrbitLargeView(entry: entry))
                    default: content = AnyView(LedgerLargeView(entry: entry))
                    }
                    let framed = content.frame(width: size.width, height: size.height)
                        .background(OrbitTheme.background).clipShape(RoundedRectangle(cornerRadius: 23))
                    let renderer = ImageRenderer(content: framed)
                    renderer.scale = 2
                    let image = try require(renderer.nsImage)
                    let bitmap = try require(NSBitmapImageRep(data: require(image.tiffRepresentation)))
                    let data = try require(bitmap.representation(using: .png, properties: [:]))
                    let suffix = indexes.count > 1 ? "-\(index)" : ""
                    try data.write(to: output.appendingPathComponent("\(name)-\(state)\(suffix).png"))
                    count += 1
                }
            }
        }
        print("Rendered \(count) Orbit widget previews (small, medium, large, ledger) to DerivedData/Previews.")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.fileReadUnknown) }
        return value
    }
}
