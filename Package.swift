// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "Curv",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
    .target(name: "SMCKit", dependencies: ["CSMC"]),
    .executableTarget(name: "fancurved", dependencies: ["SMCKit"]),
    .executableTarget(
      name: "Curv",
      dependencies: ["SMCKit"],
      linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
    ),
  ]
)
