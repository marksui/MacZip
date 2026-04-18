//swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .executable(name: "myarchive-cli", targets: ["MyArchiveCLI"]),
]

var targets: [Target] = [
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
]

#if os(macOS)
products.append(.executable(name: "MyArchiveGUI", targets: ["MyArchiveGUI"]))
targets.append(
    .executableTarget(
        name: "MyArchiveGUI",


        path: "Sources/MyArchiveGUI",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("UniformTypeIdentifiers"),
        ]
    )
)
#endif

let package = Package(
    name: "MyArchive",
    platforms: [
        .macOS(.v12),
    ],
    products: products,
    targets: targets,
    cxxLanguageStandard: .cxx17
)
