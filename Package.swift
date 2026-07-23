// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "NotesApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotesApp", targets: ["NotesApp"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "NotesCore",
            dependencies: ["CSQLite"],
            path: "Sources/NotesCore"
        ),
        .executableTarget(
            name: "NotesApp",
            dependencies: ["NotesCore"],
            path: "Sources/NotesApp"
        ),
        .testTarget(
            name: "NotesCoreTests",
            dependencies: ["NotesCore"],
            path: "Tests/NotesCoreTests"
        )
    ]
)
