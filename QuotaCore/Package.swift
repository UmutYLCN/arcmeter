// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "QuotaCore", targets: ["QuotaCore"])],
    targets: [
        .target(name: "QuotaCore"),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"],
                    resources: [.copy("Fixtures")])
    ]
)
