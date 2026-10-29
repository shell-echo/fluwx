// swift-tools-version: 5.9
import PackageDescription


let package = Package(
    name: "fluwx",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "fluwx", targets: ["fluwx"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .binaryTarget(name: "WechatOpenSDK", path: "Frameworks/WechatSDK/WechatOpenSDK.xcframework"),
        .target(name: "WechatOpenSDKPrivacy", path: "Frameworks/WechatSDK/Privacy", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(
            name: "fluwx",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "WechatOpenSDK",
                "WechatOpenSDKPrivacy"
            ],
            resources: [
                .process("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .define("FLUWX_WITH_PAY"),
                .headerSearchPath("include")
            ],
            swiftSettings: [
                .define("FLUWX_WITH_PAY")
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit"),
                .unsafeFlags(["-ObjC", "-all_load"])
            ]
        )
    ]
)
