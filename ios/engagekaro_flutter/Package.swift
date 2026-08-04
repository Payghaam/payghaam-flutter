// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Flutter resolves this plugin's Package.swift through a symlink under each
// consuming app's `ios/Flutter/ephemeral/Packages/.packages/<plugin>/` — but
// SwiftPM computes THIS manifest's own relative `path:` dependencies against
// that symlink's nominal location, not its target, and the nominal location's
// depth from the repo root differs per consuming app (confirmed: a plain
// relative "../../../ios" resolves fine when this file is loaded directly,
// but resolves to `<app>/ios/Flutter/ephemeral/ios` — nonexistent — when
// loaded via Flutter's plugin symlink). Resolving #filePath's real path first
// makes the hop count to sdks/ios stable regardless of which app the symlink
// puts us under.
let engageKaroPath = URL(fileURLWithPath: #filePath)
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .appendingPathComponent("../../../ios")
    .standardizedFileURL
    .path

let package = Package(
    name: "engagekaro_flutter",
    platforms: [
        // Must match EngageKaro's minimum (Package.swift: .iOS(.v15)) — SPM
        // enforces this transitively as a hard build error, unlike CocoaPods
        // which only warns on a mismatched s.platform.
        .iOS("15.0"),
    ],
    products: [
        .library(name: "engagekaro-flutter", targets: ["engagekaro_flutter"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Canonical native SDK — see sdk-native-wrapper-design.md. Only
        // exercised by SPM-based consumers; the CocoaPods path (the tested
        // one, via engagekaro_flutter.podspec) resolves the equivalent
        // 'EngageKaro' pod via the app's Podfile instead.
        .package(name: "EngageKaro", path: engageKaroPath),
    ],
    targets: [
        .target(
            name: "engagekaro_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "EngageKaro", package: "EngageKaro"),
            ]
        ),
    ]
)
