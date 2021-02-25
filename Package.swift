// swift-tools-version:5.2

import PackageDescription
import Darwin.C

var buildK2Proj = getenv("K2PROJ") != nil
print("Building k2proj: \(buildK2Proj)")

let package = Package(
    name: "ik2gen",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        buildK2Proj ? nil : .executable(
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

    ].compactMap { $0 },
    dependencies: [
        .package(name: "k2Utils", url: "https://github.com/k1x0r/k2utils.git", .branch("master")),
        .package(name: "XcodeEdit", url: "https://github.com/k1x0r/XcodeEdit.git", .branch("master")),
    ],
    targets: [
        buildK2Proj ? nil : .target(name: "ik2gen", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ik2proj", dependencies: ["k2Utils", "XcodeEdit", "DependencyRequirements"]),
        .target(name: "ProjectTemplate", dependencies: ["DependencyRequirements"]),
        .target(name: "DependencyRequirements", dependencies: ["XcodeEdit"]),
    ].compactMap { $0 }
)

