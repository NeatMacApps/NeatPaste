# 历史面板：预览尺寸、光标锚点、去重、点外面关闭、图片缩略图、按住方向键、搜索与玻璃、点选粘贴、滚动条、展开抖动与帧调度

文档定位：历史面板已证伪路径与必须留下的拦法。覆盖系统预览尺寸/换条闪动、光标锚点、去重、点外面关闭、图片缩略图、按住方向键、滚动条、搜索与玻璃、点选粘贴、展开时的上下抖动与逐帧调度。1.0.17 的帧率缓解未解决抖动；后续整数点坐标修复已进入本机 1.0.18，安装后的动效验收仍待完成。产品行为以 [PRODUCT_CONTRACT.md](../PRODUCT_CONTRACT.md) 为准。

## 预览必须是系统预览，且必须一直是小窗

空格打开的是系统 Quick Look，禁止改回自绘预览栏。标题是「预览」，不是条目正文。

系统预览换内容时会**自己把窗口撑大**。最小/最大尺寸只拦用户拖拽，**拦不住程序化改尺寸**。

### 走不通的路

- **换条后不再压回尺寸，只刷新内容。** 闪动会少，但窗口会停在大尺寸。用户已经因此返工。
- **刷新后立刻压一次就结束。** 系统预览撑大时往往处于「正在缩放」；若因此跳过压回，这一次等于没压，窗口同样停在大尺寸。
- **等它撑大之后再延时缩回去。** 能收回小窗，但用户会看见先变大再变小，就是换条闪一下。
- **为了让空格键回到列表，把焦点从预览抢回历史面板。** 预览会变成空白。预览打开期间用临时热键收空格、Esc、上下键；不要抢焦点。

### 正确拦法

1. 在窗口**将要变大时**直接返回规定小窗尺寸，让它根本撑不开。
2. 尺寸一旦偏离，立刻压回；换一条之后也要压，不能只在第一次打开时压。
3. 系统预览自己缩放时不要当成「用户在拖、可以跳过」。
4. 空格 / Esc / 上下键可能同时走到临时热键、预览窗和列表三条路径，必须合成一次，否则会连跳并连带多次刷新。按住上下键时，这条临时热键不会连发，必须接到同一套按住连走，且不得把焦点抢回列表。

验收：打开预览后连续换若干条，窗口一直保持小窗，不得停在大尺寸，也不得先撑满再缩。

## 图片预览不能落成纯文本

列表已有缩略图但空格预览像文本文件，多半是 Quick Look 选错了落地 URL。

### 走不通的路

- **先认 `public.file-url` 再认图片。** 截图类条目常同时带临时文件地址与旁路/内联图片；地址可能仍指向磁盘上的**非图片**文件，Quick Look 会按文本打开，而缩略图走的是旁路图片。

### 正确拦法

1. 与缩略图同一优先级：旁路图片 → 内联图片 → 仅当 `public.file-url` 指向图片或本条不是图片条目时才用文件地址。
2. 旁路 manifest 读不到时，再 materialize 外置载荷写临时图片文件，不要直接写 `plainText` 的 `.txt`。
3. 旁路 blob 文件名是 sha256、无扩展名，**禁止直接把旁路原路径交给 Quick Look**：Quick Look 靠扩展名选预览器，无扩展名的图片会被当文本打开（列表缩略图不受影响，因其走 CGImageSource 内容嗅探）。必须按条目图片类型推断扩展名（png/jpg/tiff/heic/gif），拷贝到 `NeatPasteQuickLook/<id>.<ext>` 再返回。

验收：复制截图 → 列表有缩略图 → 空格预览必须是图片小窗，不是「图片」或文件名的文本页。

## 面板贴输入位置，不贴整块编辑区

每次打开都要重新锚到**当前输入光标**。历史面板不记忆上次位置。设置窗的位置记忆是另一回事。

左边界与光标垂直对齐，窗口从光标往右展开；垂直方向完整让开当前输入行（优先在这一行下面，下面不够再放到上面）。进出场从光标用通透玻璃真实撑开窗口，禁止用缩放装小（会发糊）；这是高频操作，要快、无回弹。粘贴前必须先交出键盘，不能等收起动画结束。

