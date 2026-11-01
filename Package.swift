// swift-tools-version:6.0
// LocalizeAgent: an app's translations, harvested from its Swift and written in every language asked, as a Granite agent
// package. An app that links it finds the `localize` agent through Granite's roster, with nothing listed by hand.

import PackageDescription

let package = Package(
    name: "LocalizeAgent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalizeAgent", targets: ["LocalizeAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "LocalizeAgent",
            dependencies: [.product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "LocalizeAgentTests",
            dependencies: ["LocalizeAgent", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
