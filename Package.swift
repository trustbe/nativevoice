// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeVoice",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything that does not need AppKit lives here, so it can be
        // tested with ./Scripts/test.sh — no network, no microphone, no windows.
        // The library gets its own String Catalog: String(localized:) resolves
        // against the calling module's bundle, so strings defined here would
        // never find the executable's catalog.
        .target(name: "NativeVoiceCore",
                resources: [.process("Resources/Localizable.xcstrings")]),
        .executableTarget(
            name: "NativeVoice",
            dependencies: ["NativeVoiceCore"],
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(name: "NativeVoiceCoreTests", dependencies: ["NativeVoiceCore"]),
    ]
)