### 走不通的路

- **拿当前焦点控件的整框当光标。** 大编辑器、网页、整页输入区会把面板甩到窗口最底下，看起来像没跟随。
- **先做异步刷新再去问光标。** 面板一旦成为焦点，辅助功能只能看到本应用，锚点会错到自己身上。必须在异步刷新**之前**记下位置。
- **焦点落在本应用时仍当输入位置。** 应丢弃，改走鼠标等后备。
- **以光标为中心左右对半摆面板。** 左半边会盖住已经打的字，看起来像挡住半行。必须左边界对齐光标；只有贴到屏幕边缘才允许往回夹。
- **贴着光标中线或短插入条摆，只留很小空隙。** 辅助功能给的光标矩形常常只有一两像素高，会盖住半行。必须按整行高度让开。
- **用缩放把整窗从很小放到正常。** 玻璃会发糊。进出场必须改真实窗口尺寸，从光标旁一滴玻璃撑到规定大小。
- **收起动画还没完就发送粘贴。** 面板若仍占着键盘，粘贴会打进自己的搜索框。必须先交出键盘，玻璃再收回去。

### 正确顺序

1. 先问插入点（选区范围对应的屏幕矩形）；零长度选区拿不到时，用相邻字符的矩形。
2. 没有光标再用当前输入框；输入框过大则收成光标/鼠标所在点，禁止按整框底边摆。
3. 再没有则鼠标所在屏幕、鼠标附近。
4. 点菜单栏图标时，系统往往已经丢掉光标，退到鼠标附近是预期；**快捷键唤出**才是贴着输入位置的路径。
5. 算出锚点后：左边界对齐光标；面板整体放在这一行下面（或上面），不要挡住这一行。

## Vertical jitter during downward expansion

The reported symptom is primarily downward expansion with content pinned to the top,
plus occasional horizontal shimmer.
`PinnedContentHost.layout()` alone left the full-size hosting view at its previous
position immediately after a resize; an isolated native resize probe and the regression
test reproduced the stale content edge. Upward expansion pins content at y = 0 and
requires no corresponding per-frame translation, explaining the directional difference.

1.0.12 added the synchronous `resizeSubviews(withOldSize:)` correction with disabled
Core Animation actions. Installed 1.0.12 still showed vertical jitter on downward
expansion and occasional horizontal jitter, so that correction alone was insufficient.

Root cause (1.0.13): `animator().setFrame` animates a window's origin and size as
separate Core Animation properties. Even when seed and target share the caret-adjacent
edges, the two tweens interpolate independently with per-frame display rounding, so
`origin + size` wobbles by fractions of a point. The animator group also enables
implicit animations for descendant layers even without an explicit
`allowsImplicitAnimation = true`, so SwiftUI/glass layers lag one frame behind.
The motion test only asserted the vertical edge, so the horizontal drift was uncovered.

Fix: drive show/hide frames with a manual anchored stepper (same durations and
cubic-bezier control points as `PanelMotion`, now shared from one source). Each tick
interpolates width/height plus the fixed edges with a single eased progress, derives
the origin from the fixed edges (shared edges stay exactly constant), snaps to backing
pixels, and sets the frame synchronously with all implicit actions disabled. Ticks are
paced by the display vsync (`NSWindow.displayLink`, common modes); a Task fallback
exists only for environments where the link never arrives, and the two never drive
the same motion (see "One clock, one driver" below). Progress is a pure function of wall time. The motion
clock starts on the first vsync tick, not at setup, so a cold first render (tens of
milliseconds) cannot be charged to the curve and presented as one huge jump. The
appear curve is now ease-in-out (see "Thumbnail decode on the main thread" below).
Reduced-motion paths keep their fade-only
behavior with `allowsImplicitAnimation = false` set explicitly. Real window resize is
preserved (no scaling, no bounce, same 0.18/0.12 s pacing).

