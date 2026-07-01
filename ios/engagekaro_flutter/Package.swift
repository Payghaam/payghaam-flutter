// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "engagekaro_flutter",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(name: "engagekaro-flutter", targets: ["engagekaro_flutter"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "engagekaro_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
