# Manual acceptance checks

Run `swift test` first. Launch the packaged `.app`, because screen recording permissions are associated with app identity.

## Capture and permissions

- On first launch or via the menu bar About item, verify the compact window contains only the app name, shortcut and current bundle version in neutral black/white/gray. Check that text is centered and not clipped, and that the close button and Esc close the window without quitting.
- Use the menu bar Settings submenu to open screen recording settings, keyboard shortcut settings and shortcut detection. Report actual registration failures; an enabled system reservation alone must not be reported as a failed registration. The About window stays free of setup text.
- With screen recording denied, start capture. Expect the contextual permission dialog; its settings action must open Screen Recording settings. No blank overlay or crash.
- Grant permission through System Settings and relaunch if requested. If the initial system permission request returns success, capture should continue without a second denial message.
- Click “重新检测快捷键” and verify Control–Shift–Command–5 registers when available. Press it from another app; expect a frozen desktop with a crosshair, without opening About or adding a fixed menu-dismissal wait. Repeat while About is open. If the system screenshot panel still appears, adjust its binding; successful Carbon registration alone does not verify system shortcut precedence.
- With another app holding this exact shortcut exclusively, registration should fail honestly. Quit that app and retry; registration should recover. Repeated checks must not release an already registered shortcut.
- Begin from the menu bar. Drag a region in all four directions; a very small click should allow retrying.
- On a Retina screen, compare exported pixel dimensions with the selection indicator.
- On a second display, including one above or left of the main display, make a selection and inspect the export. Cross-display selections are intentionally unsupported.
- Unplug or change display resolution during capture. Expect cancellation without stranded overlays.
- Press Escape; focus should return to the previous app.

## Annotation and export

- Use O, L, P, A, N to select each tool. Draw an ellipse, line, freehand stroke, and arrow.
- Hold Shift while dragging an ellipse, line, or arrow; verify circle / axis constraints.
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
- `--render-demo` writes a synthetic sample PNG using the production renderer. `--render-welcome` renders the actual About view offscreen without capturing the desktop.
- `scripts/package.sh --universal` produces both CPU architectures (`lipo -archs`).
- Check signing with `codesign --verify --deep --strict`. Ad-hoc signing does not imply Apple notarization.
- Smoke-test on an Intel Mac and macOS 14 before claiming those runtime configurations are verified; cross-compilation alone does not verify them.
