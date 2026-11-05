// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DICOMSwiftJ2KIntegration",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "DICOMSwiftJ2KIntegration",
            targets: ["DICOMSwiftJ2KIntegration"]
        ),
        .executable(
            name: "dicom-swiftj2k",
            targets: ["dicom-swiftj2k"]
        )
    ],
    dependencies: [
        .package(name: "DICOMKit", path: "../.."),
        .package(
            url: "https://github.com/raster-labs/SwiftJ2K.git",
            revision: "c95ac7b3cbb6d76039d16390497e68a1d8a07bfc"
        )
    ],
    targets: [
        .target(
            name: "DICOMSwiftJ2KIntegration",
            dependencies: [
                .product(name: "DICOMCore", package: "DICOMKit"),
                .product(name: "DICOMKit", package: "DICOMKit"),
                .product(name: "SwiftJ2K", package: "SwiftJ2K")
            ]
        ),
        .executableTarget(
            name: "dicom-swiftj2k",
            dependencies: [
                "DICOMSwiftJ2KIntegration",
                .product(name: "DICOMCore", package: "DICOMKit"),
                .product(name: "DICOMKit", package: "DICOMKit"),
                .product(name: "SwiftJ2K", package: "SwiftJ2K")
            ]
        ),
        .testTarget(
            name: "DICOMSwiftJ2KIntegrationTests",
            dependencies: [
                "DICOMSwiftJ2KIntegration",
                .product(name: "DICOMCore", package: "DICOMKit"),
                .product(name: "DICOMKit", package: "DICOMKit"),
                .product(name: "SwiftJ2K", package: "SwiftJ2K"),
                .target(name: "dicom-swiftj2k", condition: .when(platforms: [.macOS]))
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
