// swift-tools-version:5.9
import PackageDescription

// The session logic as a checked model, separate from the app so it can be
// explored in a second without a simulator. The app target will depend on this
// once the first slice graduates out of shadow mode.
let package = Package(
    name: "SessionModel",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SessionModel", targets: ["SessionModel"]),
        .library(name: "SessionWorld", targets: ["SessionWorld"]),
        .executable(name: "session-runner", targets: ["session-runner"]),
    ],
    dependencies: [
        // Pinned to an exact revision, not a branch: Correcto is pre-1.0 and its
        // API is expected to move. Bump deliberately, with the checker re-run.
        .package(
            url: "https://github.com/security-union/correcto.git",
            revision: "b2c67c6482635d17db027b37ef88fd1ce95151ce"),
        // Same exact version the app pins, for `PeerID` in `SessionState`.
        .package(url: "https://github.com/security-union/Stormo.git", exact: "2.0.2"),
    ],
    targets: [
        .target(
            name: "SessionModel",
            dependencies: [
                .product(name: "Correcto", package: "correcto"),
                .product(name: "Stormo", package: "Stormo"),
            ]),
        // The world the devices live in, plus the rules. Separate from the
        // model because this is where `CorrectoCheck` is allowed: the app links
        // `SessionModel` only, so no explorer reaches a shipped binary.
        .target(
            name: "SessionWorld",
            dependencies: [
                "SessionModel",
                .product(name: "Correcto", package: "correcto"),
                .product(name: "CorrectoCheck", package: "correcto"),
            ]),
        // Drive the machine by hand. Same model the checker explores, same
        // moves the checker enumerates, one at a time, chosen by a person.
        .executableTarget(
            name: "session-runner",
            dependencies: ["SessionModel", "SessionWorld"]),
        .testTarget(
            name: "SessionModelTests",
            dependencies: [
                "SessionModel",
                "SessionWorld",
                .product(name: "CorrectoCheck", package: "correcto"),
                .product(name: "CorrectoTesting", package: "correcto"),
            ]),
    ])
