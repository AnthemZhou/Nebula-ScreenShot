# Contributing

欢迎提交问题和改进。报告问题时请提供 macOS 版本、CPU 架构、显示器缩放设置、复现步骤及预期结果。不要附上包含隐私的真实截图；优先用应用自带示例画布复现。

Before opening a pull request:

1. Keep changes focused and follow the existing Swift / AppKit style.
2. Run `swift test` and `./scripts/build.sh`.
3. Add regression coverage when changing numbering, history, geometry, or export behavior.
4. Check affected UI flows in [TESTING.md](TESTING.md).

Contributions are provided under the project's GPL-3.0-only license.