Do not reintroduce a per-tick progress cap. A 10%-per-tick cap was tried and made
every invocation worse: on the 120 Hz MacBook display it turned the 0.18 s ease-out
into a fixed 10-tick staircase (~80 ms) with 40 px steps, and because the fallback
Task and the display link can both tick inside one refresh, some frames advanced two
steps at once (79 px). The user reported the jitter moving from one editor to every
app. `HistoryPanelMotionTests` now asserts that the show motion still spans the
planned duration rather than finishing in ~10 ticks (measured heights before the fix:
`36, 115, 155, 195, 274, 313, 353, 419, 425, 428, 432`; after: `36, 43, 125, 172,
252, 284, 311, 363, 382, 393, 419, 425, 428, 430, 431, 432`). A time-based cap is not
a substitute: any step budget tied to ticks changes speed with the display refresh,
and any budget tied to elapsed time still lets a hitch teleport the panel.

One clock, one driver (1.0.16). The display link delivers `CADisplayLink.timestamp`
(vsync time) while the fallback Task reads `CACurrentMediaTime()` (wall time). The
fallback's stall test compared one with the other and fired whenever the gap exceeded
12 ms — shorter than an 8.3 ms 120 Hz frame plus callback latency — so it inserted a
wall-clock frame between two vsyncs. The next link tick then carried an earlier
timestamp, progress regressed, and the window visibly shrank 7–13 pt and grew back.
Measured in the NeatEditor run: `h=304.5 fallback` immediately followed by `h=291.5
link`, then `h=346.0 fallback` / `h=339.0 link`. Fix and rules: record the link's last
delivery in wall time and only let the fallback take over after 120 ms of link silence
(150 ms from motion start when no link has ever fired); once it takes over, link ticks
are ignored for that motion. Never compare the link timestamp with the wall clock and
never let both sources step one motion. Progress keeps a monotonic floor as a second
guard, so no out-of-order timestamp can ever shrink the window mid-expansion. Healthy
NeatEditor runs now show one driver for every tick, intervals of 8.3 ms, no negative
dt, and strictly non-decreasing height (measured 13 consecutive show/hide motions).

Content grows with the glass. Do not stage content behind a late fade-in (the glass
was empty until 70% progress and the text popped in over the last 30%): that reads as
"hitch, then grow" on every invocation and was reverted. The list still suppresses
`ScrollViewReader.scrollTo` while `HistoryPanelModel.isMotionActive` is set (instant
non-animated scroll otherwise) and snaps once when motion ends. Reload churn is
landed while ordered out: `HistoryPanel.prepareForShow` pre-lays out rows before
the visible expansion. Thumbnail decoding itself is asynchronous and must stay off
the main thread (see below). Do not add fixed sleeps before showing; the motion
clock already waits for the first presented frame, and a fixed delay only makes
every invocation feel late. This matters most for the
copy-then-invoke flow where a new row prepends and the selection resets on every
show. Anomaly-only telemetry logs slow motions and dropped vsync ticks; healthy
motions stay silent.

Thumbnail decode on the main thread (1.0.17) — mitigation, cause not confirmed.
Earlier status (2026-10-17, before native-coordinate diagnosis): 1.0.17 (18) was built and installed locally, and the user
still reports vertical judder in NeatEditor. The synchronous decode below was a
real first-open stall and removing it improved frame pacing, but frame pacing
improving did not remove the perceived jitter. Do not describe this change as
the fix and do not close the symptom on telemetry alone. The remaining cause
was unresolved at that point; the later fractional-anchor diagnosis is below.

Geometry telemetry during the
reported jitter showed zero edge error, zero glass/pin error and no layer
animations, yet `CADisplayLink.timestamp` gaps of 25–64 ms: the window was being
placed correctly but whole vsyncs were missed. Sampling the process showed the
stalls on the main thread inside display/transaction work, and their heights
matched the rows that had just become visible. `HistoryRowView` called
`HistoryThumbnail.image(for:)` synchronously in its SwiftUI body; that function
read the payload file and ran ImageIO downsampling. The newest entry was a
7.2 MB screenshot, and the stalls landed at h≈156 and h≈384 — exactly when the
rows holding the large images first rendered. A first show after launch produced
only 10–13 motion frames over ~200 ms; episodes with fewer new rows produced 21–22.

