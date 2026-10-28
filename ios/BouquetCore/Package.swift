// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BouquetCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "BouquetCore", targets: ["BouquetCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")],
    targets: [
        .target(name: "BouquetCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "BouquetCoreTests",
            dependencies: ["BouquetCore", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
