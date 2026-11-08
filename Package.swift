// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gymie",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gymie", targets: ["Gymie"]),
    ],
    targets: [
        // Pure logic ported from the Squat Overflow extension: schedule, XP, challenges,
        // routine, activity, catalog, pose protocol and the GitHub stats file format.
        .target(name: "GymieCore"),
        // The menu bar app: SwiftUI views, camera, pose client, presence detection, GitHub sync.
        .executableTarget(
            name: "Gymie",
            dependencies: ["GymieCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "GymieCoreTests", dependencies: ["GymieCore"]),
    ]
)