Change in 1.0.17: the row body only reads an `NSCache` (`HistoryThumbnail.cachedImage(for:)`,
no I/O). Decoding runs in `Task.detached(priority: .utility)` behind a per-item
`DecodeRegistry`, so a row that scrolls in and out does not start duplicate
decodes. `AppDelegate.showPanel` calls `HistoryThumbnail.prewarm` for the first
12 image items after reload, so the first visible rows are usually ready before
the expansion reaches them; a row that is not ready yet keeps its photo
placeholder and swaps in when the decode completes. Tests are async and call
`loadImage(for:)` before reading the cache. With this in place, a clean first
show after launch measured 22 frames / 175 ms with no gaps, and four
non-overlapping cycles measured 21, 21, 22 and 22 appearance frames (dismissals
15 frames). Those numbers only prove fewer missed vsyncs; they do not establish
that the panel looks smooth to the user.

Two motion changes landed with it. Per-frame opacity is gone — the window and
hosting view stay at alpha 1, so the glass is not recomposited every tick (the
old fade also squared the effective opacity of the window and content together).
And frames are set with `display: false`; forcing a display pass on every 120 Hz
tick made the glass re-render on the main thread. The appear curve is
ease-in-out (0.4, 0.0, 0.2, 1.0): its fastest section is in the middle, so one
dropped vsync cannot double or triple the height step. Reduced-motion still
uses the 0.08 s fade and was left unchanged.

Do not put image decoding, file reads or payload materialization back into a
SwiftUI body, and do not make the cache lookup fall back to a synchronous
decode on a miss — that reintroduces the stall only on the first show, which is
the invocation users notice. Do not restore per-frame alpha or `display: true`;
both were measured to cost frames. Residual limit: a payload whose decode has
not finished when its row becomes visible shows the placeholder for a few
frames; prewarm makes this rare, and swapping the thumbnail in does not resize
the row.

