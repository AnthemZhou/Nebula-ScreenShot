# 开发与调试

[返回 README](../README.md#开发)

以下内容面向从源码构建或参与开发的读者。直接使用应用请参阅 [安装与首次授权](../README.md#安装)。

## 从源码构建

需要 Xcode 16 或更新版本，以及 Swift 6 工具链。工程使用 Swift Package Manager，可直接用 Xcode 打开 `Package.swift`。只依赖 macOS 系统框架，包括 AppKit、ScreenCaptureKit、Carbon、ImageIO、Vision、CoreText 和 Metal。液态玻璃着色器随应用内嵌，在后台编译并复用截图纹理；Metal 不可用时保留深色备用外观，第三方算法许可见 `THIRD_PARTY_NOTICES.md`。

```sh
git clone https://github.com/AnthemZhou/Nebula-ScreenShot.git
cd Nebula-ScreenShot
swift test
./scripts/check-interactions.sh
bash scripts/check-text-recognition.sh
bash scripts/check-glass.sh
./scripts/check-sessions.sh
python3 scripts/check-exclusion.py
./scripts/check-relaunch.sh
bash scripts/check-permission-recovery.sh
./scripts/build.sh
open "dist/Nebula ScreenShot.app"
```

为保证系统权限归属于正确应用，实际截图请运行打包后的 `.app`，不要使用 `swift run` 请求屏幕权限。

`check-sessions.sh` 使用隐藏选区、合成图片和独立剪贴板验证连续截图与后台导出；快捷键测试临时使用未占用的 Control–Option–Shift–Command–F19/F18/F20，并仅向测试进程发送 Carbon 事件，结束后注销。不会截取真实桌面或修改系统快捷键设置。

## 打包

生成同时支持 Apple Silicon / Intel 的发布包：

```sh
./scripts/package.sh --universal
```

输出位于 `dist/`，包含 ZIP 和 SHA-256 校验文件。默认 ad-hoc 签名；可通过 `CODE_SIGN_IDENTITY` 指定自己的签名身份。本地开发应使用固定的 Apple Development 身份，以便跨构建保持 TCC 授权；面向用户的发行应使用 Developer ID Application。Developer ID 正式分发还需自行配置 hardened runtime、notarization 与 stapling；此脚本不宣称完成公证。

## 可选的本机开发签名

减少本机更新后的重复授权：在 Xcode → Settings → Accounts / Apple Accounts 登录 Apple 账户，进入 Manage Certificates，创建 Apple Development 证书。免费 Personal Team 可用于本机开发；账户和证书需要本人在 Xcode 中管理。随后使用：

```sh
python3 scripts/build-local.py --check
python3 scripts/build-local.py
```

这个入口会固定使用首次成功构建的证书，并校验每个架构的新版本满足上一次的签名要求；证书缺失、过期或身份变化时直接停止，不退回 ad-hoc。多个证书时，首次通过 `--identity` 指定 `security find-identity -v -p codesigning` 中的 SHA-1 指纹。公开的证书指纹与签名要求保存在本机 `~/Library/Application Support/Nebula ScreenShot/LocalSigning.json`，不导出私钥。构建结果保存在同目录下的 `LocalBuild/Nebula ScreenShot.app`，避开同步目录中的 Finder 元数据；需要覆盖到原先固定的应用目录。脚本本身不会安装、启动应用或重置权限。

从当前 ad-hoc 发行版首次切换到开发证书时，可能仍需授权一次；之后本机更新应持续使用此入口。再次安装 GitHub 的 ad-hoc 下载包会改变身份。本机开发签名不能代替公开发行的 Developer ID 签名与公证，也不保证系统自身的权限提醒永远不出现。正式跨版本桌面验收需要同一证书签署两个不同构建，先授权第一个，再覆盖升级第二个并确认快捷键截图无需再次授权。[Apple 对代码身份和授权的说明](https://developer.apple.com/forums/thread/819406)、[免费 Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

## 诊断日志

实际权限验证请从最终 ZIP 安装后，通过 Finder / `open` 启动 `.app`。直接运行包内二进制可能让权限归属启动它的终端或开发工具，不能据此判断应用本身是否获准。应用记录截图请求、选区就绪、一次性授权修复及错误 domain/code，不记录屏幕内容：

```sh
open "$HOME/Applications/Nebula ScreenShot.app" --args --capture
log show --last 5m --style compact --predicate 'subsystem == "io.github.anthemzhou.NebulaScreenShot" AND category == "Capture"'
```

`--capture` 在应用启动时直接开始一次截图；应用已运行时请使用快捷键。更新后若需命令行恢复，只重置此应用：`tccutil reset ScreenCapture io.github.anthemzhou.NebulaScreenShot`，然后重新启动并授权。

## 示例画布与预览

示例画布与可重现的渲染预览：

```sh
open "dist/Nebula ScreenShot.app" --args --demo
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-demo docs/preview.png
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-welcome docs/welcome.png
"dist/Nebula ScreenShot.app/Contents/MacOS/NebulaScreenShot" --render-toolbar docs/toolbar.png
```

## 目录结构

- `Sources/NebulaCore`：标注数据、事务式撤销/重做、坐标换算、预览与导出共用渲染器、元数据缓存和后台图片编码。
- `Sources/NebulaScreenShot`：菜单栏、快捷键、屏幕捕获、选区、工具条与引导窗口。
- `Tests/NebulaCoreTests`：编号及分支撤销、可调整选区几何、图钉比例与尖角、白色图钉边框与数字、编辑命中和重编号、局部擦除及下层像素保留、Retina 裁剪与导出位置、权限错误分类测试。
- `Tests/InteractionChecks`：实际 AppKit 控件的隐藏窗口手势回归与反复绘制检查；不捕获桌面、不注入系统输入、不写系统剪贴板。
- `Tests/SessionChecks`：快捷键注册与冲突恢复、连续截图取消、过期回调隔离、独立剪贴板导出及后台编码响应检查。
- `Tests/RelaunchChecks`：用独立测试父子进程验证退出状态、取消和超时，不请求屏幕权限、不启动真实截图应用。
- `Tests/TextRecognitionChecks`：真实中英文 Vision 识别、部分选字、取消和过期任务隔离、保留截图的重复文字复制与独立剪贴板检查。
- `Tests/PermissionRecoveryChecks`：授权恢复子进程的成功、失败、取消和超时，以及主线程响应和进度提示生命周期检查；不修改真实授权。
- `.github/workflows/build.yml`：macOS 核心、编辑器交互、截图会话、遮罩排除与重启测试，以及 Universal 构建和构建产物上传。

手动验收步骤见 [TESTING.md](../TESTING.md)。欢迎提交 Issue 与 Pull Request。
