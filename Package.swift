// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Scyther",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Scyther",
            targets: ["Scyther"]),
        .library(
            name: "ScytherSwiftUI",
            targets: ["ScytherSwiftUI"]),
        .library(
            name: "ScytherUI",
            targets: ["ScytherUI"]),
        .library(
            name: "ScytherExtensions",
            targets: ["ScytherExtensions"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Scyther",
            dependencies: [
                .target(name: "ScytherExtensions"),
                .target(name: "ScytherUI")
            ],
            path: "Sources/Scyther",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "ScytherExtensions",
            path: "Sources/ScytherExtensions"
        ),
        .target(
            name: "ScytherSwiftUI",
            dependencies: [
                .target(name: "Scyther")
            ],
            path: "Sources/ScytherSwiftUI"
        ),
        .target(
            name: "ScytherUI",
            path: "Sources/ScytherUI"
        ),
        .testTarget(
            name: "ScytherTests",
            dependencies: ["Scyther"]),
    ],
    swiftLanguageVersions: [.v5]
)
