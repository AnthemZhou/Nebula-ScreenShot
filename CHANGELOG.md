# Changelog

## 1.0.0 — 2026-11-14

- First stable release of the native macOS screenshot annotator, including numbered teardrop pins, editable shapes, freehand/local erasing, undo/redo, clipboard output and PNG saving.
- Remove the entry fade and its animation task. Show the capture interface with its final selection shade on the first frame; no additional animation delay.
- Update the editor interaction check to verify the initial shade is already final before any input or animation wait.

## 0.1.9 — 2026-11-14

- Remove the duplicate in-app screen-recording permission alert. Wait for native consent; further user retries open Settings without another app modal or an automatic capture loop.
- Track the installed code signature. After an existing installation changes ad-hoc identity and a real capture is denied, repair only Nebula’s ScreenCapture record once and relaunch into native-consent mode. Persist the claim before reset/relaunch; successful capture cancels it, and later denials of the same signature never auto-reset again. Fresh installations and certificate-signed builds skip automatic repair.
- Expose one-click permission repair in the main menu after a denial; remove the redundant repair confirmation. Relaunch directly into the native request instead of capturing first.
- Add regression coverage for first installs, legacy upgrades, stable certificates, success without reset, denial/relaunch loop prevention and native-only prompt actions.

## 0.1.8 — 2026-11-14

- Preload and reuse display-filter metadata when already authorized, capture fresh pixels concurrently across displays, and defer toolbar construction until a region is selected. Reduce the dim-only entry fade from 180 to 60 ms. Add metadata/pixel/panel timing diagnostics without logging screen content.
- Erase only the brushed portion of freehand strokes using per-stroke masks; keep the screenshot and lower annotations intact. Masks follow moved strokes, remain clipped to the crop used for erasing, and undo/redo with the whole gesture. Other annotation types retain object erasing.
- Change default pin-mode gestures to click-to-pin, left-drag rounded rectangles, and right-drag straight lines. Fix rounded dashed boxes at the thin 2 pt width.
- Keep all four original drawing groups and remove toolbar text labels. Center icons in square highlights, retain accessible names/tooltips, and render the pin button with the same colored teardrop and white outline/number as canvas pins.
- Add local-erase geometry, Retina compositing and history regressions; extend the hidden AppKit interaction checks for swapped gestures, partial erasing, icon button geometry and deferred toolbar construction.

## 0.1.7 — 2026-11-14

- Replace the per-repaint NSString hint drawing with a native, cached-label view. The v0.1.6 crash report identified this font-layout path as the cause of the app exiting and leaving its global shortcut unavailable.
- Add content-free hotkey registration/delivery logs; bring the app forward when explicitly requesting native screen recording consent, and clarify automatic first-use permission requests versus manual recovery and stable signing.
- Restyle pins as teardrops with white outlines and white numbers. Hover reveals a minus badge; deleting any pins renumbers the remainder, including through undo/redo.
- Add shape hover handles, draggable line/arrow endpoints, box/ellipse resizing, and whole-object movement.
- Draw rectangles with rounded corners and dashed borders.
- Add freehand pen and object eraser tools, with one history transaction per drag. Expose undo and redo directly in the toolbar.
- Add core editing/rendering tests and a checked-in hidden AppKit integration harness covering deletion, re-editing, erasing, clean export and 120 initial/selection redraw cycles. Run both suites in CI.

## 0.1.6 — 2026-11-14

- Use Dots orange (#EC603B) by default and put six color swatches at the front of the single-row toolbar. Keep Save PNG directly accessible.
- Scale numbered pins with the current crop, add an exact-position pointed tip, and keep edge pins inside the image with readable number contrast.
- Add click-to-pin, left-drag lines in pin mode, and right-drag rectangles. Commit on release to avoid stray pins; right-click the canvas to cancel.
- Resize the selection from any edge or eight handles, and Space-drag to move the crop while retaining annotations at their image positions.
- Present fixed, nonactivating capture panels with only a 180 ms dim-color fade; respect Reduce Motion and avoid activating or moving the underlying app on entry.
- Add geometry, pin rendering, Retina export and six-color contrast regression tests, plus refreshed toolbar/demo previews.

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
