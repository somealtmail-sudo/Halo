// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "Halo", targets: ["Halo"])],
    targets: [
        .target(name: "HaloCore"),
        .executableTarget(name: "Halo", dependencies: ["HaloCore"]),
        .testTarget(name: "HaloCoreTests", dependencies: ["HaloCore"])
    ],
    swiftLanguageModes: [.v5]
)
