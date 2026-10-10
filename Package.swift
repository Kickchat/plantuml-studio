// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PlantUMLStudio", platforms: [.macOS(.v14)],
  products: [.executable(name: "PlantUMLStudio", targets: ["PlantUMLStudio"])],
  targets: [
    .target(name: "PlantUMLCore"), .target(name: "Rendering"),
    .target(name: "SequenceModule", dependencies: ["PlantUMLCore"]),
    .target(name: "ERModule", dependencies: ["PlantUMLCore"]),
    .executableTarget(
      name: "PlantUMLStudio",
      dependencies: ["PlantUMLCore", "Rendering", "SequenceModule", "ERModule"]),
    .testTarget(
      name: "PlantUMLCoreTests",
      dependencies: ["PlantUMLCore", "Rendering", "SequenceModule", "ERModule"]),
  ])
