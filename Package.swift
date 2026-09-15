// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "Curv",
  platforms: [.macOS(.v15)],
  targets: [
    .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
    .target(name: "SMCKit", dependencies: ["CSMC"]),
    .executableTarget(name: "fancurved", dependencies: ["SMCKit"]),
    .executableTarget(
      name: "Curv",
      dependencies: ["SMCKit"],
      linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
