// swift-tools-version: 6.2
import PackageDescription
    
let package = Package(
    name: "CompanionCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
        .executable(name: "companion-m0", targets: ["companion-m0"]),
    ],
    targets: [
    .target(name: "CompanionCore"),
        .executableTarget(name: "companion-m0", dependencies: ["CompanionCore"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
    ]
)