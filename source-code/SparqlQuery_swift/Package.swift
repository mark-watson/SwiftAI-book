// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SparqlQuery_swift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SparqlQuery_swift",
            targets: ["SparqlQuery_swift"]),
    ],
    targets: [
        .target(
            name: "SparqlQuery_swift"),
        .testTarget(
            name: "SparqlQuery_swiftTests",
            dependencies: ["SparqlQuery_swift"]),
    ]
)
