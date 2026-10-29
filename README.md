# ipadWechat

微信 iPad 登录模式适配与 iPhone 底部标签栏遮挡修复。这里保存的是本地编写的 Objective-C 插件源码（V5），不是微信完整源码或可独立运行的 App，也不是微信官方项目。

## 当前实现

- 将 `+[DeviceInfo isiPad]` 返回值设为 `YES`，保留平板登录路径。
- 将 `isSupportSplitView`、`canUseInAppSplitView` 返回值设为 `NO`，关闭平板分栏路径；不修改 `isiPadUniversal`。
- 修复从朋友圈返回后，空白系统 `UITabBar` 被移到微信 `MMTabBar` 上方，导致底部按钮被遮挡的问题。
- 仅在主标签控制器中，两栏可见、重叠且顺序错误时，将微信标签栏移到系统栏上方。不会隐藏任意一栏。
- 布局及页面出现时检查顺序；前台每 0.5 秒补充一次轻量检查，处理 UIKit 在转场结束后再次调整顺序的情况。
- 不修改账号资格校验。

## 验证记录

2026-10-29，在 iPhone 13 mini / iOS 26.3.1、微信 8.0.71 基础包上完成验证。本地安装构建号为 `8.0.71.36`，原有 `WeChatBundleVersion` 保持 `8.0.71.34`。

- 用户连续两次进入朋友圈并返回，再切换“聊天”和“我”，确认白条不再遮挡、按钮正常。
- 实机控件信息确认：系统空白栏位于微信标签栏下方，四个按钮中心的点击都命中微信标签栏内的按钮。
- 前一版已由用户确认，同一账号可同时登录 13 mini 和主手机；V5 未改变该登录适配，本轮没有再次单独确认主手机在线状态。
- 已完成编译、签名、安装及打包校验。仓库中的构建脚本另经本机编译验证。

未验证长时间在线、完整消息同步、锁屏通知、语音来电或支付；本插件没有增加后台推送能力。只验证了上述组合，其他微信或 iOS 版本可能不兼容。

## 构建

需要 macOS、完整 Xcode 和 iPhoneOS SDK。

```sh
./scripts/build.sh
```

产物为 `build/LocalPadMode.dylib`，不进入 Git。

此命令只编译插件，不下载微信、不注入、不签名，也不安装到设备。将其用于自行准备的兼容 App 时，插件需位于 `Frameworks/LocalPadMode.dylib`，主可执行文件需加载 `@executable_path/Frameworks/LocalPadMode.dylib`，随后使用自己的有效开发签名及匹配的描述文件重新签名。开发签名需要按其实际有效期续签。

## 本地配置与诊断

插件读取 App 沙盒内的 `Library/Preferences/LocalPadLayout.json`。配置示例见 `config/LocalPadLayout.example.json`。

- `repairEnabled` 默认 `true`，控制标签栏顺序修复，不改变登录适配。
- `diagnosticsEnabled` 默认 `false`。开启后，前台约每 3 秒将控件类名、位置、显示状态及点击命中写入 `Library/Caches/LocalPadDiagnostics/latest.json`，覆盖上一份记录；不记录聊天文字、联系人文字或截图。
- 实机验收结束后已关闭诊断。日常使用保持关闭即可。

## 文件范围

仓库只包含原创适配代码、构建脚本、配置示例和本文档。不包含微信二进制或 IPA、签名私钥、证书、描述文件、设备标识、聊天数据、截图或诊断原始记录。

微信本体及其商标属于各自权利人。本仓库不提供微信本体，也不包含可绕过加密或账号资格校验的实现。
