<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/NeatPaste/AGENTS.md -->
# NeatPaste

通用工程规范：[Swift 规范](../_standards/swift.md)

NeatPaste 是 macOS 菜单栏剪贴板历史工具：复制后可唤出面板，按时间从新到旧挑选并粘贴回刚才正在输入的地方。

## 组件一览

| 目录 | 说明 | 状态 |
|---|---|---|
| `app-macos/` | macOS 客户端（独立 git 仓库） | 第一波骨架 |

Remote 尚未建立；发版与 Forgejo/GitHub 由后续流程处理，本产品文件夹不是 git 仓库。

## 明确不做

钉住、收藏、云同步、AI 整理、跨平台客户端、Mac App Store 版、把富文本/图片降成纯文本。第一波也不做自动更新安装包渠道（无 Sparkle、无公证 dmg）。

## 钉死的体验

打开面板默认选中最新一条；回车粘贴；历史只保留 7 天；探测间隔 0.5 秒；面板出现在输入光标附近；文本和图片同一行高；不把内容格式降级。权威说明见产品契约。

## 基线豁免（第一波）

- 不适用「自行分发必须带应用内自更新 / 正式发行必须带已签名 dmg」：第一波只做到本机可编译、可装进「应用程序」、可用快捷键唤出；对外发行渠道未开。
- 不适用隐私清单：不收集、不上报用户数据。
- 应用图标第一波按产品要求使用实色位图；分层图标留到下次改图标时迁移。

## 文档导航

- [app-macos/AGENTS.md](app-macos/AGENTS.md)：改、评审或排查 macOS 客户端工程、面板、热键、菜单栏或覆盖安装前**必读**。不读会把面板做成抢焦点、用错菜单栏实现，或覆盖安装把签名装坏。
- [app-macos/docs/PRODUCT_CONTRACT.md](app-macos/docs/PRODUCT_CONTRACT.md)：改、评审或排查任何用户可见行为、历史保留、粘贴、面板位置与「明确不做」的范围前**必读**。不读会把已钉死的体验改掉，或把后续不做的能力做进去。
- [../_standards/swift.md](../_standards/swift.md)：新建、评审或改造本 macOS 应用前**必读**。不读会偏离开源 Mac 应用的签名、本地化、无蓝框和覆盖安装闭环。
- [../_standards/workspace-docs/swift-docs/macos-app-baseline.md](../_standards/workspace-docs/swift-docs/macos-app-baseline.md)：评审本应用完整度、补分发/开机自启/快捷键/设置窗前**必读**。不读会漏掉菜单栏应用必做项，或把第一波已登记的豁免当成可以永久不做。
- [../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md](../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md)：改菜单栏生命周期、悬浮面板、退出拦截或开机自启前**必读**。不读会在新系统上被自动退出，或退出按钮没反应。
- [../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改面板玻璃、透明度或列表底色前**必读**。不读会把列表做成整窗透明，字看不清。
- [../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增设置项或改设置窗口打开方式前**必读**。不读会出现设置打不开、键名散落或默认值不一致。
- [../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：改粘贴所需的辅助功能授权、引导或降级态前**必读**。不读会在用户拒绝后反复弹窗，或拒绝后整段粘贴不可用。
- [../_standards/workspace-docs/swift-docs/apple-localization.md](../_standards/workspace-docs/swift-docs/apple-localization.md)：改用户可见文案或补语言前**必读**。不读会把键名显示给用户，或只改一种语言。
- [../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md](../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)：更换应用图标或菜单栏图标前**必读**。不读会弄丢模板图、透明像素规则或图标存放约定。

<!-- managed:inherited-agents:end -->

# AGENTS.md

通用工程规范：[Swift 规范](../../_standards/swift.md)

本仓库是 NeatPaste 的 macOS 客户端。产品级约定见上级 [../AGENTS.md](../AGENTS.md)。

## 工程源

- [`project.yml`](project.yml) 是 Xcode 工程的唯一来源。不要手改 `NeatPaste.xcodeproj`。
- 增删源文件或改构建设置后必须先 `xcodegen generate` 再构建。

## 钉死的实现约束

- **面板禁止激活本应用。** 打开历史面板时不得把本应用切到前台，否则回车粘贴会贴到自己身上。用非激活浮层、`orderFrontRegardless()` + `makeKey()`，不要走会抢焦点的激活。
- **禁止把 SwiftUI 菜单栏额外场景当成真正的菜单栏。** 真正工作的是状态栏按钮 + 自定义浮层；入口里那个永远隐藏的空菜单栏场景只为了满足框架协议。
- **禁止 SwiftData / Core Data。** 历史存储由后续实现接入，第一波只用内存假数据；接口已经写在 `HistoryServing`。
- 用户退出必须走 `AppDelegate.shared.requestTermination()`。禁止把系统代理强转成 `AppDelegate`。
- 设置项的存储键只允许出现在 `AppPreferences`，禁止在业务代码里写散落字符串键。
- 单测 target 必须把默认 actor 隔离设成 `nonisolated`（见 `project.yml` 的测试 target）。模块默认 MainActor 会让 XCTestCase 的初始化/setUp 编不过。

## 常用命令

```bash
xcodegen generate
```

```bash
xcodebuild -project NeatPaste.xcodeproj -scheme NeatPaste -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```

```bash
xcodebuild -project NeatPaste.xcodeproj -scheme NeatPaste -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

覆盖安装必须先删旧包再整包复制，不能往已存在的应用里合并：

```bash
pkill -x NeatPaste || true
xcodebuild -project NeatPaste.xcodeproj -scheme NeatPaste -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
rm -rf /Applications/NeatPaste.app
ditto build/DerivedData/Build/Products/Release/NeatPaste.app /Applications/NeatPaste.app
xattr -dr com.apple.quarantine /Applications/NeatPaste.app 2>/dev/null || true
open /Applications/NeatPaste.app
```

启动只认「应用程序」里的这一份；`open` 失败重试 2 次。

## 文档导航

- [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md)：改、评审或排查面板、粘贴、历史保留、快捷键默认值或「明确不做」范围前**必读**。不读会把已钉死的体验改掉。
- [../../_standards/swift.md](../../_standards/swift.md)：改本仓库代码、工程或验证方式前**必读**。不读会偏离 Swift 6 并发基线和覆盖安装闭环。
- [../../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md](../../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md)：改菜单栏生命周期、浮层或退出拦截前**必读**。不读会在新系统上被自动退出。
- [../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改面板材质前**必读**。不读会让列表文字落在不干净的底上。
- [../../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增设置项前**必读**。不读会把键名写散，或设置窗口打不开。
- [../../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：改粘贴授权引导前**必读**。不读会在拒绝后失去「仍可写入系统剪贴板」这条降级路径。
- [../../_standards/workspace-docs/swift-docs/apple-localization.md](../../_standards/workspace-docs/swift-docs/apple-localization.md)：改用户可见文案前**必读**。不读会把键名显示出来。
