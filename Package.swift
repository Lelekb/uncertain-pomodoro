// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UncertainPomodoro",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PomodoroCore", path: "Sources/PomodoroCore"),
        .executableTarget(name: "UncertainPomodoro", dependencies: ["PomodoroCore"], path: "Sources/UncertainPomodoro"),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"], path: "Tests/PomodoroCoreTests"),
    ]
)
