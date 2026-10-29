# Fluwx

本分支的 iOS SwiftPM 静态 SDK 分发、dSYM 修复和固定 Git 提交接入方式见 [接入与 SDK 更新说明](./doc/iOS_STATIC_SDK.md)。

[![pub package](https://img.shields.io/pub/v/fluwx.svg)](https://pub.dartlang.org/packages/fluwx)
![Build status](https://github.com/OpenFlutter/fluwx/actions/workflows/build_test.yml/badge.svg)
[![GitHub stars](https://img.shields.io/github/stars/OpenFlutter/fluwx)](https://github.com/OpenFlutter/fluwx/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/OpenFlutter/fluwx)](https://github.com/OpenFlutter/fluwx/network)
[![GitHub license](https://img.shields.io/github/license/OpenFlutter/fluwx)](https://github.com/OpenFlutter/fluwx/blob/main/LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/OpenFlutter/fluwx)](https://github.com/OpenFlutter/fluwx/issues)
<a target="_blank" href="https://qm.qq.com/q/TJ29rkzywM"><img border="0" src="https://pub.idqqimg.com/wpa/images/group.png" alt="OpenFlutter" title="OpenFlutter"></a>

---

![logo](https://gitee.com/OpenFlutter/resoures-repository/raw/master/fluwx/fluwx_logo.png)

## 什么是Fluwx

`Fluwx` 是一个[微信SDK](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Resource_Center_Homepage.html)插件，它允许开发者调用
[微信原生SDK](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Resource_Center_Homepage.html).

> 加入我们的QQ群: 1003811176

![QQGroup](https://gitee.com/OpenFlutter/resoures-repository/raw/master/common/flutter.png)

## 能力

- 分享图片，文本，音乐，视频等。支持分享到会话，朋友圈以及收藏.
- 微信支付.
- 在微信登录时，获取Auth Code.
- 拉起小程序.
- 订阅消息.
- 打开微信.
- 从微信标签打开应用
- APP拉起客服微信

## 开发环境搭建

请阅读[DEVELOPMENT_CN.md](./doc/DEVELOPMENT_CN.md) 以了解开发环境搭建。

## 准备

[现在迁移到V6](./doc/MIGRATE_TO_V6.md)

> 注意：V6有很多破坏性更新，尤其是iOS方面，如支持scene_delegate和Swift Package Manager。请在迁移到V6之前仔细阅读文档。

`Fluwx` 可以做很多工作但不是所有. 在集成之前，最好读一下[官方文档](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Resource_Center_Homepage.html).  
 然后你才知道怎么生成签名，怎么使用universal link以及怎么添加URL schema等.

## 安装

在`pubspec.yaml` 文件中添加 `fluwx` 依赖（默认带支付功能）:

```yaml
dependencies:
  fluwx: ^${latestVersion}
```

![pub package](https://img.shields.io/pub/v/fluwx.svg)

> [!WARNING]
> 别忘记替换 ^${latestVersion} ！为 `fluwx` 的发布版本！<br />
> （参考上面的版本号，或pub.dev 上的 [versions](https://pub-web.flutter-io.cn/packages/fluwx/versions)）

> [!WARNING]
> 对于不需要支付功能的版本，你可以切换到`fluwx_no_pay`包，这是一个独立的包，没有支付功能。

## 配置

`Fluwx` 从v4开始可以在`pubspec.yaml`的`fluwx`进行一些配置。具体可以参考[pubspec.yaml](./example/pubspec.yaml#L10)。

- app_id。这并不会替你初始化微信SDK，所以你还是自己调用`fluwx.registerApi`。
- debug_logging. 可选. 把它设置成`true`可以开启日志。目前在iOS上没有效果。
- flutter_activity. 可选. 这个通常是用于Android的冷启动。如果不设置任何值，`Fluwx`将尝试启动launcher activity.

- 在 OpenHarmony 上，要检查微信是否已安装，请在项目的 module.json5 中添加以下内容

```json5
{
  "module": {
    "querySchemes": [
      "weixin"
    ],
  }
}
```

> HarmonyOS 调试须知：不要使用 IDE 的自动签名，务必手动申请调试证书进行签名并调试

## 注册 WxAPI

通过 `fluwx` 注册WxApi.

```dart
Fluwx fluwx = Fluwx();
fluwx.registerApi(appId: "wxd930ea5d5a228f5f",universalLink: "https://your.univerallink.com/link/");
```

参数 `universalLink` 只在iOS上有用. 查看[文档](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html) 以便了解如何生成通用链接.  
 你也可以学习到怎么在iOS工程中添加URL schema，怎么添加`LSApplicationQueriesSchemes`。这很重要。

对于Android, 可以查看[本文](https://developers.weixin.qq.com/doc/oplatform/Downloads/Android_Resource.html)以便了解怎么获取app签名.
然后你需要知道release和debug时，app签名有什么区别。如果签名不对，你会得一个错误 `errCode = -1`.

建议越早注册越好。

## 能力文档

- [基础知识](./doc/BASIC_KNOWLEDGE_CN.md)
- [分享](./doc/SHARE_CN.md)
- [支付](./doc/PAYMENT_CN.md)
- [登录](./doc/AUTH_CN.md)
- [从微信标签打开应用](./doc/LAUNCH_APP_FROM_H5_CN.md)
- [APP拉起客服微信](/doc/Customer_Service_CN.md)
对于更多功能，可以查看源码。

## QA

[这些问题可能对你有帮助](./doc/QA_CN.md)

## 捐助

开源不易，请作者喝杯咖啡。

<img src="https://gitee.com/OpenFlutter/resoures-repository/raw/master/common/wx.jpeg" height="300">  <img src="https://gitee.com/OpenFlutter/resoures-repository/raw/master/common/ali.jpeg" height="300">

## 关注公众号

![subscribe](https://gitee.com/OpenFlutter/resoures-repository/raw/master/fluwx/wx_subscription.png)

## 关注趋势

![stars](https://starchart.cc/OpenFlutter/fluwx.svg)

## LICENSE

    Copyright 2018 OpenFlutter Project

    Licensed to the Apache Software Foundation (ASF) under one or more contributor
    license agreements.  See the NOTICE file distributed with this work for
    additional information regarding copyright ownership.  The ASF licenses this
    file to you under the Apache License, Version 2.0 (the "License"); you may not
    use this file except in compliance with the License.  You may obtain a copy of
    the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
    License for the specific language governing permissions and limitations under
    the License.
