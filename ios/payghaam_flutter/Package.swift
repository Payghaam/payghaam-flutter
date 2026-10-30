// swift-tools-version: 5.9

import Foundation
import PackageDescription

let package = Package(
    name: "payghaam_flutter",
    platforms: [
        // Must match Payghaam's minimum (payghaam-ios's Package.swift: .iOS(.v15))
        // — SPM enforces this transitively as a hard build error, unlike
        // CocoaPods which only warns on a mismatched s.platform.
        .iOS("15.0"),
    ],
    products: [
        .library(name: "payghaam-flutter", targets: ["payghaam_flutter"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Canonical native SDK, resolved from its own repo (not a local path —
        // payghaam-ios and payghaam-flutter are separate repos). Only exercised
        // by SPM-based consumers; the CocoaPods path (the tested integration,
        // via payghaam_flutter.podspec) resolves the equivalent 'Payghaam' pod
        // through the consuming app's Podfile instead.
        // Live Activities APIs require 0.1.4+.
        .package(url: "https://github.com/payghaam/payghaam-ios.git", from: "0.1.6"),
    ],
    targets: [
        .target(
            name: "payghaam_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Payghaam", package: "payghaam-ios"),
            ]
        ),
    ]
)
