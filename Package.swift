// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PhotoAgain", platforms: [.macOS(.v14)],
  products: [
    .library(name: "PhotoAgainCore", targets: ["PhotoAgainCore"]),
    .library(name: "PhotoAgainVision", targets: ["PhotoAgainVision"]),
    .library(name: "PhotoAgainOllama", targets: ["PhotoAgainOllama"]),
    .executable(name: "photoagain", targets: ["photoagain"]),
  ],
  targets: [
    .target(name: "PhotoAgainCore"),
    .target(name: "PhotoAgainOllama", dependencies: ["PhotoAgainCore"]),
    .target(name: "PhotoAgainVision", dependencies: ["PhotoAgainCore"]),
    .executableTarget(
      name: "photoagain", dependencies: ["PhotoAgainCore", "PhotoAgainVision", "PhotoAgainOllama"]),
    .testTarget(
      name: "PhotoAgainTests",
      dependencies: ["PhotoAgainCore", "PhotoAgainVision", "PhotoAgainOllama"]),
  ])
