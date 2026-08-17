<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/NeatPaste/AGENTS.md -->
# NeatPaste

通用工程规范：[Swift 规范](../_standards/swift.md)

NeatPaste 是 macOS 菜单栏剪贴板历史工具：复制后可唤出面板，按时间从新到旧挑选并粘贴回刚才正在输入的地方。

## 组件一览

| 目录 | 说明 | 状态 |
|---|---|---|
| `app-macos/` | macOS 客户端（独立 git 仓库） | 第一波骨架 |

Remote：`app-macos` -> GitHub `NeatMacApps/NeatPaste`（公开，https://github.com/NeatMacApps/NeatPaste ）；本产品文件夹不是 git 仓库。首次开源发布已完成；对外发行渠道（签名 dmg、Homebrew）待后续接入。

## 明确不做

钉住、收藏、云同步、AI 整理、跨平台客户端、Mac App Store 版、把富文本/图片降成纯文本。第一波也不做自动更新安装包渠道（无 Sparkle、无公证 dmg）。

## 钉死的体验

打开面板默认选中最新一条；回车粘贴；再点已选中的条目或双击同样粘贴；空格用系统 Quick Look 预览当前条；按住上下键连续移动选择（预览开着同样如此）；点面板外立刻关掉；图片出缩略图；相同内容只留一条、再复制则顶到最上；历史只保留 7 天且重启后仍在；探测间隔 0.5 秒；面板出现在输入光标附近；文本和图片同一行高；不把内容格式降级。权威说明见产品契约。

## 基线豁免（第一波）

合法暂缓（尚未对外发行，一旦发公开 Release 必须补齐）：

- 不适用「自行分发必须带应用内自更新 / 正式发行必须带已签名 dmg」：第一波只做到本机可编译、可装进「应用程序」、可用快捷键唤出；对外发行渠道未开。
- 不适用隐私清单：不收集、不上报用户数据。

**下列不是豁免，是第一波欠账，必须尽快补，不得写成「下次改图标再做」：**

- 分层应用图标（当前仍是扁平切图，系统会降成灰底）
- 面板外框通透玻璃（不要雾面块），搜索和列表同一块实底、搜索不要单独描边；预览走系统 Quick Look，不要做常驻预览栏，也不要加标题栏
- 启动瞬间与搜索框无系统蓝框，并补自有焦点态
- 窗口位置 / 尺寸记忆（设置窗；历史面板每次打开都重新锚到输入位置，不记忆）
- README 开源门面截图：面板图与设置窗图待拍后存入 `docs/images/` 并取消两份 README 里的注释区（用户自理，拍图前注意剪贴板内容脱敏）

## 文档导航

