// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KnowledgeGraphNavigator_swift",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", .branch("master")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "1.7.4"),
        .package(url: "git@github.com:mark-watson/SparqlQuery_swift.git", .branch("main")),
        .package(url: "git@github.com:mark-watson/Nlp_swift.git", .branch("main")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "KnowledgeGraphNavigator_swift",
            dependencies: ["SparqlQuery_swift", "Nlp_swift", "SwiftyJSON", "SwiftSoup"]),
    ]
)
