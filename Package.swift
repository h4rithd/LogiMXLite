// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LogiMXLite", platforms: [.macOS(.v15)], products: [
    .library(name: "LogiCore", targets: ["LogiCore"]),
    .executable(name: "LogiMXLite", targets: ["LogiMXLite"])
], targets: [
    .target(name: "LogiCore"),
    .executableTarget(name: "LogiMXLite", dependencies: ["LogiCore"], resources: [.process("Resources")]),
    .testTarget(name: "LogiCoreTests", dependencies: ["LogiCore"])
], swiftLanguageModes: [.v6])
