# Changelog

## 0.1.5 — 2026-11-14

- Replace the two-row annotation panel with a compact, opaque dark toolbar and neutral icons.
- Keep four drawing groups in order: numbered pins, ellipse/rectangle, line, arrow; default to pins and remove freehand drawing.
- Add outlined rectangles, including Shift-constrained squares and Retina export.
- Move color/width controls into a style menu and secondary actions into More; keep undo, cancel and confirm directly accessible.
- Add actual toolbar rendering previews and rectangle export/history regression tests.
- Explicitly request initial screen recording consent once when needed and document manual addition in System Settings; keep ScreenCaptureKit as the actual capture-access check.

## 0.1.4 — 2026-11-14

- Fix the permission recovery loop after an ad-hoc signed update: add an explicit action that resets only Nebula's ScreenCapture record and relaunches the same installed app for fresh authorization.
- Attempt ScreenCaptureKit directly and classify its actual authorization error; unrelated capture failures retain their real error domain/code.
- Opening Screen Recording settings no longer issues a duplicate Core Graphics permission request.
- Prevent overlapping permission dialogs and add content-free capture lifecycle diagnostics.
- Add regression tests for NSError-based ScreenCaptureKit permission classification and document stable installation / code signing requirements.

## 0.1.3 — 2026-11-14

- Use a compact monochrome About window with a keyboard-accessible close button.
- Register the capture shortcut exclusively, validate event identities, and report actual registration results.
- Remove the fixed menu-dismissal delay from the shortcut capture path.

## 0.1.2 — 2026-11-14

- Reduce the About window to the app name, capture shortcut and bundle version in a compact centered layout.
- Move screen recording permissions, keyboard settings and shortcut checks to the menu bar Settings submenu.
- Show permission guidance only when attempting capture without access.
- Keep system-reservation diagnostics separate from registration errors; unavailable system data is no longer reported as a confirmed conflict.
- Add offscreen rendering of the actual About view for visual verification.

## 0.1.1 — 2026-11-14

- Change the global capture shortcut to Control–Shift–Command–5.
- Make “确认” the default editor action: clicking it or pressing Enter copies the annotated image to the clipboard and closes the editor. Command–C also copies; saving a PNG remains an explicit action.
- Update onboarding, menu labels, demo artwork and shortcut conflict guidance for the new shortcut.
- Sign and package in temporary staging directories to avoid synced-folder Finder metadata invalidating release builds.

## 0.1.0 — 2026-11-14

First preview release.

- Native macOS menu bar app with Control–Shift–Command–4 capture shortcut.
- ScreenCaptureKit region capture with Retina export and per-display selection.
- Ellipse, line, freehand, arrow and sequential numbered pin annotations.
- Ink colors, line widths, undo/redo, clear and reselect.
- PNG saving and PNG/TIFF clipboard copying.
- First-run screen recording and shortcut conflict guidance.
- Synthetic demo canvas, automated core tests and universal build workflow.
- GPL-3.0-only license.

Validation: core tests and interactive demo annotation/save/clipboard flows verified on Apple Silicon with macOS 26.5.2. Real desktop capture requires the user's screen recording permission. macOS 14, Intel hardware and multi-monitor runtime checks remain on the manual acceptance list. Release binaries are ad-hoc signed, not notarized.
