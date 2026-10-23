// swift-tools-version:5.9
import PackageDescription

// A Linux-only harness that runs the app's real APIClient and LibraryStore
// against the live server, so the import -> library flow can be verified
// without a device or a simulator. See tools/livecheck/README.md.
//
// The app's sources and the check are compiled as ONE module, because the
// app's types are internal.
let package = Package(
    name: "LiveCheck",
    platforms: [.macOS(.v12)],
    targets: [
        // A stand-in for Apple's Combine, which does not exist on Linux.
        .target(name: "Combine", path: "Shims/Combine"),
        .executableTarget(
            name: "LiveCheck",
            dependencies: ["Combine"],
            path: "Sources"
        ),
    ]
)