- [app-macos/AGENTS.md](app-macos/AGENTS.md)：改、评审或排查 macOS 客户端工程、面板、预览窗、热键、菜单栏、去重、光标锚点、收录探测或覆盖安装前**必读**。不读会把面板做成抢焦点、用错菜单栏实现，把预览限尺寸拿掉，漏收刚复制的内容，或覆盖安装把签名装坏。
- [app-macos/docs/PRODUCT_CONTRACT.md](app-macos/docs/PRODUCT_CONTRACT.md)：改、评审或排查任何用户可见行为、历史保留、粘贴、收录探测、预览、去重、面板位置与「明确不做」的范围前**必读**。不读会把已钉死的体验改掉，或把后续不做的能力做进去。
- [app-macos/docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md](app-macos/docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md)：改、评审或排查系统预览尺寸、换条闪动/变大、面板是否跟随输入位置、历史重复条目、点外面关不掉、重启后历史丢失、按住上下键只动一格、搜索框描边或窗口边缘玻璃前**必读**。不读会再拿掉限尺寸，把整页编辑器底边当成光标，让面板一直挡屏幕，把 7 天历史做成重启即丢，按住方向键只跳一条，给搜索单独加粗框，或把外框做成雾面块。
- [app-macos/docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md](app-macos/docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md)：改、评审或排查「复制了但列表没有」、收录探测、写回同时带文字和文件、或本机冒烟验收收录前**必读**。不读会把内容还没装上当成已经处理完，这条就永远进不了列表。
- [../_standards/swift.md](../_standards/swift.md)：新建、评审或改造本 macOS 应用前**必读**。不读会偏离开源 Mac 应用的签名、本地化、无蓝框和覆盖安装闭环。
- [../_standards/workspace-docs/swift-docs/macos-app-baseline.md](../_standards/workspace-docs/swift-docs/macos-app-baseline.md)：新建、脚手架、评审本应用完整度、补分发/开机自启/快捷键/设置窗前**必读**。不读会把「第一波能跑」当成完成，或把未对外发行的暂缓当成可以永久不做。
- [../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md](../_standards/workspace-docs/swift-docs/apple-app-icon-assets.md)：新做、更换、评审或排查应用图标或菜单栏图标前**必读**。不读会再补一套扁平切图，系统会把图标降成灰底。
- [../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md](../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md)：改菜单栏生命周期、悬浮面板、退出拦截、开机自启、系统剪贴板收录/写回或本机冒烟日志前**必读**。不读会在新系统上被自动退出，或漏收刚复制的内容。
- [../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改面板玻璃、透明度或列表底色前**必读**。不读会把列表做成整窗透明，字看不清。
- [../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增设置项或改设置窗口打开方式前**必读**。不读会出现设置打不开、键名散落或默认值不一致。
- [../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：改粘贴所需的辅助功能授权、引导或降级态前**必读**。不读会在用户拒绝后反复弹窗，或拒绝后整段粘贴不可用。
- [../_standards/workspace-docs/swift-docs/apple-localization.md](../_standards/workspace-docs/swift-docs/apple-localization.md)：改用户可见文案或补语言前**必读**。不读会把键名显示给用户，或只改一种语言。

<!-- managed:inherited-agents:end -->

# AGENTS.md

通用工程规范：[Swift 规范](../../_standards/swift.md)

本仓库是 NeatPaste 的 macOS 客户端。产品级约定见上级 [../AGENTS.md](../AGENTS.md)。

## 工程源

- [`project.yml`](project.yml) 是 Xcode 工程的唯一来源。不要手改 `NeatPaste.xcodeproj`。
- 增删源文件或改构建设置后必须先 `xcodegen generate` 再构建。

## 钉死的实现约束

- **面板禁止激活本应用。** 打开历史面板时不得把本应用切到前台，否则回车粘贴会贴到自己身上。用非激活浮层、`orderFrontRegardless()` + `makeKey()`，不要走会抢焦点的激活。
- **点未选中只改选中，再点已选中或双击才粘贴。** 不要做成「点一下就粘贴」。打开后面板已默认选中最新一条，点它就应粘贴。鼠标粘贴关掉面板后，双击收尾那一下会点穿到下面的窗口，必须先挡住再关。
- **上下键连发必须自己做。** 非激活浮层往往收不到系统按键连发；把按下吞掉后系统也可能不再连发。必须在按下时记下方向、按系统连发延迟/间隔自己连续移动，抬起、键已松开或关掉面板时停。系统连发事件若仍到达则丢掉，避免跳两格。不要为了连发把本应用切到前台。预览打开时按键走临时热键，热键只响一次、不会连发，必须从这条路径同样启动按住连走；不要为了连发把焦点抢回列表。热键、预览窗、列表可能同时收到第一次按下，已按住则不再走步。
- **历史面板尺寸固定。** 不要加可缩放；每次打开都用规定默认尺寸。列表可滚，不要显示滚动条。
- **点面板外必须立刻关掉。** 非激活浮层点回正在用的应用时往往不会失焦，不能靠「本应用失活 / 窗口失焦」来关，否则会一直挡屏幕；也不要用失活来关，否则一打开就会被关掉。必须在按下时看点击落点：面板、系统预览、菜单栏本图标内不关，其余立刻关。
- **历史面板无标题栏。** 预览用系统 Quick Look（空格开关），禁止做常驻预览栏，禁止改成自绘预览。打开必须让系统预览真正出画；不要为了收键把焦点抢回来，否则预览会空白。预览打开期间用临时热键收空格、Esc 和上下键，因为按键不会回到历史列表。预览必须是小窗。系统预览换内容时会自己撑大，最小/最大尺寸拦不住程序化改尺寸；必须在将要变大时直接拦回小窗，换一条后也要立刻压回。禁止为了防闪而放弃限尺寸。系统预览自己缩放时不要当成「用户在拖」而跳过压回。上下键可能同时走到热键/预览窗/列表，必须合成一次；热键不会连发，按住必须接到同一套按住连走，且不得把焦点抢回列表。踩坑与验收见 [docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md](docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md)。
- **外框通透玻璃，搜索和列表同一块实底。** 不要用雾面材质冒充玻璃。搜索框不要单独加描边或另一套底色；焦点用插入光标即可。列表仍是内容层实底，字必须在干净底上。
- **打开面板前先记下光标位置，再做异步刷新。** 面板成为焦点后辅助功能只能看到自己，再去问光标会锚错。大编辑器不能拿整框当光标。
- **相同内容去重。** 收入时按用户可见内容合并，旧的删掉、新的顶到最上。不要按会随每次复制变掉的网页/应用元数据当成新条目。
- **图片行必须出缩略图。** 固定小方图里画真实缩小图，禁止只放通用照片图标。系统临时文件名、内部编号不得当作列表标题；没有可读名称时显示「图片」。
- **禁止把 SwiftUI 菜单栏额外场景当成真正的菜单栏。** 真正工作的是状态栏按钮 + 自定义浮层；入口里那个永远隐藏的空菜单栏场景只为了满足框架协议。
- **历史必须落在本机、重启还在。** 7 天是给用户留的，不是「这次打开期间有效」。禁止 SwiftData / Core Data / GRDB；用本机用户资料目录里的文件保存完整条目（不降级）。生产路径禁止只放内存，也禁止塞假数据。接口写在 `HistoryServing`。
- **剪贴板变化必须可重试。** 先看到变化、内容还没装上时，不得把变化计数往前推；否则打开面板也读不到这一条。密码/瞬时/本应用写回才算处理完。条目字节为空时必须回退读整板。单测只用独立命名的剪贴板，禁止动系统剪贴板。踩坑与验收见 [docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md](docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md)。
- **含文件地址的写回必须一次写完。** 先写文本再写文件地址会把文本冲掉。
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

对外发版（签名公证 dmg + Sparkle 更新包 + GitHub Release + appcast，一条命令、可重复执行；`--local-only` 只产本地公证包不碰远端）：

```bash
scripts/publish-release.sh
```

首次安装渠道：GitHub Release 的公证 dmg 与 Homebrew（`x0c/tap` 的 `neatpaste` cask）；自动更新源为仓库根 `appcast.xml`（raw 地址）。版本号双写于 `Configuration/Base.xcconfig` 与 `project.yml`，发版脚本会比对一致性并拦截回退。

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

启动只认「应用程序」里的这一份；`open` 失败重试 2 次。核对装上的是这份：比较 `Contents/MacOS/NeatPaste` 哈希，不要看 `.app` 文件夹修改时间。收录冒烟：复制一条已知长度的唯一文本，等至少 0.5 秒，快捷键打开面板必须看到它。不要用 zsh 的 `log`（必须 `/usr/bin/log`），也不要搜应用打印的中文——系统日志会藏成私有。

## 文档导航

- [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md)：改、评审或排查面板、粘贴、历史保留、收录探测、预览、去重、面板位置、快捷键默认值或「明确不做」范围前**必读**。不读会把已钉死的体验改掉。
- [docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md](docs/troubleshooting/2026-08-15-history-panel-preview-and-anchor.md)：改、评审或排查系统预览尺寸、换条闪动/变大、面板是否跟随输入位置、历史重复条目、点外面关不掉、重启后历史丢失、按住上下键只动一格、搜索框描边或窗口边缘玻璃前**必读**。不读会再拿掉限尺寸，把整页编辑器底边当成光标，让面板一直挡屏幕，把 7 天历史做成重启即丢，按住方向键只跳一条，给搜索单独加粗框，或把外框做成雾面块。
- [docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md](docs/troubleshooting/2026-08-15-clipboard-ingest-retry.md)：改、评审或排查「复制了但列表没有」、收录探测、写回同时带文字和文件、或本机冒烟验收收录前**必读**。不读会把内容还没装上当成已经处理完，这条就永远进不了列表。
- [../../_standards/swift.md](../../_standards/swift.md)：改本仓库代码、工程或验证方式前**必读**。不读会偏离 Swift 6 并发基线和覆盖安装闭环。
- [../../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md](../../_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md)：改菜单栏生命周期、浮层、退出拦截、系统剪贴板收录/写回或本机冒烟日志前**必读**。不读会在新系统上被自动退出，或漏收刚复制的内容。
- [../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md](../../_standards/workspace-docs/swift-docs/liquid-glass-practices.md)：改面板材质前**必读**。不读会让列表文字落在不干净的底上。
- [../../_standards/workspace-docs/swift-docs/apple-app-preferences.md](../../_standards/workspace-docs/swift-docs/apple-app-preferences.md)：新增设置项前**必读**。不读会把键名写散，或设置窗口打不开。
- [../../_standards/workspace-docs/swift-docs/macos-system-permissions.md](../../_standards/workspace-docs/swift-docs/macos-system-permissions.md)：改粘贴授权引导前**必读**。不读会在拒绝后失去「仍可写入系统剪贴板」这条降级路径。
- [../../_standards/workspace-docs/swift-docs/apple-localization.md](../../_standards/workspace-docs/swift-docs/apple-localization.md)：改用户可见文案前**必读**。不读会把键名显示出来。
