// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SprigCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "SprigCore", targets: ["SprigCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")],
    targets: [
        .target(name: "SprigCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "SprigCoreTests",
            dependencies: ["SprigCore", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
