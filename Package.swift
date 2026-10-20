// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LocalModelWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ModelWidgetCore", targets: ["ModelWidgetCore"]),
        .library(name: "LocalModelWidgetPanel", targets: ["LocalModelWidgetPanel"]),
        .executable(name: "LocalModelWidget", targets: ["LocalModelWidget"]),
        .executable(name: "t3boii-feed", targets: ["T3boiiFeed"]),
        .executable(name: "ModelWidgetChecks", targets: ["ModelWidgetChecks"])
    ],
    targets: [
        .target(name: "ModelWidgetCore"),
        .target(
            name: "LocalModelWidgetPanel",
            dependencies: ["ModelWidgetCore"]
        ),
        .executableTarget(
            name: "LocalModelWidget",
            dependencies: ["ModelWidgetCore", "LocalModelWidgetPanel"]
        ),
        .executableTarget(
            name: "T3boiiFeed",
            dependencies: ["ModelWidgetCore"]
        ),
        .executableTarget(
            name: "ModelWidgetChecks",
            dependencies: ["ModelWidgetCore", "LocalModelWidgetPanel"],
            path: "Tests/ModelWidgetChecks",
            // main.swift holds an @main type, so a multi-file target must not treat it as top-level code.
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
