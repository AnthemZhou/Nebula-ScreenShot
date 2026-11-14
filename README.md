# Nebula ScreenShot

**截取灵感，标记重点。** 一个轻量的 macOS 原生菜单栏截图工具。

按 **Control + Shift + Command + 4**，拖动选区，然后直接圈画、拉线、画箭头，或点击放置连续编号的圆形图钉 **① ② ③**。

[下载](https://github.com/AnthemZhou/Nebula-ScreenShot/releases) · [使用说明](#使用) · [从源码构建](#开发) · [GPL 3.0](LICENSE)

![使用真实标注渲染器导出的合成示例](docs/preview.png)

*上图为合成示例画布；圆圈、箭头、自由画线与编号均由应用的实际导出代码绘制。*

## 功能

- 全局快捷键 **⌃⇧⌘4** 与菜单栏入口。
- 拖动选择屏幕区域，原地显示悬浮标注工具条。
- 圆圈 / 椭圆、直线、自由画笔、箭头。
- **连续编号图钉**：选择图钉工具后，在选区内依次点击，生成圆圈内的 1、2、3……；每张新截图从 1 开始。
- 五种颜色、三档线宽；撤销、重做、清空标注、重新选区。
- 复制 PNG / TIFF 到剪贴板，或保存 PNG；保留 Retina 分辨率。
- 可在任意一块显示器上选择区域；一次选区限制在单块显示器内。
- 自带无需屏幕录制权限的示例画布，便于试用标注。
- 截图仅在本机内存中处理。没有账户、联网上传、埋点或第三方依赖。

## 安装

要求 **macOS 14 Sonoma 或更新版本**。Universal 发布包包含 Apple Silicon 和 Intel 两种架构。

1. 从 [Releases](https://github.com/AnthemZhou/Nebula-ScreenShot/releases) 下载 ZIP 并解压。
2. 将 **Nebula ScreenShot.app** 拖入「应用程序」文件夹，再打开。
3. 应用常驻菜单栏，关闭说明窗口不会退出应用。

首版采用 ad-hoc 签名，**尚未经过 Apple Developer ID 签名与公证**。从网络下载后，macOS 可能阻止首次打开。确认来源后，可在「系统设置 → 隐私与安全性」中使用「仍要打开」，也可在本机从源码构建。不需要关闭 Gatekeeper。

### 首次设置

**屏幕权限**：打开「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」（部分系统称「屏幕录制」），允许 Nebula ScreenShot。若系统要求，请退出并重新打开应用。应用只请求画面捕获，不录制音频。

**快捷键冲突**：macOS 默认也使用 **⌃⇧⌘4** 将所选区域截图拷贝到剪贴板。在「系统设置 → 键盘 → 键盘快捷键 → 截屏」中，取消这一项或改为其他组合，然后回到应用点击「重新检测」。不同系统语言下，该项名称略有不同，请核对按键组合。应用不会自动更改系统快捷键。

即使快捷键被占用，仍可点击菜单栏图标 →「区域截图」。权限和快捷键设置入口都在「设置与使用说明」窗口中。

## 使用

1. 按 **⌃⇧⌘4** 或点击菜单栏「区域截图」。
2. 按住鼠标拖出截图区域，松开后出现工具条。
3. 选择工具并在选区内标注。选择「图钉」后，每点击一次添加一个带递增数字的圆圈。
4. 按 **Enter / ⌘C** 复制并结束，或按 **⌘S** 保存 PNG。

| 操作 | 快捷键 |
| --- | --- |
| 圆圈 / 椭圆 | O |
| 直线 | L |
| 自由画笔 | P |
| 箭头 | A |
| 连续编号图钉 | N |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |
| 复制并结束 | ⌘C / Enter |
| 保存 PNG | ⌘S |
| 重新选择区域并清空标注 | R |
| 取消截图 | Esc |
| 正圆 / 水平或垂直线、箭头 | 拖动时按住 Shift |

工具快捷键仅在截图编辑期间生效。撤销图钉后继续点击，会使用当前下一个序号。取消保存对话框会回到原选区，保留已有标注。工具条与选区边框不会进入导出图片。

## 开发

需要 Xcode 16 或更新版本，以及 Swift 6 工具链。工程使用 Swift Package Manager，可直接用 Xcode 打开 `Package.swift`。只依赖系统框架 AppKit、ScreenCaptureKit 与 Carbon。

```sh
git clone https://github.com/AnthemZhou/Nebula-ScreenShot.git
cd Nebula-ScreenShot
swift test
./scripts/build.sh
open "dist/Nebula ScreenShot.app"
```

为保证系统权限归属于正确应用，实际截图请运行打包后的 `.app`，不要使用 `swift run` 请求屏幕权限。

生成同时支持 Apple Silicon / Intel 的发布包：

```sh
./scripts/package.sh --universal
```

输出位于 `dist/`，包含 ZIP 和 SHA-256 校验文件。默认 ad-hoc 签名；可通过 `CODE_SIGN_IDENTITY` 指定自己的签名身份。Developer ID 正式分发还需自行配置 hardened runtime、notarization 与 stapling；此脚本不宣称完成公证。

示例画布与可重现的渲染预览：

```sh
open "dist/Nebula ScreenShot.app" --args --demo
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-demo docs/preview.png
```

### 结构

- `Sources/NebulaCore`：标注数据、事务式撤销/重做、坐标换算、预览与导出共用渲染器。
- `Sources/NebulaScreenShot`：菜单栏、快捷键、屏幕捕获、选区、工具条与引导窗口。
- `Tests/NebulaCoreTests`：编号及分支撤销、Retina 选区裁剪、箭头几何、像素方向与导出位置测试。
- `.github/workflows/build.yml`：macOS 自动测试、Universal 构建和构建产物上传。

手动验收步骤见 [TESTING.md](TESTING.md)。欢迎提交 Issue 与 Pull Request。

## License

Copyright © 2026 Nebula ScreenShot contributors.

本项目使用 **GNU General Public License v3.0 only (`GPL-3.0-only`)**，全文见 [LICENSE](LICENSE)。

---

**English:** Nebula ScreenShot is a native, local-only macOS menu bar screenshot annotator. Press Control–Shift–Command–4, select a region, then draw ellipses, lines, freehand strokes, arrows, or sequential numbered pins. Copy to the clipboard or save a Retina-resolution PNG. Requires macOS 14+. Disable the conflicting built-in screenshot shortcut before using the global hotkey. The first release is ad-hoc signed and not notarized. Licensed under GPL-3.0-only.
