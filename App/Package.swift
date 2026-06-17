// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZRImporter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZRImporter", targets: ["ZRImporter"])
    ],
    targets: [
        .executableTarget(
            name: "ZRImporter",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("QuickLook"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
