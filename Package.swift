// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmartDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SmartDock",
            path: "Sources/SmartDock",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
