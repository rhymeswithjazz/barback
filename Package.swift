// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barback",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Barback", targets: ["Barback"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        // Pure logic: the allow list format, menu bar geometry, and the icon, shortcut and
        // auto-close settings. Tested without a UI.
        .target(name: "BarbackCore"),
        .executableTarget(
            name: "Barback",
            dependencies: [
                "BarbackCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // scripts/release.sh puts Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // Embeds Info.plist in the binary, so `swift run` already has the bundle
                // identifier (for its preferences) and runs as a menu bar agent.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", Context.packageDirectory + "/Resources/Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "BarbackCoreTests", dependencies: ["BarbackCore"]),
    ]
)
