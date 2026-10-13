// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TextAdventureGame",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "game", targets: ["Game"]),
        .library(
            name: "TextAdventureGame",
            targets: ["TextAdventureGame"]
        ),
    ],
    targets: [
        .target(
            name: "TextAdventureGame"
        ),
        .executableTarget(
            name: "Game",
            dependencies: ["TextAdventureGame"]
        ),
        .testTarget(
            name: "TextAdventureGameTests",
            dependencies: ["TextAdventureGame"]
        ),
    ],
    // The game is a single-threaded terminal loop; plain statics are fine.
    swiftLanguageModes: [.v5]
)
