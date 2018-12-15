// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "ik2gen",
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
        .package(url: "https://git.lan/k2utils.git", from: "0.0.0"),
        .package(url: "https://git.lan/xcodeedit.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ik2gen", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ik2proj", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ProjectTemplate", dependencies: ["DependencyRequirements"]),
        .target(name: "DependencyRequirements", dependencies: ["XcodeEdit"]),

    ]
)

