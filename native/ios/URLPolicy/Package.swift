// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevelopmentURLPolicy",
    products: [.library(name: "DevelopmentURLPolicy", targets: ["DevelopmentURLPolicy"])],
    targets: [
        .target(name: "DevelopmentURLPolicy"),
        .testTarget(name: "DevelopmentURLPolicyTests", dependencies: ["DevelopmentURLPolicy"])
    ]
)
