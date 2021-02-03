// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "ik2gen",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .executable(
            name: "ik2gen",
            targets: ["ik2gen"]
        ),
        .executable(
            name: "ik2proj",
            targets: ["ik2proj"]
        ),
        .library(
            name: "ProjectTemplate",
            targets: ["ProjectTemplate"]
        ),
        .library(
            name: "DependencyRequirements",
            targets: ["DependencyRequirements"]
        ),

    ],
    dependencies: [
        .package(name: "k2Utils", url: "https://github.com/k1x0r/k2utils.git", .branch("master")),
        .package(name: "XcodeEdit", url: "https://github.com/k1x0r/XcodeEdit.git", .branch("master")),
    ],
    targets: [
        .target(name: "ik2gen", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ik2proj", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ProjectTemplate", dependencies: ["DependencyRequirements"]),
        .target(name: "DependencyRequirements", dependencies: ["XcodeEdit"]),

    ]
)

