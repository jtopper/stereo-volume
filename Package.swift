// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "stereo-vol",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "stereo-vol",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Carbon"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
