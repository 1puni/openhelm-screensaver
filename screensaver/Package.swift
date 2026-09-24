// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenHelmChartSaver",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenHelmChartSaverCore", type: .static, targets: ["OpenHelmChartSaverCore"]),
        .library(name: "OpenHelmChartSaver", type: .dynamic, targets: ["OpenHelmChartSaver"]),
        .executable(name: "OpenHelmChartSaverPreview", targets: ["OpenHelmChartSaverPreview"]),
    ],
    targets: [
        .target(name: "OpenHelmChartSaverCore"),
        .target(
            name: "OpenHelmChartSaver",
            dependencies: ["OpenHelmChartSaverCore"],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenSaver"), .linkedFramework("ImageIO"),
            ]
        ),
        .executableTarget(
            name: "OpenHelmChartSaverPreview",
            dependencies: ["OpenHelmChartSaver"],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .testTarget(name: "OpenHelmChartSaverCoreTests", dependencies: ["OpenHelmChartSaverCore"]),
        .testTarget(name: "OpenHelmChartSaverTests", dependencies: ["OpenHelmChartSaver"]),
    ]
)
