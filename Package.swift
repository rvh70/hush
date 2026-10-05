// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hush",
            path: "Sources/Hush",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
