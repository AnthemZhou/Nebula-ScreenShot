# Manual acceptance checks

Run `swift test` first. Install the final ZIP in a fixed Applications directory and launch the `.app` through Finder or `open`, because screen recording permissions are associated with the signed app identity. Running the inner executable from a terminal can attribute the request to that terminal instead.

## Capture and permissions

- On first launch or via the menu bar About item, verify the compact window contains only the app name, shortcut and current bundle version in neutral black/white/gray. Check that text is centered and not clipped, and that the close button and Esc close the window without quitting.
- Use the menu bar Settings submenu to open screen recording settings, keyboard shortcut settings and shortcut detection. Report actual registration failures; an enabled system reservation alone must not be reported as a failed registration. The About window stays free of setup text.
- With screen recording denied, start capture. Expect the contextual permission dialog only after ScreenCaptureKit reports userDeclined; its settings action must only open Screen Recording settings, without another CGRequest call. No blank overlay or crash; repeated hotkeys must not stack permission dialogs.
- Grant permission through System Settings and relaunch if requested. Capture must proceed based on the actual ScreenCaptureKit result, without a separate Core Graphics preflight blocking it.
- After replacing an ad-hoc build whose old permission is still listed as enabled, use “重新授权屏幕录制…”. Cancel must have no side effects. Confirm must invoke only `tccutil reset ScreenCapture io.github.anthemzhou.NebulaScreenShot`, report failure if that command fails, and relaunch the same installed app after a successful reset. Grant permission to this version and verify a real desktop selection appears. Other applications' permissions must remain unchanged.
- A non-permission ScreenCaptureKit failure must show its actual error domain/code rather than instructing the user to toggle permission. Logs must contain lifecycle/error metadata only, never screenshots or window titles.
- Click “重新检测快捷键” and verify Control–Shift–Command–5 registers when available. Press it from another app; expect a frozen desktop with a crosshair, without opening About or adding a fixed menu-dismissal wait. Repeat while About is open. If the system screenshot panel still appears, adjust its binding; successful Carbon registration alone does not verify system shortcut precedence.
- With another app holding this exact shortcut exclusively, registration should fail honestly. Quit that app and retry; registration should recover. Repeated checks must not release an already registered shortcut.
- Begin from the menu bar. Drag a region in all four directions; a very small click should allow retrying.
- On a Retina screen, compare exported pixel dimensions with the selection indicator.
- On a second display, including one above or left of the main display, make a selection and inspect the export. Cross-display selections are intentionally unsupported.
- Unplug or change display resolution during capture. Expect cancellation without stranded overlays.
- Press Escape; focus should return to the previous app.

## Annotation and export

- Verify the toolbar is one dark opaque row with four drawing groups in this order: pin, ellipse/rectangle, line, arrow. A new capture defaults to pin. There is no pen tool or second instruction row.
- Use N, O, B, L, A to select each tool. Switch ellipse/rectangle using the shape dropdown, then draw both. Selecting the shape button later must restore the last chosen shape.
- Hold Shift while dragging an ellipse, rectangle, line, or arrow; verify circle / square / axis constraints.
- Open the style menu and choose each color and width. The current choices must be marked, including after a keyboard tool change. All menus must appear above the capture overlay and close cleanly when canceled; the overlay must retain its original window level afterwards.
- Use toolbar undo and the More menu for redo, clear, reselect and save. Verify their enabled states, then cancel with the cross or confirm with the checkmark. At narrow display widths, controls must remain inside the toolbar and accessible through their labels/tooltips.
- Select the pin tool and click three places. Expect 1, 2, 3 in circles at those locations.
- Undo the third pin; place another. Expect 3. Undo and redo mixed shapes and pins.
- Clear annotations, undo clear, and confirm the next number is restored.
- Try all colors and widths, including multi-digit pin numbers.
- Click “确认”, repeat with Enter, then with Command–C, and paste each result into Preview or another image-aware app. No save dialog should appear for confirmation. Confirm annotations are present, correctly oriented, and the toolbar / border are absent.
- Save a PNG. Cancel the save panel and verify the editable region is retained. Retry and save.
- R reselects; a new selection starts numbering from 1.
- A second capture starts numbering from 1 and ignores repeat hotkeys while already editing.

## Demo and distribution

- “试用标注” works without granting screen recording permission.
- `--render-demo` writes a synthetic sample PNG using the production renderer. `--render-welcome` and `--render-toolbar` render the actual views offscreen without capturing the desktop. Add `--compact` to the toolbar render to inspect its narrow layout.
- `scripts/package.sh --universal` produces both CPU architectures (`lipo -archs`).
- Check signing with `codesign --verify --deep --strict`. Ad-hoc signing does not imply Apple notarization.
- Smoke-test on an Intel Mac and macOS 14 before claiming those runtime configurations are verified; cross-compilation alone does not verify them.
