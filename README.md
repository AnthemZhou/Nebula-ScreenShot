# Nebula ScreenShot

**截取灵感，标记重点。** 一个轻量的 macOS 原生菜单栏截图工具。

按 **Control + Shift + Command + 5**，拖动选区，点击打编号图钉、左键拖圆角方框、右键拖直线；还可选择圆圈或箭头工具。确认后直接复制到剪贴板。

[下载](https://github.com/AnthemZhou/Nebula-ScreenShot/releases) · [使用说明](#使用) · [从源码构建](#开发) · [GPL 3.0](LICENSE)

![使用真实标注渲染器导出的合成示例](docs/preview.png)

*上图为合成示例画布；圆圈、方框、直线、箭头与编号均由应用的实际导出代码绘制。*

## 标注工具条

深色单行工具条，最前方放置 **六个色点**，随后是 **图钉、圆圈 / 方框、直线、箭头、画笔、橡皮擦**。主栏仅显示图标，选中背景与图标居中对齐；悬停提示和辅助功能名称保留。图钉按钮使用与画面相同的水滴形。默认使用 Dots 橙（`#EC603B`）；切换颜色只影响后续标注。**撤销、重做、保存 PNG** 直接位于主栏，粗细和其他操作保留在菜单中。

![实际标注工具条的离屏渲染](docs/toolbar.png)

图钉的尖角落在点击位置，大小随选区短边变化。以下合成示例使用实际渲染器、保持同一显示比例：

![小选区与大选区中的图钉比例](docs/pins.png)

## 二次编辑

鼠标停在图钉上显示删除按钮；停在线条或图形上显示控制点。下面是实际编辑器在合成画布上的状态，删除按钮和控制点不会进入导出图片。

![实际编辑器的悬停删除与端点控制点](docs/editor.png)

## 窗口

黑白小窗口仅显示 **Nebula ScreenShot、⌃⇧⌘5、版本号**。点击菜单栏 →「关于 Nebula ScreenShot」可打开；按 Esc 关闭。截图快捷键直接进入选区，不经过此窗口。

![主窗口内容的实际离屏渲染](docs/welcome.png)

## 功能

- 全局快捷键 **⌃⇧⌘5** 直接截图，与菜单栏入口；使用独占注册，避免多个 Carbon 快捷键监听者同时响应。
- 已授权时预加载显示器过滤信息，截图时复用这些信息并为各显示器并发请求当前画面；不缓存旧截图、不在后台持续录屏。选区完成后才创建工具条，减少进入截图时的初始化工作。
- 进入截图时立即显示选区界面与静态暗色遮罩，没有渐变或窗口动画；拖动选择屏幕区域，原地显示悬浮标注工具条。
- 标注工具：编号图钉、圆圈 / 圆角虚线方框、直线、箭头、手动画笔，以及橡皮擦。
- **连续编号图钉**：在选区内依次点击，生成 1、2、3……；水滴形图钉使用白色边框与白色数字，尖角精确落在点击位置。图钉随当前选区大小缩放，靠近边缘时自动避让；每张新截图从 1 开始。
- 鼠标悬停图钉时显示「−」删除按钮；删除后，其余图钉按创建顺序连续编号。悬停线条、箭头或图框会显示编辑控制点；拖动控制点调整端点 / 大小，拖动边线平移整个标注。
- 画笔记录手动轨迹；橡皮擦只擦去手绘笔触被涂抹的部分，保留其余笔触并露出下层标注和底图。图钉及几何图形仍按对象擦除。一次连续擦除只占一个撤销步骤；删除、改形、移动、擦除和编号变化都可撤销 / 重做。
- 默认图钉模式支持 **点击打钉、按住左键拖动圆角方框、按住右键拖动直线**；切换圆圈或箭头工具后，左键拖动绘制对应形状。圆角虚线方框固定使用“细”档（2 pt），不随线条 / 画笔粗细改变。
- 标注中仍可拖动选区四边和八个控制点调整大小，或按住 **空格 + 左键拖动** 平移选区。原有标记保留在原画面位置，导出按最终选区裁剪。
- 主栏提供橙、黄、绿、蓝、紫、白六色；粗细菜单提供三档线宽，主栏可撤销 / 重做，更多菜单可清空标注、重新选区。
- 编辑后点击「确认」或按 Enter，默认将 PNG / TIFF 复制到剪贴板；也可主动保存 PNG，保留 Retina 分辨率。
- 可在任意一块显示器上选择区域；一次选区限制在单块显示器内。
- 自带无需屏幕录制权限的示例画布，便于试用标注。
- 截图仅在本机内存中处理。没有账户、联网上传、埋点或第三方依赖。

## 安装

要求 **macOS 14 Sonoma 或更新版本**。Universal 发布包包含 Apple Silicon 和 Intel 两种架构。

1. 从 [Releases](https://github.com/AnthemZhou/Nebula-ScreenShot/releases) 下载 ZIP 并解压。
2. 将 **Nebula ScreenShot.app** 拖入「应用程序」文件夹（或 `~/Applications`），再打开。请使用固定目录中的这一份应用，不要从同步的源码 / `dist` 目录长期运行。
3. 应用常驻菜单栏，关闭说明窗口不会退出应用。

当前发行包采用 ad-hoc 签名，**尚未经过 Apple Developer ID 签名与公证**。从网络下载后，macOS 可能阻止首次打开。确认来源后，可在「系统设置 → 隐私与安全性」中使用「仍要打开」，也可在本机从源码构建。不需要关闭 Gatekeeper。

### 首次设置

首次使用的正常流程是：点击截图 → 应用发起 macOS 原生权限请求 → 用户允许，应用自动重启并恢复快捷键。**不应要求每位新用户手动添加应用**；列表「＋」是系统记录异常时的补救入口。应用不能代替用户允许权限。[Apple 官方示例的首次授权流程](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)。

**屏幕权限**：打开「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」（部分系统称「屏幕录制」），允许 Nebula ScreenShot。授权完成后，应用会自动重启并恢复快捷键；若系统出现退出提示，可按提示操作，无需再手动打开应用。应用只请求画面捕获，不录制音频。

首次截图被系统拒绝时，应用只发起一次原生授权请求，**不再叠加“需要屏幕录制权限”的应用提示框**。等待系统授权后，应用自动重启并恢复快捷键。v1.0.1 会在请求授权前准备一次性重启辅助进程，接住系统授权导致的退出；若权限变为允许而旧进程仍在，也会自动重启一次。

**开关已开，却仍被拒绝**：当前发行包使用 ad-hoc 签名，更新会改变代码身份，系统可能仍保存旧版本的授权。v0.1.9 会记住实际签名身份：已安装用户升级后，只有真正截图被拒绝时，才自动清除 **Nebula 自己的 ScreenCapture 记录一次**，重新启动并发起原生授权。成功截图会取消这次修复；同一签名后续被拒绝不会反复重置。首次安装和稳定证书签名不使用这条自动修复流程。

出现授权失败时，菜单栏主菜单会提供 **“修复屏幕录制授权…”**，设置中也保留“重新授权屏幕录制…”。选择后会直接清除 Nebula 的旧记录、重启并请求原生授权，不再要求手动用「＋」重新添加，也不叠加确认框。系统的“允许”仍须用户操作；其他应用的权限不受影响。授权辅助进程仅在当前授权期间临时存在，最长等待 10 分钟；成功截图、主动退出、强制退出或注销会结束该流程，不会作为常驻守护程序重开应用。如果系统列表本身异常，可最后尝试[手动添加当前安装的应用](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac)。

正式的跨版本授权需要稳定的 Apple 代码签名身份；固定安装目录本身不能消除 ad-hoc 签名变化。[Apple 对此问题的说明](https://developer.apple.com/forums/thread/819406)。

**快捷键检查**：默认快捷键为 **⌃⇧⌘5**，应用以独占方式注册。部分 macOS 配置会将它作为系统截屏快捷键的变体保留；出现在系统保留列表中，并不等于注册失败。菜单栏 →「设置」→「重新检测快捷键」会显示实际注册结果；其他应用独占此组合时，退出该应用后可重新检测。

如果按下后仍出现系统截屏面板，请检查「系统设置 → 键盘 → 键盘快捷键 → 截屏 → 截屏和录制选项」。独占注册不等于禁用系统快捷键，应用不会修改系统设置或请求额外的键盘监听权限。Apple 文档说明 **⇧⌘5** 用于打开截屏与录屏工具，但未单独说明加 Control 的变体：[Apple 使用说明](https://support.apple.com/en-euro/guide/mac-help/mh26782/mac)。

如果快捷键突然无反应且菜单栏图标也消失，请先重新打开应用：这表示应用可能已退出。v0.1.7 修复了 v0.1.6 在截图提示文字排版中崩溃的问题，并新增快捷键注册 / 收到事件的诊断日志。

即使快捷键被占用，仍可点击菜单栏图标 →「区域截图」。权限和快捷键检查入口统一位于菜单栏 →「设置」。

## 使用

1. 按 **⌃⇧⌘5** 或点击菜单栏「区域截图」。
2. 按住鼠标拖出截图区域，松开后出现工具条。
3. 默认点击打钉、左键拖圆角方框、右键拖直线。可从工具条选择颜色、圆圈或箭头。拖动选区边缘继续调整，已有标记不会清空。
4. 点击工具条右侧的 **勾号（确认）**，或按 **Enter / ⌘C**，截图即复制到剪贴板并结束编辑，可直接 **⌘V** 粘贴。需要文件时，点击主栏 **保存图标（向下箭头）** 或按 **⌘S**。

| 操作 | 快捷键 |
| --- | --- |
| 圆圈 / 椭圆 | O |
| 方框 / 矩形 | B |
| 直线 | L |
| 箭头 | A |
| 连续编号图钉 | N |
| 手动画笔 / 橡皮擦 | P / E |
| 删除当前选中标注 | Delete |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |
| 确认并复制到剪贴板 | Enter / ⌘C |
| 保存 PNG | ⌘S |
| 重新选择区域并清空标注 | R |
| 取消截图 | 空白处右键单击 / Esc |
| 调整选区大小，保留标注 | 拖动选区边缘或八个控制点 |
| 平移选区，保留标注位置 | 空格 + 左键拖动 |
| 正圆 / 正方形 / 水平或垂直线、箭头 | 拖动时按住 Shift |

空白处单击打钉；在已有标注上按下则选中并可拖动编辑。画笔模式下按住左键绘制轨迹。

“按住拖动”不需要等待计时；鼠标松开后提交标注，拖动不会额外生成图钉。右键单击画布可退出截图，右键拖动选区内则绘制直线。工具快捷键仅在截图编辑期间生效。撤销图钉后继续点击，会使用当前下一个序号。取消保存对话框会回到原选区，保留已有标注。工具条与选区边框不会进入导出图片。

## 开发

需要 Xcode 16 或更新版本，以及 Swift 6 工具链。工程使用 Swift Package Manager，可直接用 Xcode 打开 `Package.swift`。只依赖系统框架 AppKit、ScreenCaptureKit 与 Carbon。

```sh
git clone https://github.com/AnthemZhou/Nebula-ScreenShot.git
cd Nebula-ScreenShot
swift test
./scripts/check-interactions.sh
./scripts/check-relaunch.sh
./scripts/build.sh
open "dist/Nebula ScreenShot.app"
```

为保证系统权限归属于正确应用，实际截图请运行打包后的 `.app`，不要使用 `swift run` 请求屏幕权限。

生成同时支持 Apple Silicon / Intel 的发布包：

```sh
./scripts/package.sh --universal
```

输出位于 `dist/`，包含 ZIP 和 SHA-256 校验文件。默认 ad-hoc 签名；可通过 `CODE_SIGN_IDENTITY` 指定自己的签名身份。本地开发应使用固定的 Apple Development 身份，以便跨构建保持 TCC 授权；面向用户的发行应使用 Developer ID Application。Developer ID 正式分发还需自行配置 hardened runtime、notarization 与 stapling；此脚本不宣称完成公证。

实际权限验证请从最终 ZIP 安装后，通过 Finder / `open` 启动 `.app`。直接运行包内二进制可能让权限归属启动它的终端或开发工具，不能据此判断应用本身是否获准。应用记录截图请求、选区就绪、一次性授权修复及错误 domain/code，不记录屏幕内容：

```sh
open "$HOME/Applications/Nebula ScreenShot.app" --args --capture
log show --last 5m --style compact --predicate 'subsystem == "io.github.anthemzhou.NebulaScreenShot" AND category == "Capture"'
```

`--capture` 在应用启动时直接开始一次截图；应用已运行时请使用快捷键。更新后若需命令行恢复，只重置此应用：`tccutil reset ScreenCapture io.github.anthemzhou.NebulaScreenShot`，然后重新启动并授权。

示例画布与可重现的渲染预览：

```sh
open "dist/Nebula ScreenShot.app" --args --demo
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-demo docs/preview.png
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-welcome docs/welcome.png
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-toolbar docs/toolbar.png
```

### 结构

- `Sources/NebulaCore`：标注数据、事务式撤销/重做、坐标换算、预览与导出共用渲染器。
- `Sources/NebulaScreenShot`：菜单栏、快捷键、屏幕捕获、选区、工具条与引导窗口。
- `Tests/NebulaCoreTests`：编号及分支撤销、可调整选区几何、图钉比例与尖角、白色图钉边框与数字、编辑命中和重编号、局部擦除及下层像素保留、Retina 裁剪与导出位置、权限错误分类测试。
- `Tests/InteractionChecks`：实际 AppKit 控件的隐藏窗口手势回归与反复绘制检查；不捕获桌面、不注入系统输入、不写系统剪贴板。
- `Tests/RelaunchChecks`：用独立测试父子进程验证退出状态、取消和超时，不请求屏幕权限、不启动真实截图应用。
- `.github/workflows/build.yml`：macOS 核心 / 编辑器交互测试、Universal 构建和构建产物上传。

手动验收步骤见 [TESTING.md](TESTING.md)。欢迎提交 Issue 与 Pull Request。

## License

Copyright © 2026 Nebula ScreenShot contributors.

本项目使用 **GNU General Public License v3.0 only (`GPL-3.0-only`)**，全文见 [LICENSE](LICENSE)。

---

**English:** Nebula ScreenShot is a native, local-only macOS menu bar screenshot annotator. Press Control–Shift–Command–5 to capture directly, select a region, then use the compact icon-only dark toolbar for numbered pins, ellipses/rectangles, lines and arrows. Click the checkmark or press Enter to copy the annotated image to the clipboard by default. Six color dots lead the toolbar, with Dots orange as the default; Save PNG is directly accessible. Click to pin, left-drag to draw a rounded rectangle in pin mode, and right-drag to draw a line. Pins scale with the crop, have white outlines/numbers and an exact-position teardrop tip. Hover to delete a pin and renumber the others, or edit shape endpoints and bounds. Rectangles use thin 2 pt rounded dashed borders. The eraser removes only brushed regions of freehand strokes and whole objects for other annotation types; each sweep supports undo/redo. Resize the selection using its edges, or Space-drag to move it while keeping annotations in place. Right-click the canvas to cancel. The capture interface and static selection shade appear immediately, with no fade or window animation. Display-filter metadata is reused and toolbar creation is deferred; every capture still requests fresh pixels, without background recording. The compact About window uses only black, white and neutral gray. Requires macOS 14+. The global shortcut uses exclusive registration; if the system screenshot panel still appears, adjust the conflicting system binding. Permission requests use the native macOS prompt without a duplicate in-app alert. A temporary helper restores the app and hotkey after consent, reuses any instance macOS has already reopened, and respects explicit quit, force quit and logout. A changed ad-hoc build can repair its own stale screen-permission record once after a real denial, then relaunch for native consent; later denials do not trigger repeated resets. The app is ad-hoc signed and not notarized. Licensed under GPL-3.0-only.