Reuse the existing `HistoryPanel` / `PinnedContentHost` implementation and the public
`NSView.resizeSubviews(withOldSize:)` callback to position content synchronously. Disable
Core Animation actions for this corrective translation; keep the real window resize (no
scaling) and the fade that belongs to the reduced-motion path. Do not reintroduce
per-frame opacity on the normal path. Do not replace real window resizing with scaling or
lengthen the animation to hide the defect. Shared API details:
[AppKit resizing and pinned content](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#pinned-content-during-window-resize)
and [display-link window motion](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#display-link-window-motion-and-main-thread-work).

Regression coverage includes immediate resize without a deferred layout pass, both
anchor directions, sampling the actual `HistoryPanel.showPanel(placement:)` animation,
and horizontal edge stability (window + content `minX`) alongside the vertical
caret-adjacent edge. Review live motion separately from geometry assertions; static
screenshots cannot prove absence of compositor jitter, and in-process frame counts do
not override the user's live report.

Test-harness warning: `HistoryPanelMotionTests` exercises the real panel, so running
`xcodebuild ... test` orders the panel front and can steal focus on every cycle. On
2026-10-17 repeated full-suite runs interrupted the user's normal computer use; the
user explicitly asked for the popups to stop. Do not run window-motion tests while
the user is actively using the Mac; ask first or run only non-UI tests. One
environment-sensitive failure was observed: `testAnimatedWindowKeepsCaretEdgeAndContentTogether`
can sample only the 36 pt seed for the whole 240 ms window and fail "Must sample an
in-flight resize". Hypothesis (unconfirmed): the test host loses key, `resignKey()`
calls `hidePanel()`, and the hide path cancels the appearance motion at seed height.
Do not treat that failure as a product regression until visibility/key state and hide
calls are checked. The test passed 14 consecutive isolated runs after the failure.

### Validation diagnostics

Current verification boundary (2026-10-18): the owner requires virtual displays to
stay disconnected during normal use; a short idle period is not permission to
connect one. Do not synthesize panel shortcuts, move windows or change focus as a
substitute. A bounded, observation-only capture helper can wait for an ordinary
NeatEditor invocation, record its actual expansion once and exit. If none occurs,
expiry is missing acceptance evidence, not a product pass. Keep the recorded binary
identity and the complete capture log with the evidence. Installed 1.0.18 (19)
includes the motion fix; a new installation/version number alone does not clear it.

The earlier non-exclusive Carbon registration probe returned `noErr`; it did not
prove NeatPaste's hotkey registration was missing. Apple's installed SDK permits
multiple non-exclusive registrants. See the shared
[Carbon diagnostic limit](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#carbon-全局快捷键在-swift-6-并发下的桥接).
No additional hotkey or startup change is justified by that probe.

A production recording on 2026-10-17 captured the installed 1.0.17 (18)
expanding from NeatEditor on the 2× virtual display. The selected-row top alternated
between 604 and 606 backing pixels before settling; concurrent WindowServer bounds
alternated between y=252 and y=253 points. This is rendered movement, not a frame-count
inference. A silent native `NSPanel.setFrame(_:display:)` probe then reproduced the
cause: AppKit floors the origin and ceils the size to whole screen points on this
macOS 27.2 system. With a fixed requested top edge of 1043.5 pt, integer and half-point
heights alternate the actual top between 1043 and 1044 pt. The earlier layout probe
used an integer top edge and therefore missed this case.

Repair: retain the existing panel, content pin, display-link clock and real resize.
Align window geometry to whole screen points before deriving the seed and each
anchored interpolation; Retina backing-pixel alignment alone is insufficient for
these native window bounds. Preserve the current curve, duration, content size and
focus/dismissal behavior. Validate the repaired artifact using an actual NeatEditor
expansion recording and rendered row/top-edge positions; native frame readback is
additional evidence, not a substitute. The implementation and 82 non-presenting Debug tests pass, including native
window quantization regression coverage for fractional anchors in both directions.
Release compilation passed for arm64 and x86_64, and static analysis passed. The
existing App Intents metadata warning is retained as assessed below. Visual
acceptance remains pending. This motion task has no authorization to publish or
change the update feed.

Silent layout probe (2026-10-17, installed 1.0.17 (18) unchanged): an independent
CLI reused the current `PinnedContentHost`, `PanelGlassView` and `PanelSearchField`
source with a synthetic fixed-size SwiftUI search/list layout. It never ordered
the panel in or made it key. Across both pin directions and ten heights per
direction (including 36, 84.5, 156, 190.5, 320.5, 384 and 432 pt), the search
region, native text field and first-row marker each retained one screen-coordinate
rectangle, both immediately after layout and after a run-loop turn (40 samples).
The probe compiled under Swift 6 complete concurrency with no diagnostics; its
runtime diagnostic stream was empty. This does not reproduce production data,
key/focus changes, scroll-to-selection callbacks, live display-link timing or the
WindowServer compositor, and cannot clear the reported symptom.

Initially, the execution host reported `CGPreflightScreenCaptureAccess() == false`
and `AXIsProcessTrusted() == false`; region capture failed and video produced no
file. After the owner unlocked the session and the current `tmux` screen-recording
entry was enabled through System Settings, capture preflight returned true. An
actual BetterDisplay virtual-screen image and two-second video were inspected.
A targeted NeatEditor shortcut attempt did not expose the history panel; the
recording did not contain the required expansion, so it provides no motion
acceptance evidence. See the shared
[closed-lid capture notes](~/.config/agentsync/docs/MAC_KNOWLEDGE_BASE.md#closed-lid-screen-capture-2026-10-17)
for setup outcomes and the remaining closed-lid verification limit.
Do not open repeated test panels without a working way to capture their rendered
motion. The next evidence must distinguish internal content movement from glass,
shadow or window-surface movement in the actual NeatEditor interaction; no new
animation parameter change is justified by this probe. Modern screen-flush API
limitations are covered in the shared
[display-link motion notes](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#display-link-window-motion-and-main-thread-work).

- Animation completion callbacks now enter the existing main-actor bridge before checking
  the generation and changing panel state; no cross-actor warning is retained.
- Drag tests assert loaded values inside the provider callbacks before fulfilling their
  expectations, removing mutable captures shared with an internal provider queue.
- Xcode 27.2 emits `Metadata extraction skipped, no AppIntents.framework dependency found`
  for the application/test targets. Neither target declares App Intents or shortcuts;
  metadata extraction has no inputs and the product does not depend on its output.
  Retain this tool-generated warning rather than add an unused dependency or suppress
  diagnostics. Reassess if an App Intents feature is introduced.

### Verification scope (1.0.12)

Xcode 27.2 / macOS 27.2: all 81 Debug tests and static analysis passed. The motion
regression sampled 30 live window sizes in each direction, confirmed in-flight resize
samples and stable caret/content edges within 0.5 pt, and rejected independent geometry
animations on the hosted layer while allowing its intended opacity fade. Six native
view-render attachments from downward expansion were inspected. Release archive/export
compiled arm64 and x86_64; the installed 1.0.12 (13) executable matched the exported
artifact. The installed panel was opened through Settings > More > Open Panel, captured
with the native computer tool and dismissed with Esc. Existing history remained visible.

The terminal execution host has no Screen Recording or Accessibility access. Its window
screenshot helper could not capture the panel; the native computer tool supplied the
installed-window capture instead. Native cached view renders do not establish compositor
frame pacing, and no continuous desktop recording is claimed.

### Release workflow

The publisher now uses Developer ID archive/export, reusing NeatWebApp's release workflow
and [Sparkle's supported distribution route](https://sparkle-project.org/documentation/).
The exported app is installed after the source commit, before the external notarization
wait. Publication still requires stapled app/DMG tickets, signed update feed and verified
remote assets. Build logs remain local and are excluded from source staging.

## 相同内容只留一条

再复制一次已有内容：删掉旧的，新的顶到最上，并留下这一次的完整格式。不要并排堆重复。

比较的是用户看见的内容（图片字节 / 文件地址 / 正文），不要把网页或应用每次复制都会变的元数据当成新条目。正文相同、附带格式每次略有不同，仍算同一条；最新一次覆盖。

## 点面板外必须立刻关掉

面板是非激活浮层，打开时底下那个应用仍是前台。用户点回那个应用、桌面或别的窗口时，本窗口往往**不会失焦**，也不会触发「本应用失活」。

### 走不通的路

- **只在窗口失焦时关掉。** 点回正在用的应用时经常根本不失焦，面板会继续挡屏幕。
- **在本应用失活时关掉。** 浮层本来就不把本应用切到前台，这条路径一打开就会把面板自己关掉。

### 正确拦法

1. 打开后面板外的按下（含点到别的应用）必须立刻关掉；点击仍要落到被点的地方，不要变成先关再点第二次。
2. 点在面板里、系统预览上、菜单栏本图标上不要关。菜单栏本图标仍走原来的开关。
3. 不要用「本应用失活」来关。

## 图片行必须是缩略图，不要内部文件名

复制图片时，系统常常顺手带上临时文件地址，文件名是一串编号。那不是用户复制的正文。

### 走不通的路

- **列表左侧只放通用照片图标。** 固定小方图必须画出真实缩小图。
- **把临时文件名当标题。** 用户会以为复制坏了。没有可读名称时显示「图片」；截图保存名这类真人能认的名字可以显示。

## 7 天历史必须扛过重启

「保留 7 天」是用户退出、杀进程、覆盖安装后再打开，7 天内的条目还在。只在本次运行里记着，等于没保存。

### 走不通的路

- **第一波先放内存、重启丢失。** 产品契约曾经允许，用户已经否决。不得再当完成态。
- **用 SwiftData / Core Data / GRDB 才算持久化。** 本机用户资料目录里的文件即可，完整保留格式，到期再清。

验收：复制几条 → 退出或重启 → 再打开仍能看到；满 7 天的条目消失。

## 按住上下键必须连续移动

面板不能把自己切成前台，否则回车会贴到自己身上。这种非激活浮层常常只收得到第一次按下，系统连发到不了；把按下吞掉不传给搜索框之后，系统也可能不再连发。

### 走不通的路

- **指望系统连发事件。** 点一下能动、按住不动，就是这条。
- **为了收到连发把本应用切到前台。** 粘贴会贴到自己身上。
- **预览开着只靠临时热键点一下。** 热键只响按下一次，按住不会连发；预览成为焦点后按键也不会回到列表。
- **为了连发把焦点从预览抢回列表。** 预览会变成空白。

### 正确拦法

1. 第一次按下立刻移动一条，同时按系统连发延迟/间隔自己连续走。
2. 抬起、键已经松开、或关掉面板时停。
3. 系统连发若仍到达，丢掉，避免一次跳两格。
4. 预览开着时，临时热键的按下也要启动同一套按住连走，抬起时停。热键、预览窗、列表同时收到第一次按下，只走一步。不要抢回焦点。

验收：列表里有多条时按住下键，选择应连续往下走，松手即停。打开预览后再按住，预览和列表都要连续换条，预览仍是小窗且不是空白。

## 搜索和列表必须是同一块实底；外框才是通透玻璃

搜索不是独立控件，不要做成「列表上面另套一个带描边的输入框」。外框玻璃要对齐同类捕捉窗：通透，不要雾面。

### 走不通的路

- **给搜索单独铺一块底再加粗描边或焦点描边。** 和下面列表不是同一块，用户一眼看成粗框。
- **焦点时再叠一层加深底。** 搜索会比列表暗一截，看起来仍像另套边框。
- **窗口外框用雾面材质。** 边缘会变成一圈脏灰边，不是通透玻璃。同类捕捉窗用的是通透玻璃加细白边。
- **只靠窗口自身截图验收玻璃。** 那种截图采不到桌面，通透玻璃会看起来像一块实心灰，不能当观感依据；要在真实桌面/壁纸上看边缘。

### 正确拦法

1. 搜索和列表放进同一块内容实底；搜索本身不再铺底、不再描边；焦点用插入光标即可。
2. 外框用通透玻璃，细白边勾边缘；列表仍是内容层实底，字必须在干净底上。
3. 玻璃验收看真实屏幕上的窗口边缘，不要用「只含窗口、背景是黑的」那种截图下结论。

验收：搜索区域和列表是同一块底、没有粗描边；窗口边缘能看出背后桌面，不是一圈雾面灰框。

## 列表不得出现滚动条

列表可以滚，但不能画出滚动条。这和系统外观里「滚动时显示 / 始终显示」无关：历史面板自己必须藏掉。

### 走不通的路

- **只说「尽量隐藏」。** 系统把这当成建议。笔记本用触控板时看起来对了；接上鼠标（蓝牙鼠标也算）就会把滚动条画回来。这不是某一个大版本才有的例外，26 和更新系统都这样；不要拿另一台不同大版本的机器当验收。
- **为了消掉滚动条去关掉滚轮/触控板滚动。** 上下键、滚轮和触控板滑动都必须还能走列表。

### 正确拦法

必须用「永不显示」，覆盖系统在接鼠标时仍要画出滚动条的那条默认。上下键连发、滚轮、触控板滑动仍可滚。

验收：历史超过一屏时，接鼠标的 Mac 上打开面板，列表右侧不得出现滚动条；滚轮和上下键仍能移动。

## 点已选中或双击才粘贴，不要点一下就贴

点未选中的条目只换选中；再点已选中的、或双击，才走和回车一样的粘贴。打开后面板已经选中最新一条，点它就应粘贴。

### 走不通的路

- **点一下就粘贴。** 和键盘选中再回车不一致，划过列表时会误贴。
- **关掉面板后不管双击收尾。** 打开时最新一条已选中，用户常会双击它；第一下粘贴并关掉后，第二下会点穿到正在输入的窗口，可能点中按钮或选中一段字。

### 正确拦法

1. 未选中 → 只选中；已选中再点 → 粘贴。双击未选中的条目自然是先选中再粘贴。
2. 鼠标触发的粘贴在关面板之前，先挡住原来那块位置，吃掉双击收尾那一下；键盘回车不用挡。

验收：点另一条只会换高亮；再点同一条会粘贴并关掉。双击最新一条只贴一次，不会点到下面窗口。

<!-- 该文档整理/压缩于 2026-09-05 -->
