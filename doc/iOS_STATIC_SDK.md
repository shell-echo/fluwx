# iOS 静态 SDK 分发与 dSYM

此分支基于 fluwx 6.0.6，使用腾讯官方带支付功能的 WeChat OpenSDK 2.0.8。修复包括 `packages/fluwx` 的 SwiftPM 分发方式，以及共享 iOS 源码中 Scene Universal Link 的返回值、冷启动转发和注册前缓存。Dart API 和 Android 配置沿用上游；`fluwx_no_pay` 和 CocoaPods 的分发方式未修改。

## 本地修复登记

| 项目 | 记录 |
|---|---|
| 首次修复日期 | 2026-10-29 |
| 上游仓库与基线 | [OpenFlutter/fluwx](https://github.com/OpenFlutter/fluwx)，`v6.0.6` / `aa89699635f24947f036b9139336beaedb7a8271` |
| 本地维护分支 | [shell-echo/fluwx → fix/ios-static-sdk-packaging](https://github.com/shell-echo/fluwx/tree/fix/ios-static-sdk-packaging) |
| 原始修复提交 | [`03eea944856e297781206ebf0f2c5866917ee341`](https://github.com/shell-echo/fluwx/commit/03eea944856e297781206ebf0f2c5866917ee341) |
| 腾讯 SDK | 带支付功能的 OpenSDK 2.0.8；设备 arm64，模拟器 arm64 / x86_64 |
| 原始下载包 | [OpenSDK2.0.8.zip](https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK2.0.8.zip) |
| ZIP SHA-256 | `fba98084417ddf43a6926b8fa499a5eb0d2763933d3e62864a65e1713f36a2d4` |

首次已完成：6 项导入测试、3 项宿主 XCTest、固定 Git SHA 拉取、完整仓库源码/软链接一致性核对、未签名 Release 设备归档及独立复核。正式签名 IPA、App Store Connect 上传和真机微信交互尚未验证。后续升级应在文末继续追加更新记录，保留首次修复基线，方便辨认上游变化与本地补丁。

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

## 差异清单与维护要点

| 路径（相对仓库根目录） | 本地改动 | 跟随上游时检查 |
|---|---|---|
| `packages/fluwx/ios/fluwx/Package.swift` | 将远程 `WechatOpenSDK-SPM` 产品依赖替换为本地静态库 binary target，并依赖 `WechatOpenSDKPrivacy` 资源 target | 保持 Flutter 生成的包仍能消费；按新上游整合 target、编译和链接设置，避免恢复旧 framework 分发 |
| `packages/_shared/ios/Sources/FluwxPlugin.m` | Scene Universal Link 返回 `BOOL`；处理冷启动 `userActivities`，注册前缓存并在成功注册后重放一次 | 区分 Flutter 插件与 UIKit 的返回类型，覆盖冷启动、注册失败/重试及非微信链接继续路由；上游修复后检查是否能移除本地处理 |
| `packages/fluwx/ios/fluwx/Frameworks/WechatSDK/WechatOpenSDK.xcframework/` | 原厂 archive 改为 `libWechatOpenSDK.a`，添加 `HeadersPath` 和普通 Clang module map；头文件保留 `WechatOpenSDK/` 命名空间 | 公开导入路径、全部平台/架构与原厂字节保持正确；该目录通过导入器生成 |
| `packages/fluwx/ios/fluwx/Frameworks/WechatSDK/Privacy/` | 用独立 SwiftPM 资源 target 分发原厂隐私清单 | 保留原件、target 依赖和最终 App 中的资源 bundle；隐私内容变更时依据新原件调整测试预期 |
| `packages/fluwx/ios/fluwx/Frameworks/WechatSDK/provenance.json`、`README.vendor.txt` | 记录版本、输入文件哈希和原厂发布说明 | 与本次导入一起更新；不要只替换 `.a` 而保留旧记录 |
| `tools/import_wechat_sdk.py` | 检查静态 archive、架构、头文件集合和资源，暂存后整体替换，失败回滚 | SDK 新结构需要先审查再修改检查条件，不能跳过检查直接更新 |
| `tools/tests/test_wechat_sdk.py`、`tools/tests/ios/WechatPackagingTests.swift` | 导入/回滚测试、宿主打包和 Scene 回跳路由测试 | SDK 或相关回调更新后执行；宿主测试夹具要复制到实际启用 SPM 的测试工程 |
| `.gitattributes` | 仅对导入的腾讯头文件关闭 Git 空白检查，保留原厂空白字节 | 范围保持在 vendor 头文件，其他源码继续检查 |
| `README.md`、`README_CN.md`、`CHANGELOG.md`、本文件 | 说明入口、修复记录、接入和维护步骤 | 升级时记录新版本、新上游基线、验收代码提交和剩余未验证项 |

首次打包修复没有修改原生业务源码；后续复查只调整共享 iOS 源码中上述 Scene Universal Link 路由和缓存。该共享源码也会被 no_pay 和 CocoaPods 使用，但它们的 SDK 分发和构建未在本次验证。Dart API、Android 配置、支付请求与响应接口、`FLUWX_WITH_PAY`、`-ObjC`、`-all_load` 设置均保持原样。未来上游调整这些设置时，应审查新版本的要求，避免机械地恢复旧值。保留 monorepo 原有软链接和 `packages/_shared`，这是 Git 子目录接入所依赖的仓库结构。

## 应用接入

宿主 `pubspec.yaml` 固定经过审核的完整 Git 提交。下面是首次已完成 Git 接入及归档验证的修复版本；后续升级时改为新的验收提交：

```yaml
dependencies:
  fluwx:
    git:
      url: https://github.com/shell-echo/fluwx.git
      ref: 03eea944856e297781206ebf0f2c5866917ee341
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

应用尽早创建并保留一个 `Fluwx` 实例，先安装所需的响应订阅者，再调用 `registerApi`，以接收成功注册时重放的冷启动事件。宿主路由也应能接受微信 Universal Link 的回调路径；注册前该路径会继续交给 Flutter 和其他插件。`registerApi` 成功只代表 SDK 注册成功，域名关联及真实回跳仍需真机验证。支付交易结果由服务端通知或主动查单确认。

## 跟随官方 fluwx 更新

1. 分开确认 **fluwx 版本**与**腾讯原生 SDK 版本**。先选定官方 fluwx tag / 完整 SHA，比较其 `Package.swift`、`packages/_shared/ios`、`packages/fluwx/pubspec.yaml` 及原生依赖变化；核对它是否仍通过旧 framework 形式分发微信 SDK。
2. 从当前修复分支建立候选更新分支，再整合选定的上游版本。保留本地补丁的必要行为，逐项处理差异清单中的冲突；不要用上游整个 `Package.swift` 直接覆盖，也不要在未检查打包方式前移除补丁。此步骤只针对候选更新，避免直接改动应用已固定引用的提交。
3. 若本次只更新 fluwx、腾讯 SDK 未变，先确认现有 SDK 与新插件公开 API、链接设置兼容；无需仅为重新生成同一 SDK 而再次导入。若腾讯 SDK 也更新，按下节从官方包重新导入，审查 SDK 发布说明、文件哈希、公开头文件、架构和隐私清单变化。
4. 对最终组合执行受影响检查：导入测试、宿主 XCTest、设备 Release 归档检查；真机验证登录/分享/支付等实际使用的能力。更改 Dart、Android 或其他平台代码时，另补对应平台的检查。最后让测试宿主从 fork 的完整 Git SHA 拉取并归档，确认包含 vendor 工件、隐私资源和完整 monorepo 软链接。
5. 追加本次更新记录并发布已验收的提交；应用修改 `ref` 和 `pubspec.lock`，重新生成 SPM 集成及新归档。记录实际通过、未执行和仍待验证的项目，避免将首次验收结果当成新 SDK 的验证结果。

### 上游何时可以替代本补丁

当上游已修复分发时，用不带本地补丁的候选版本在干净测试宿主验证：微信 API 可用、隐私清单完整、归档不再出现本次空 framework / 符号问题，并核对动态二进制与其 dSYM（如果存在）的 UUID。满足这些条件后，才移除已无必要的本地 adapter、vendor 工件、导入器和专用测试，再复核应用接入。

如果腾讯改为真正的动态库、增加签名要求或改变资源机制，当前静态库导入方案的前提已变化。应先评估新的官方集成方式并更新验收预期，不能强行将动态库按 `.a` 处理，也不能为了通过旧测试丢弃新资源。

## SDK 更新和核验

构建只使用仓库中已审查的 SDK，不在 CI 构建时临时下载。维护者从腾讯官网下载带支付功能的 XCFramework、解压后，在仓库根目录执行：

```sh
python3 tools/import_wechat_sdk.py /path/to/WechatOpenSDK.xcframework --version 2.0.8
python3 -m unittest discover -s tools/tests -p 'test_wechat_sdk.py' -v
```

导入器检查全部 slice 的架构及静态 archive 类型、公开头文件的文件名集合、隐私清单格式和额外资源，再替换整个 `Frameworks/WechatSDK` 目录；安装失败会恢复原目录。遇到新架构、头文件集合或资源时停止导入，需要先审查 SDK 的新要求。已有头文件内部的方法签名变化仍需通过人工审查、编译和运行验证；导入检查不能替代 API 兼容性验证。

`--version` 是维护者填写的版本记录，导入器不会联网核实来源或从二进制中验证版本。导入前核对官方下载包及发布说明；`provenance.json` 保存输入文件 SHA-256，便于比较版本和核对原始代码、头文件及隐私清单。

已有 `.wechat-sdk-import.lock` 会阻止重复导入。普通异常或 HUP/INT/TERM 会触发清理和安装回滚；SIGKILL、断电或回滚失败时，保留现场并检查 `Frameworks/.wechat-sdk-import-*` 下的 `previous` 和锁目录，恢复一致状态后再重试。

更新后创建新的 Release `.xcarchive`，检查以下内容：

- App 的 `Frameworks` 内没有 `WechatOpenSDK.framework`。
- 宿主没有 `@rpath/WechatOpenSDK.framework/WechatOpenSDK` 动态依赖。
- 宿主 dSYM 中仍有 `WXApi` / `FluwxPlugin` 的可用符号；不能因为没有单独 framework 而遗漏微信代码。
- `fluwx_WechatOpenSDKPrivacy.bundle/PrivacyInfo.xcprivacy` 与腾讯原件一致。
- 运行 `tools/tests/ios/WechatPackagingTests.swift` 中的宿主 XCTest，确认微信类来自宿主镜像、SDK 方法可执行、隐私清单可读。
- 确认 Flutter Scene Universal Link 回调返回 `BOOL`，SDK 返回未处理/已处理时分别转发 `NO`/`YES`，且用户活动与插件 delegate 原样传给 SDK。该测试替换 SDK 处理方法，不进行真实微信回跳。

上述 XCTest 用于启用本分支 SwiftPM 集成的 Flutter 宿主。可将它复制为测试工程的 `ios/RunnerTests/RunnerTests.swift`，再运行 Runner 的 XCTest Scheme；它不需要微信密钥，也不进行登录或支付。

本次验证环境为 Flutter 3.47.8、Xcode 27.1；实际微信登录、分享、支付仍需在完成开放平台配置后用真机验证。未签名诊断归档通过不等于已通过 App Store Connect 上传。

## 后续更新记录

每次升级追加一条记录，填写：日期、上游 fluwx tag / SHA、腾讯 SDK 版本与官方下载包哈希、本地保留或移除的补丁、新增兼容性处理、实际验收的代码 SHA、检查命令/结果和未验证项。首次修复信息保留在上方“本地修复登记”。

### 2026-10-29 联合接入复查

联合阿里云号码认证插件构建时，发现上游 `scene:continueUserActivity:` 使用 UIKit 的 `void` 签名，但插件实现的 `FlutterSceneLifeCycleDelegate` 要求 `BOOL`。Flutter 据此决定停止向其他插件和宿主转发事件；已注册时返回值必须与 `WXApi handleOpenUniversalLink:delegate:` 一致。

Scene 冷启动的 Universal Link 位于 `connectionOptions.userActivities`，上游仅处理 `URLContexts`，会遗漏该入口。现在分别转发两种输入；Dart 尚未完成微信注册时缓存 Universal Link，注册失败保留、注册成功后清空并重放一次。注册前无法判断是否为微信链接，因此返回 `NO` 让其他插件和宿主继续路由，宿主路由应能接受该回调路径。新增宿主回归测试覆盖返回类型、SDK `NO` / `YES`、参数转发、空/其他活动、两种链接同时存在、注册失败/重试与不重复重放。测试替换 SDK 方法，不证明真实微信支付或回跳已成功。SDK 二进制、头文件和支付接口未变，正式签名上传及真实微信回跳仍需业务接入后验收。
