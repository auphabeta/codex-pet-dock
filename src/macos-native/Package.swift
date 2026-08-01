// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexPetDockMacOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CodexPetDockMacOS",
            targets: ["CodexPetDockMacOS"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexPetDockMacOS",
            path: "Sources/CodexPetDockMacOS"
        )
    ]
)
