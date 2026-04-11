//swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MyArchive",
    products: [
        .executable(name: "myarchive-cli", targets: ["MyArchiveCLI"]),
        .executable(name: "MyArchiveGUI", targets: ["MyArchiveGUI"]),
    ],
    targets: [
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [
                .apt(["libssl-dev"]),
                .brew(["openssl@3"]),
            ]
        ),
        .systemLibrary(
            name: "CZlib",
            pkgConfig: "zlib",
            providers: [
                .apt(["zlib1g-dev"]),
                .brew(["zlib"]),
            ]
        ),
        .target(
            name: "ArchiveCore",
            dependencies: ["COpenSSL", "CZlib"],
            path: "Sources/ArchiveCore",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++17"]),
            ],
            linkerSettings: [
                .linkedLibrary("crypto"),
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "ArchiveBridge",
            dependencies: ["ArchiveCore"],
            path: "Sources/ArchiveBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++17"]),
            ],
            linkerSettings: [
                .linkedLibrary("crypto"),
                .linkedLibrary("z"),
            ]
        ),
        .executableTarget(
            name: "MyArchiveCLI",
            dependencies: ["ArchiveCore"],
            path: "Sources/MyArchiveCLI",
            cxxSettings: [
                .unsafeFlags(["-std=c++17"]),
            ],
            linkerSettings: [
                .linkedLibrary("crypto"),
                .linkedLibrary("z"),
            ]
        ),
        .executableTarget(
            name: "MyArchiveGUI",
            dependencies: ["ArchiveBridge"],
            path: "Sources/MyArchiveGUI",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS(.v13)])),
                .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
                .linkedFramework("UniformTypeIdentifiers", .when(platforms: [.macOS])),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
