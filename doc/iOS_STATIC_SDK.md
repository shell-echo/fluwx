# iOS 静态 SDK 分发与 dSYM

此分支基于 fluwx 6.0.6，使用腾讯官方带支付功能的 WeChat OpenSDK 2.0.8。改动限于 `packages/fluwx` 的 SwiftPM 分发方式；Dart API、原生业务代码和 Android 配置沿用上游。`fluwx_no_pay` 和 CocoaPods 分发未在本补丁中修改。

## 为什么这样修复

腾讯 2.0.8 的 `WechatOpenSDK.framework/WechatOpenSDK` 实际是静态 archive。原来的 SwiftPM 依赖将整个 framework 交给 Xcode，归档时 Xcode 会为它生成空的动态占位二进制。占位 framework 可能触发缺少 dSYM 或 `MinimumOSVersion` 不匹配；微信代码已经静态链接到宿主可执行文件。

本分支在导入 SDK 时将外壳改为标准静态库 XCFramework：

```text
WechatSDK/
  WechatOpenSDK.xcframework/
    ios-arm64/libWechatOpenSDK.a
    ios-arm64/Headers/WechatOpenSDK/*.h
    ios-arm64_x86_64-simulator/libWechatOpenSDK.a
    ios-arm64_x86_64-simulator/Headers/WechatOpenSDK/*.h
  Privacy/PrivacyInfo.xcprivacy
  Privacy/Privacy.swift
  provenance.json
  README.vendor.txt
```

设备端 arm64 和模拟器 arm64/x86_64 的代码及公开头文件保持腾讯原字节；仅调整 XCFramework 元数据和 Clang module map。独立资源 target 将腾讯原始隐私清单分发到 `fluwx_WechatOpenSDKPrivacy.bundle`。宿主不再嵌入 `WechatOpenSDK.framework`，也不需要它的独立 dSYM；可用的微信静态符号随宿主 dSYM 保存，不承诺腾讯未提供的源码行号。

相关上游记录：[fluwx #762](https://github.com/OpenFlutter/fluwx/issues/762)、[微信官方 SDK 下载](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Downloads/iOS_Resource.html)。上游 fluwx 6.0.6 仍引用原 framework 形式的 WechatOpenSDK-SPM 2.0.8，单纯升级该版本不能改变这一封装方式。

## 应用接入

修复分支发布到自己的 fork 后，宿主 `pubspec.yaml` 固定经过审核的完整 Git 提交；下例 URL 和 SHA 是占位符，需要替换：

```yaml
dependencies:
  fluwx:
    git:
      url: <your-fluwx-fork-url>
      ref: <reviewed-full-commit-sha>
      path: packages/fluwx

flutter:
  config:
    enable-swift-package-manager: true
```

提交宿主 `pubspec.lock`。本地验证可将 Git 来源改为 `path: ../fluwx/packages/fluwx`。保留 Git 仓库完整目录及已有 symlink：本仓库通过 `packages/_shared` 共享代码，不能只拷贝 `packages/fluwx` 一个目录。

```sh
flutter pub get
flutter build ios --config-only
open ios/Runner.xcworkspace
```

Xcode 使用宿主自己的 Team、签名和 Bundle ID。SwiftPM 自动完成静态链接及隐私资源复制，宿主无需添加针对该 SDK 的 framework 删除脚本、dSYM 生成脚本、MinimumOSVersion 修补或额外资源复制阶段。也不要重复手动添加微信 SDK。

微信能力本身仍需按[官方接入说明](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html)配置 App ID、URL Scheme、`LSApplicationQueriesSchemes` 和 Universal Link / Associated Domains，再调用 `fluwx.registerApi`。这部分属于宿主的微信配置，与本次 SDK 封装修复独立。

## SDK 更新和核验

构建只使用仓库中已审查的 SDK，不在 CI 构建时临时下载。维护者从腾讯官网下载带支付功能的 XCFramework、解压后，在仓库根目录执行：

```sh
python3 tools/import_wechat_sdk.py /path/to/WechatOpenSDK.xcframework --version 2.0.8
python3 -m unittest discover -s tools/tests -p 'test_wechat_sdk.py' -v
```

导入器检查全部 slice 的架构及静态 archive 类型、公开头文件、隐私清单和额外资源，再替换整个 `Frameworks/WechatSDK` 目录；安装失败会恢复原目录。遇到新架构、头文件或资源时停止导入，需要先审查 SDK 的新要求。`provenance.json` 保存源文件 SHA-256，便于核对原始代码和头文件。

已有 `.wechat-sdk-import.lock` 会阻止重复导入。普通异常或 HUP/INT/TERM 会触发清理和安装回滚；SIGKILL、断电或回滚失败时，保留现场并检查 `Frameworks/.wechat-sdk-import-*` 下的 `previous` 和锁目录，恢复一致状态后再重试。

更新后创建新的 Release `.xcarchive`，检查以下内容：

- App 的 `Frameworks` 内没有 `WechatOpenSDK.framework`。
- 宿主没有 `@rpath/WechatOpenSDK.framework/WechatOpenSDK` 动态依赖。
- 宿主 dSYM 中仍有 `WXApi` / `FluwxPlugin` 的可用符号；不能因为没有单独 framework 而遗漏微信代码。
- `fluwx_WechatOpenSDKPrivacy.bundle/PrivacyInfo.xcprivacy` 与腾讯原件一致。
- 运行 `tools/tests/ios/WechatPackagingTests.swift` 中的宿主 XCTest，确认微信类来自宿主镜像、SDK 方法可执行、隐私清单可读。

上述 XCTest 用于启用本分支 SwiftPM 集成的 Flutter 宿主。可将它复制为测试工程的 `ios/RunnerTests/RunnerTests.swift`，再运行 Runner 的 XCTest Scheme；它不需要微信密钥，也不进行登录或支付。

本次验证环境为 Flutter 3.47.8、Xcode 27.1；实际微信登录、分享、支付仍需在完成开放平台配置后用真机验证。未签名诊断归档通过不等于已通过 App Store Connect 上传。
