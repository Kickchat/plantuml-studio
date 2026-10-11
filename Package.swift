// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PlantUMLStudio", platforms: [.macOS(.v14)],
  products: [.executable(name: "PlantUMLStudio", targets: ["PlantUMLStudio"])],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
  targets: [
    .target(name: "StudioDesign"),
    .target(name: "PlantUMLCore"), .target(name: "Rendering"),
    .target(name: "SequenceModule", dependencies: ["PlantUMLCore"]),
    .target(name: "ERModule", dependencies: ["PlantUMLCore"]),
    .target(name: "ComponentModule", dependencies: ["PlantUMLCore"]),
    .executableTarget(
      name: "PlantUMLStudio",
      dependencies: [
        "PlantUMLCore", "Rendering", "SequenceModule", "ERModule", "ComponentModule",
        "StudioDesign",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]),
    .executableTarget(name: "StudioBenchmark", dependencies: ["PlantUMLCore", "Rendering"]),
    .testTarget(
      name: "PlantUMLCoreTests",
      dependencies: [
        "PlantUMLCore", "Rendering", "SequenceModule", "ERModule", "ComponentModule",
        "StudioDesign",
      ]),
  ])
