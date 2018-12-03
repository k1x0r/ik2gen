// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "ik2gen",
    products: [
        .executable(
            name: "ik2gen",
            targets: ["ik2gen"]
        )
    ],
    dependencies: [
        .package(url: "https://git.lan/k2utils.git", from: "0.0.0"),
        .package(url: "https://git.lan/xcodeedit.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ik2gen", dependencies: ["k2Utils", "XcodeEdit"]),
    ]
)

