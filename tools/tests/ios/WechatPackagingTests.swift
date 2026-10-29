import Flutter
import ObjectiveC
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testWechatApiExecutesFromHostBinary() throws {
    let sdk = try XCTUnwrap(NSClassFromString("WXApi") as? NSObject.Type)
    let selector = NSSelectorFromString("getApiVersion")
    XCTAssertTrue(sdk.responds(to: selector))
    let version = try XCTUnwrap(sdk.perform(selector)?.takeUnretainedValue() as? String)
    XCTAssertFalse(version.isEmpty)
    let image = String(cString: try XCTUnwrap(class_getImageName(sdk)))
    XCTAssertTrue(image.hasSuffix("/Runner") || image.hasSuffix("/Runner.debug.dylib"), image)
  }

  func testWechatHasNoEmbeddedFramework() throws {
    let frameworks = try XCTUnwrap(Bundle.main.privateFrameworksURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("WechatOpenSDK.framework").path))
  }

  func testVendorPrivacyManifestIsBundled() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "fluwx_WechatOpenSDKPrivacy", withExtension: "bundle"))
    let manifest = url.appendingPathComponent("PrivacyInfo.xcprivacy")
    let data = try Data(contentsOf: manifest)
    let privacy = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let entries = try XCTUnwrap(privacy["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    XCTAssertTrue(entries.contains { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" && ($0["NSPrivacyAccessedAPITypeReasons"] as? [String])?.contains("CA92.1") == true })
  }
}
