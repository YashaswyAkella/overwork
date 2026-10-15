// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overwork",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Overwork",
            path: "Sources/Overwork",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
            ]
        )
    ]
)
