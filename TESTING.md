# Manual acceptance checks

Run `swift test` and `./scripts/check-interactions.sh` first. The interaction suite uses hidden windows and synthetic images; it does not request permission or send system input. Install the final ZIP in a fixed Applications directory and launch the `.app` through Finder or `open`, because screen recording permissions are associated with the signed app identity. Running the inner executable from a terminal can attribute the request to that terminal instead.

## Capture and permissions

- On first launch or via the menu bar About item, verify the compact window contains only the app name, shortcut and current bundle version in neutral black/white/gray. Check that text is centered and not clipped, and that the close button and Esc close the window without quitting.
- Use the menu bar Settings submenu to open screen recording settings, keyboard shortcut settings and shortcut detection. Report actual registration failures; an enabled system reservation alone must not be reported as a failed registration. The About window stays free of setup text.
- After a targeted permission reset, start capture. If ScreenCaptureKit reports userDeclined, expect an explicit OS consent request so Nebula appears in Screen Recording settings. Request consent at most once per process; opening settings afterwards must not duplicate that request. Opening settings before the first capture must also request initial consent. No blank overlay or crash; repeated hotkeys must not stack permission dialogs.
- Grant permission through System Settings and relaunch if requested. Capture must proceed based on the actual ScreenCaptureKit result, without a separate Core Graphics preflight blocking it.
- If the explicit consent request returns success, retry capture once. A subsequent ScreenCaptureKit denial must show recovery guidance instead of looping indefinitely.
- After replacing an ad-hoc build whose old permission is still listed as enabled, use “重新授权屏幕录制…”. Cancel must have no side effects. Confirm must invoke only `tccutil reset ScreenCapture io.github.anthemzhou.NebulaScreenShot`, report failure if that command fails, and relaunch the same installed app after a successful reset. Grant permission to this version and verify a real desktop selection appears. Other applications' permissions must remain unchanged.
- A non-permission ScreenCaptureKit failure must show its actual error domain/code rather than instructing the user to toggle permission. Logs must contain lifecycle/error metadata only, never screenshots or window titles.
- Click “重新检测快捷键” and verify Control–Shift–Command–5 registers when available. Press it from another app; expect a frozen desktop with a crosshair, without opening About or adding a fixed menu-dismissal wait. Repeat while About is open. If the system screenshot panel still appears, adjust its binding; successful Carbon registration alone does not verify system shortcut precedence.
- With another app holding this exact shortcut exclusively, registration should fail honestly. Quit that app and retry; registration should recover. Repeated checks must not release an already registered shortcut.
- Begin from the menu bar. Drag a region in all four directions; a very small click should allow retrying.
- On a Retina screen, compare exported pixel dimensions with the selection indicator.
- On a second display, including one above or left of the main display, make a selection and inspect the export. Cross-display selections are intentionally unsupported.
- Unplug or change display resolution during capture. Expect cancellation without stranded overlays.
- Enter from a hotkey while another app is in a full-screen Space: only the dark shade should fade in (180 ms), with no panel frame/alpha animation, Space switch or underlying window movement. Check Reduce Motion skips the fade.
- Before and after making a selection, right-click blank canvas or press Escape to cancel; focus should remain with or return to the previous app. Right-dragging outside the selection must not cancel. Right-clicks on the toolbar must not cancel.

## Annotation and export

- Verify the toolbar is one dark opaque row with tools in this order: pin, ellipse/rectangle, line, arrow, pen, eraser. Undo, redo and Save PNG are directly accessible; a new capture defaults to pin.
- Use N, O, B, L, A, P, E to select each tool. Switch ellipse/rectangle using the shape dropdown, then draw both. Selecting the shape button later must restore the last chosen shape.
- Hold Shift while dragging an ellipse, rectangle, line, or arrow; verify circle / square / axis constraints.
- Choose each of the six color dots at the front of the toolbar and each stroke width from the width menu. New annotations must use the selected color; earlier annotations keep theirs. The current choices must be marked, including after a keyboard tool change. All menus must appear above the capture overlay and close cleanly when canceled; the overlay must retain its original window level afterwards.
- Use primary toolbar undo, redo and Save PNG; use More for clear and reselect. Verify their enabled states, then cancel with the cross or confirm with the checkmark. At narrow display widths, controls must remain inside the toolbar and accessible through their labels/tooltips.
- Click three places. Expect 1, 2, 3 in teardrops with white borders/numbers and pointed tips at those exact locations. Default color is Dots orange (#EC603B).
- In pin mode, left-drag a line and right-drag a rectangle. No stray numbered pin may appear during or after either drag; a drag out and back to its start must not become a click. A drag delivered only by mouse-up must still work.
- Resize the crop from each of its eight handles and any edge. Keep the opposite edge fixed, clamp to the screen, and preserve every annotation and the next pin number. Shrink around a mark and expand again; it must reappear at its original location.
- Hold Space and drag inside the crop to move it, including near screen boundaries. Annotations stay attached to the source image, not the crop; export dimensions and origin must reflect the new selection.
- Compare small and large crops, multi-digit pins, and pins near every edge. Pins shrink with the short edge of the crop, their tip remains exact, their bubble fits inside, and pin size does not change with stroke width.
- Hover a pin, move onto its minus badge and click. The badge must remain reachable and later numbers must close the gap. Undo/redo restores the exact pins and their numbers; the next new pin continues the sequence.
- Hover a line/arrow to reveal two white endpoint controls; drag either endpoint or drag the shaft to move the entire object. Hover a box/ellipse to reveal size controls. Edits retain identity and consume only one undo transaction per drag. Press Delete after selection to remove it.
- Confirm rectangles have rounded corners, dash gaps and no fill. Their dash gaps should remain easy to select/edit.
- In pen mode, drag through several intermediate points and release; the exported stroke must follow the path. In eraser mode, drag across several objects and release; one undo restores every erased object and the original pin numbers. Empty erasing does not invalidate redo.
- Hover pins/shapes and export while the badge/handles are visible. UI controls must be absent from the output.
- Undo the third pin; place another. Expect 3. Undo and redo mixed shapes and pins.
- Clear annotations, undo clear, and confirm the next number is restored.
- Try all colors and widths, including multi-digit pin numbers.
- Click “确认”, repeat with Enter, then with Command–C, and paste each result into Preview or another image-aware app. No save dialog should appear for confirmation. Confirm annotations are present, correctly oriented, and the toolbar / border are absent.
- Save a PNG. Cancel the save panel and verify the editable region is retained. Retry and save.
- R reselects; a new selection starts numbering from 1.
- A second capture starts numbering from 1 and ignores repeat hotkeys while already editing. Repeat hotkey → initial hint → selection → cancel/copy several times; verify the menu bar app remains alive, especially after R reselects to the initial CJK hint. Check DiagnosticReports if it exits.

## Demo and distribution

- “试用标注” works without granting screen recording permission.
- `--render-demo` writes a synthetic sample PNG using the production renderer. `--render-welcome` and `--render-toolbar` render the actual views offscreen without capturing the desktop. Add `--compact` to the toolbar render to inspect its narrow layout.
- `scripts/package.sh --universal` produces both CPU architectures (`lipo -archs`).
- Check signing with `codesign --verify --deep --strict`. Ad-hoc signing does not imply Apple notarization.
- Smoke-test on an Intel Mac and macOS 14 before claiming those runtime configurations are verified; cross-compilation alone does not verify them.
