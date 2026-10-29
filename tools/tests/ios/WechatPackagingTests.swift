import Flutter
import ObjectiveC
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testSceneUniversalLinkReturnsSdkHandledResult() throws {
    // FlutterSceneLifeCycleDelegate requires BOOL, unlike UISceneDelegate's
    // void callback. Flutter uses this result to stop routing a handled link.
    let pluginClass = try XCTUnwrap(NSClassFromString("FluwxPlugin") as? NSObject.Type)
    let callback = NSSelectorFromString("scene:continueUserActivity:")
    let callbackMethod = try XCTUnwrap(class_getInstanceMethod(pluginClass, callback))
    let returnType = try XCTUnwrap(method_copyReturnType(callbackMethod))
    defer { free(returnType) }
    let encoding = String(cString: returnType)
    XCTAssertTrue(["B", "c"].contains(encoding), "Flutter requires BOOL, found \(encoding)")
    guard ["B", "c"].contains(encoding) else { return }

    try withSDKDouble { plugin, sdk in
      plugin.setValue(true, forKey: "isRunning")
      let activity = webActivity()
      XCTAssertFalse(try invokeScene(plugin, activity))
      sdk.handled = true
      XCTAssertTrue(try invokeScene(plugin, activity))
      XCTAssertEqual(sdk.activities.count, 2)
      XCTAssertTrue(sdk.activities.allSatisfy { $0 === activity })
      XCTAssertTrue(sdk.delegates.allSatisfy { $0 === plugin })
    }
  }

  func testColdSceneForwardsUniversalLinksAndLeavesOtherActivitiesUnhandled() throws {
    try withSDKDouble { plugin, sdk in
      plugin.setValue(true, forKey: "isRunning")
      let activity = webActivity()
      let options = SceneOptionsDouble(activities: [activity])
      XCTAssertFalse(try invokeConnection(plugin, options))
      sdk.handled = true
      XCTAssertTrue(try invokeConnection(plugin, options))
      XCTAssertEqual(sdk.activities.count, 2)
      XCTAssertTrue(sdk.activities.allSatisfy { $0 === activity })
      XCTAssertTrue(sdk.delegates.allSatisfy { $0 === plugin })
      XCTAssertFalse(try invokeConnection(plugin, nil))
      XCTAssertFalse(try invokeConnection(plugin, SceneOptionsDouble(activities: [])))
      XCTAssertFalse(try invokeConnection(plugin, SceneOptionsDouble(activities: [NSUserActivity(activityType: "other.activity")])))
      XCTAssertEqual(sdk.activities.count, 2)
      let url = try XCTUnwrap(URL(string: "wx-test://callback"))
      XCTAssertTrue(try invokeConnection(plugin, SceneOptionsDouble(activities: [activity], urls: [url])))
      XCTAssertEqual(sdk.activities.count, 3)
      XCTAssertEqual(sdk.urls, [url])
    }
  }

  func testColdSceneLinkWaitsForSuccessfulRegistrationAndReplaysOnlyOnce() throws {
    try withSDKDouble { plugin, sdk in
      let activity = webActivity()
      // Returning NO before registration keeps normal host/other-plugin routing.
      XCTAssertFalse(try invokeConnection(plugin, SceneOptionsDouble(activities: [activity])))
      XCTAssertTrue(sdk.activities.isEmpty)
      sdk.registrationAllowed = false
      XCTAssertFalse(try register(plugin))
      XCTAssertTrue(sdk.activities.isEmpty)
      sdk.registrationAllowed = true
      XCTAssertTrue(try register(plugin))
      XCTAssertEqual(sdk.activities.count, 1)
      XCTAssertTrue(sdk.activities.first === activity)
      XCTAssertTrue(sdk.delegates.first === plugin)
      XCTAssertTrue(try register(plugin))
      XCTAssertEqual(sdk.activities.count, 1)
    }
  }

  private func webActivity() -> NSUserActivity {
    let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    activity.webpageURL = URL(string: "https://example.invalid/wechat/")
    return activity
  }

  private func invokeScene(_ plugin: NSObject, _ activity: NSUserActivity) throws -> Bool {
    let selector = NSSelectorFromString("scene:continueUserActivity:")
    let method = try XCTUnwrap(class_getInstanceMethod(type(of: plugin), selector))
    typealias Callback = @convention(c) (AnyObject, Selector, AnyObject?, NSUserActivity) -> Bool
    // The callback does not access scene; nil avoids constructing a UIKit scene.
    return unsafeBitCast(method_getImplementation(method), to: Callback.self)(plugin, selector, nil, activity)
  }

  private func invokeConnection(_ plugin: NSObject, _ options: SceneOptionsDouble?) throws -> Bool {
    let selector = NSSelectorFromString("scene:willConnectToSession:options:")
    let method = try XCTUnwrap(class_getInstanceMethod(type(of: plugin), selector))
    typealias Callback = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> Bool
    return unsafeBitCast(method_getImplementation(method), to: Callback.self)(plugin, selector, nil, nil, options)
  }

  private func register(_ plugin: NSObject) throws -> Bool {
    let handler = try XCTUnwrap(plugin as? FlutterPlugin)
    var response: Any?
    handler.handle?(FlutterMethodCall(methodName: "registerApp", arguments: [
      "appId": "wx-test", "iOS": true, "universalLink": "https://example.invalid/wechat/"
    ]), result: { response = $0 })
    return try XCTUnwrap(response as? Bool)
  }

  private func withSDKDouble(_ body: (NSObject, LinkSDKDouble) throws -> Void) throws {
    let sdkClass = try XCTUnwrap(NSClassFromString("WXApi"))
    let pluginClass = try XCTUnwrap(NSClassFromString("FluwxPlugin") as? NSObject.Type)
    let sdk = LinkSDKDouble()
    let linkMethod = try XCTUnwrap(class_getClassMethod(sdkClass, NSSelectorFromString("handleOpenUniversalLink:delegate:")))
    let linkBlock: @convention(block) (AnyObject, NSUserActivity, AnyObject) -> Bool = { _, activity, delegate in
      sdk.activities.append(activity)
      sdk.delegates.append(delegate)
      return sdk.handled
    }
    let linkIMP = imp_implementationWithBlock(linkBlock)
    let originalLink = method_setImplementation(linkMethod, linkIMP)
    defer {
      method_setImplementation(linkMethod, originalLink)
      imp_removeBlock(linkIMP)
    }
    let registerMethod = try XCTUnwrap(class_getClassMethod(sdkClass, NSSelectorFromString("registerApp:universalLink:")))
    let registerBlock: @convention(block) (AnyObject, NSString, NSString) -> Bool = { _, _, _ in sdk.registrationAllowed }
    let registerIMP = imp_implementationWithBlock(registerBlock)
    let originalRegister = method_setImplementation(registerMethod, registerIMP)
    defer {
      method_setImplementation(registerMethod, originalRegister)
      imp_removeBlock(registerIMP)
    }
    let urlMethod = try XCTUnwrap(class_getClassMethod(sdkClass, NSSelectorFromString("handleOpenURL:delegate:")))
    let urlBlock: @convention(block) (AnyObject, NSURL, AnyObject) -> Bool = { _, url, _ in
      sdk.urls.append(url as URL)
      return sdk.handled
    }
    let urlIMP = imp_implementationWithBlock(urlBlock)
    let originalURL = method_setImplementation(urlMethod, urlIMP)
    defer {
      method_setImplementation(urlMethod, originalURL)
      imp_removeBlock(urlIMP)
    }
    try body(pluginClass.init(), sdk)
  }

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

private final class LinkSDKDouble {
  var handled = false
  var registrationAllowed = true
  var activities: [NSUserActivity] = []
  var delegates: [AnyObject] = []
  var urls: [URL] = []
}

private final class SceneOptionsDouble: NSObject {
  @objc let URLContexts: NSSet
  @objc let userActivities: NSSet
  init(activities: [NSUserActivity], urls: [URL] = []) {
    URLContexts = NSSet(array: urls.map { URLContextDouble(url: $0) })
    userActivities = NSSet(array: activities)
    super.init()
  }
}

private final class URLContextDouble: NSObject {
  @objc let URL: NSURL
  init(url: Foundation.URL) {
    URL = url as NSURL
    super.init()
  }
}
