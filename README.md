# Nebula ScreenShot

<img src="docs/icon.png" width="96" alt="Nebula ScreenShot 黑白圆角图标">

轻量的 macOS 菜单栏截图、标注与文字提取工具。按 **⌃⇧⌘5** 拖选区域，添加编号图钉、图形或手绘标记，再按 **回车** 复制图片；也可开启 **提取文字**，选中图片里的文字并复制。

**当前版本：v1.1.8** · macOS 14+ · Apple Silicon / Intel · GPL-3.0-only

[**下载 v1.1.8（Universal ZIP）**](https://github.com/AnthemZhou/Nebula-ScreenShot/releases/download/v1.1.8/Nebula-ScreenShot-1.1.8-universal.zip) · [发行说明](https://github.com/AnthemZhou/Nebula-ScreenShot/releases/tag/v1.1.8) · [安装](#安装) · [首次授权](#首次授权) · [使用](#使用) · [快捷键](#快捷键) · [常见问题](#常见问题)

## 安装

1. 下载上方的 **`Nebula-ScreenShot-1.1.8-universal.zip`**。同一个安装包适用于 Apple Silicon 和 Intel，无需选择架构；GitHub 的 `Source code` 是源码，不是应用安装包。
2. 双击 ZIP 解压，将 **Nebula ScreenShot.app** 拖入「应用程序」文件夹，再从那里打开。也可以安装到用户自己的 `~/Applications`，后续更新请沿用同一位置。
3. 在屏幕顶部菜单栏找到 Nebula 的取景框图标。应用常驻菜单栏；关闭「关于」窗口不会退出应用。

**首次打开被 macOS 阻止？** 当前下载包尚未经过 Apple Developer ID 签名与公证。确认文件来自本仓库的 Release 后，先尝试打开一次，再到 **系统设置 → 隐私与安全性 → 仍要打开**，按系统提示确认。详见 [Apple 的打开说明](https://support.apple.com/zh-cn/102445)。

需要核对下载文件时，可使用发行页附带的 [SHA-256 校验文件](https://github.com/AnthemZhou/Nebula-ScreenShot/releases/download/v1.1.8/Nebula-ScreenShot-1.1.8-universal.zip.sha256)。

## 首次授权

首次截取真实屏幕需要允许 macOS 的屏幕录制权限。**打开应用的确认和屏幕录制授权是两件事。**

1. 打开应用后，按 **Control + Shift + Command + 5**，或点击菜单栏图标 → **区域截图**，触发系统授权请求。
2. 在 macOS 提示中允许 Nebula ScreenShot；若提示打开设置，进入 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制**，打开 **Nebula ScreenShot** 的开关。不同系统版本也可能将这一项称为「屏幕录制」或「录屏与系统录音」。
3. 如果系统要求退出并重新打开，按提示操作。应用会自动恢复运行和快捷键，然后再次按 **⌃⇧⌘5** 开始截图。

通常无需手动把应用添加到权限列表。找不到应用或开关已开却仍不能截图时，请看下方的 [常见问题](#常见问题)。系统权限的位置也可参阅 [Apple 说明](https://support.apple.com/zh-cn/guide/mac-help/mchld6aa7d23/mac)。

Nebula 只捕获屏幕画面，不录制音频。想先熟悉标注，可选择菜单栏 → **试用标注…**，使用不需要屏幕录制权限的示例画布。

## 使用

### 图片文字提取

1. 拖出截图选区后，点击工具栏中橡皮擦右侧的 **「提取文字」** 图标（文字取景框）。默认不开启，普通截图不会启动识别。
2. 等待下方的「正在识别文字…」结束，在图片文字上按住左键拖选；支持局部、反向和跨行选择。双击可选中整行，**⌘A** 可全选识别结果。
3. 按 **回车 / ⌘C**，或右键选择 **复制文字**。底部显示「复制成功」，文字与玻璃底一起渐隐消失；截图和文字选区会保留，可重新选字、继续复制。再次选字时会恢复固定的「拖选文字」提示。完成后按 **Esc** 手动退出，再用 **⌘V** 粘贴。

再次点击文字按钮，或选择图钉、画笔等工具，可返回标注模式；已有标记会保留。文字模式中，左键用于选字、选区内右键打开复制菜单。可从选区外侧拖动边缘，或按空格拖动选区，松手后自动重新识别。保存 PNG 仍保存原截图与标注，不包含文字高亮。

识别使用 macOS 本机 Vision，支持中英文，不上传截图、不增加额外权限。模糊、过小或特殊字体可能识别不准，复制后请核对原文。

### 截图与标注

1. 按 **⌃⇧⌘5**：屏幕变暗，光标变为十字准星。
2. **按住左键拖选区域**，松开后出现标注工具栏。截图画面准备期间可按 Esc 取消。
3. 默认使用图钉模式：**点击打钉、左键拖框、右键拖箭头**。需要圆圈、直线或画笔时，从工具栏或快捷键切换。
4. 按 **Return / Enter** 或 **⌘C** 复制并结束截图，然后在聊天、文档等支持图片的应用中按 **⌘V** 粘贴。

默认复制到剪贴板，**不会自动保存文件**。需要 PNG 文件时，点击工具栏的保存图标，或按 **⌘S**；取消保存对话框会返回原选区，保留已有标注。按 **Esc** 可取消截图。

### 标注手势

以下前三项是在默认图钉模式（按 **N** 切回）下最常用的操作。按住鼠标即可直接拖动，无需等待长按计时。

| 想做什么 | 如何操作 |
| --- | --- |
| 添加编号图钉 | 在选区空白处左键单击，依次生成 1、2、3……；每张新截图从 1 开始 |
| 画圆角方框 | 在选区空白处按住左键拖动，生成细线、圆角、虚线矩形 |
| 画箭头 | 使用图钉或形状工具，在选区内按住右键拖动 |
| 画圆圈、矩形、直线或箭头 | 从滑杆图标菜单选择形状，再按住左键拖动 |
| 画笔 / 钢笔 | 按 P 使用已设定的画笔模式；长按工具图标可切换拖拽圆或贝塞尔钢笔 |
| 擦除 | 选择橡皮擦（E），按住左键涂抹；手绘笔触只擦去经过的部分，图钉和几何图形按整个对象擦除 |
| 删除图钉 | 移开后重新悬停图钉，点击出现的「−」；后面的图钉会自动重新编号 |
| 调整已有标注 | 使用图钉或形状工具，悬停后拖动端点或控制点；拖动标注本体可平移 |
| 调整截图范围 | 鼠标靠近选区边缘或四角后拖动；四角会显示当前标注颜色的柔光 |
| 平移截图范围 | 在选区内按住空格，再按住左键拖动 |
| 退出截图 | 按 Esc，或在选区外暗部右键单击；画笔模式下选区内右键仅结束当前绘制 |

选区采用圆角细白实线，四角悬停时显示贴合边界的柔光；直边也能拖动，但不显示彩色调整块。圆角仅用于编辑界面，导出的图片仍为完整矩形。调整截图范围时，工具栏和复制提示会跟随选区，已有标注保留在原画面位置，最终导出按新的选区裁剪。左键单击暗部不会清除选区，开始新的拖拽后才会替换。每个选区位于一块显示器内，支持在不同显示器上分别截图。

### 画笔模式

v1.1.8 提供两种可切换的画笔模式：

- **平滑手绘 · 拖拽圆（初始默认）**：选择画笔（P）后按住左键拖动小圆，牵引笔尖过滤手部抖动。松手保留平滑后的笔迹，不会突然延伸到鼠标位置。图标显示曲线与牵引圆。
- **钢笔 · 贝塞尔曲线**：再次点击或长按画笔按钮，或在滑杆菜单 → **画笔模式** 中切换；图标变为钢笔尖。使用小钢笔光标单击落点，按住左键拖动新点拉出方向手柄；准备下一点时显示淡虚线预览。靠近已有节点或手柄时高亮并变为空心箭头，按住左键可调整。绘制中点击起点可闭合（松开鼠标后生效），拖动起点只调整位置；可闭合时光标带小圆，并预览闭合段。
- **设置默认**：模式菜单每行右侧有「○ 默认」。点模式名称只切换本次绘制；点右侧圆圈会保存默认模式并立即切换，后续截图的画笔图标与绘制方式均使用该选择。
- **长按菜单**：按住画笔或「形状与设置」约四分之一秒展开菜单，保持按住并拖到选项，松开即可选择；普通点击仍然可用。
- **右键结束**：在选区内右键结束当前路径和编辑，保留截图；选区外暗部右键退出截图。完成后靠近曲线节点可再次编辑；单击首点或尾点后可继续绘制，拖动端点则移动端点。绘制过程中撤销 / 重做节点和手柄修改；完成后可整条撤销，续画也可一次撤回。
- 两种模式的线宽均比其他同档线条细 20%。回车 / ⌘C 可直接完成当前路径并复制截图，导出不包含手柄、牵引线或预览虚线。

两种模式使用较小的系统光标。锚点、手柄、牵引圆和辅助线只在编辑时显示，不会出现在复制或保存的图片里。橡皮擦、撤销和重做仍可使用。

### 工具栏

![工具栏：颜色、图钉、画笔、橡皮擦、提取文字、形状与设置、撤销、重做、保存 PNG](docs/toolbar.png)

从左到右是 **六种颜色 → 图钉 → 画笔 → 橡皮擦 → 提取文字 → 形状与设置 → 撤销 → 重做 → 保存 PNG**。按钮仅显示图标，鼠标停留可查看提示。普通标注模式中，下方显示 **「回车以复制到剪贴板」**；文字模式中显示 **「拖选文字 · ⌘A 全选 · 回车复制」**。

- 色板顺序为 **蓝、紫、白、橙、黄、绿**，默认使用蓝色；切换颜色只影响后续标注，并同步改变四角柔光。
- 滑杆图标菜单包含圆圈、方框、直线、箭头，以及线条 / 画笔粗细、画笔模式。圆角虚线方框固定使用细线。
- 复制图片时，下方提示保持不变，完成后结束截图。导出期间暂时锁定编辑，Esc 仍可取消，避免重复复制或丢失新画的标记。
- 界面跟随系统或应用语言设置，支持中文和英文。工具栏与复制提示使用 Metal 绘制偏黑的液态玻璃，沿圆角边缘呈现折射和高光；Metal 不可用时使用深色备用外观，开启「减少透明度」时使用不透明底色。上图为静态布局预览。

工具栏、选区边框、编辑控制点和删除按钮都不会进入导出的图片。

<details>
<summary>查看标注效果与二次编辑示例</summary>

![图钉、圆圈、圆角虚线框、直线与箭头的合成示例](docs/preview.png)

![编辑器中的图钉删除按钮与箭头端点](docs/editor.png)

以上均为合成画布，标记由应用的实际渲染代码绘制；编辑器预览使用静态工具栏底色。

</details>

## 快捷键

**⌃ = Control，⇧ = Shift，⌘ = Command。** 只有「开始截图」是全局快捷键，其余操作在截图编辑期间使用。

| 操作 | 快捷键 |
| --- | --- |
| 开始截图 | **⌃⇧⌘5** |
| 复制图片并结束截图（标注模式） | **Return / Enter** 或 **⌘C** |
| 复制所选文字并保留选区（文字模式） | **Return / Enter** 或 **⌘C** |
| 全选识别文字（文字模式） | **⌘A** |
| 保存 PNG | **⌘S** |
| 取消截图 | **Esc** |
| 图钉 / 默认手势 | **N** |
| 圆圈 / 椭圆 | **O** |
| 圆角矩形 | **B** |
| 直线 | **L** |
| 箭头 | **A** |
| 手绘画笔 | **P** |
| 橡皮擦 | **E** |
| 撤销 / 重做 | **⌘Z** / **⇧⌘Z** |
| 删除当前选中的标注 | **Delete / ⌫** |
| 平移选区 | **空格 + 左键拖动** |
| 绘制正圆、正方形，或水平 / 垂直的线与箭头 | **绘制时按住 Shift** |
| 重新选择区域并清空所有标注（无法撤销） | **R** |

## 常见问题

### 快捷键没有反应，或者打开了系统截图工具

1. 先确认 Nebula 的菜单栏图标还在；若已退出，从「应用程序」重新打开。
2. 点击菜单栏 → **区域截图**。如果能正常截图，进入 **设置 → 重新检测快捷键…** 查看注册结果；若提示被其他应用占用，退出或调整该应用后再次检测。
3. 如果出现 macOS 自带的截屏面板，检查 **系统设置 → 键盘 → 键盘快捷键 → 截屏** 中的冲突项。Nebula 使用的是 **Control + Shift + Command + 5**，请确认没有漏按 Control。

### 权限列表里没有 Nebula，或者已经允许却仍提示授权

先从菜单栏 → **设置 → 屏幕录制权限…** 发起系统请求。仍异常时，使用 **设置 → 重新授权屏幕录制…**；授权失败后，主菜单也会出现 **修复屏幕录制授权…**。这会重置 Nebula 自己的屏幕录制记录并重新请求授权，需要你再次允许。

恢复期间会立即显示简洁的进度提示，无需反复按快捷键；出现系统授权窗口时，应用的进度提示会让开。

若系统列表仍未更新，可在该权限页面点「＋」，选择安装在「应用程序」或 `~/Applications` 中的 **Nebula ScreenShot.app**，再按系统提示重新打开。

### 更新后是否需要重新授权

当前发行包采用临时签名，更新后 **可能需要重新允许屏幕录制**。升级时先退出旧版，再用新版覆盖原安装位置；不要同时运行下载目录和应用目录中的两份应用。遇到授权循环，可按上一项重新授权。

### 复制后找不到图片文件

默认输出在剪贴板，直接 **⌘V** 粘贴即可。需要磁盘文件时，用 **⌘S** 或工具栏保存图标选择 PNG 保存位置。

### 截图会上传吗

不会。截图、标注和文字识别均在本机处理，没有账号、云端上传或埋点；只有主动保存时才生成图片文件。复制后的图片由你自行粘贴到目标应用。

## v1.1.8 更新

- 新增拖拽圆平滑画笔与可编辑的贝塞尔钢笔：支持节点、方向手柄、下一段预览、闭合路径和首尾续画。
- 可分别选择当前画笔模式和保存默认模式；新截图会记住默认模式与工具图标。
- 画笔及形状设置支持长按展开菜单，拖到选项后松开即可选择；光标统一为更紧凑的钢笔与空心箭头。
- 笔画线宽减细 20%，活动笔迹独立绘制；保留局部擦除、撤销重做和干净导出，辅助线与控制点不会进入图片。
- 画笔模式下，选区内右键结束编辑，选区外右键退出截图；复制图片时提示保持不变，避免文字与玻璃背景闪换。

发布包为 **v1.1.8 / build 58**，支持 Apple Silicon 和 Intel。69 项核心测试、中英文编辑交互、默认设置与长按菜单、快捷键与连续截图均已检查，功能已通过本机桌面试用。构建结果见 [GitHub Actions](https://github.com/AnthemZhou/Nebula-ScreenShot/actions)，完整变更见 [CHANGELOG.md](CHANGELOG.md)。

## 开发

从源码构建需要 **Xcode 16+ / Swift 6**。工程使用 Swift Package Manager，仅依赖 macOS 系统框架；液态玻璃使用 Metal，不需要额外下载渲染依赖。

构建命令、测试、诊断日志与目录结构见 [开发与调试指南](docs/DEVELOPMENT.md)。参与贡献请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，手动验收见 [TESTING.md](TESTING.md)。遇到问题可 [提交 Issue](https://github.com/AnthemZhou/Nebula-ScreenShot/issues)，附上应用版本、macOS 版本和复现步骤。

<details>
<summary>English quick start</summary>

Requires macOS 14 or later. [Download v1.1.8](https://github.com/AnthemZhou/Nebula-ScreenShot/releases/download/v1.1.8/Nebula-ScreenShot-1.1.8-universal.zip), unzip, move **Nebula ScreenShot.app** to Applications, and open it. The Universal app supports Apple Silicon and Intel. This release is ad-hoc signed and not notarized; if macOS blocks it, follow [Apple’s opening instructions](https://support.apple.com/102445) after verifying its source.

Press **Control–Shift–Command–5** and allow screen recording when macOS asks. Follow any quit/reopen prompt; Nebula restores its menu-bar app and shortcut automatically. Press the shortcut again and drag a region. In the default pin mode, click to number points, left-drag a rounded rectangle, and right-drag an arrow. The slider menu contains shapes and stroke widths; pen, eraser, undo/redo and PNG save are on the toolbar. The palette is blue, purple, white, orange, yellow and green, with blue selected by default. Resize the crop from any edge or corner; the toolbar stays visible, and only the corners show a soft colored glow.

The pen tool offers **Smooth freehand · Pull circle** and **Pen · Bézier path**. Click/drag to place Bézier anchors and tangent handles, click the starting anchor to close, or drag existing anchors/handles to edit. Right-click inside the crop to finish the current pen path; click either endpoint of an open path to continue it. Right-click outside the crop to exit capture. Hold the pen or settings button, drag to an option, and release to select. The trailing **Default** radio saves a mode for future captures; choosing its title only changes the current mode.

Press **Return / Command–C** to copy the image and finish capture, **Command–S** to save PNG, or **Esc** to cancel. Canceling Save returns to the editor. To extract text, click the **Extract Text** icon beside the eraser, then drag across text, double-click a line, or press **Command–A**. **Return / Command–C** copies plain text and keeps the editor open for another selection. The success message and glass background fade together; press **Esc** when finished. Recognition runs on-device and starts only when you enable text mode. Screenshots stay on your Mac. An upgrade may require screen-recording consent again with the current ad-hoc releases.

</details>

## License

本项目采用 **GNU General Public License v3.0 only（GPL-3.0-only）**，完整协议见 [LICENSE](LICENSE)。

液态玻璃光学模型参考 MIT 许可的 Liquid Glass Engineering，来源和第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

Copyright © 2026 Nebula ScreenShot contributors.
