// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LearnCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LearnCore", targets: ["LearnCore"]),
    ],
    targets: [
        .target(name: "LearnCore", resources: [.process("Resources")]),
        .testTarget(name: "LearnCoreTests", dependencies: ["LearnCore"]),
    ]
)
