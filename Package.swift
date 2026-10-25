// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ROGGamingCenter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ROGGamingCenter", targets: ["ROGGamingCenter"]),
        .executable(name: "rogauracore", targets: ["rogauracore"]),
    ],
    targets: [
        // Pure Swift: models, presets, packet builder. No AppKit/IOKit.
        .target(name: "AuraCore"),
        // IOHID transport to the Aura controller.
        .target(name: "AuraHID", dependencies: ["AuraCore"]),
        .executableTarget(
            name: "ROGGamingCenter",
            dependencies: ["AuraCore", "AuraHID"]
        ),
        .executableTarget(
            name: "rogauracore",
            dependencies: ["AuraCore", "AuraHID"]
        ),
        .testTarget(name: "AuraCoreTests", dependencies: ["AuraCore"]),
    ]
)
