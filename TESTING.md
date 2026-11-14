# Manual acceptance checks

Run `swift test` first. Launch the packaged `.app`, because screen recording permissions are associated with app identity.

## Capture and permissions

- On first launch, verify the permission and shortcut guidance is readable.
- With screen recording denied, start capture. Expect permission guidance, no blank overlay or crash.
- Grant permission through System Settings and relaunch if requested.
- Click “重新检测” and verify Control–Shift–Command–5 registers when available. Press it from another app; expect a frozen desktop with a crosshair. If a conflicting custom system binding exists, expect guidance for that binding.
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
- `--render-demo` writes a synthetic sample PNG using the production renderer.
- `scripts/package.sh --universal` produces both CPU architectures (`lipo -archs`).
- Check signing with `codesign --verify --deep --strict`. Ad-hoc signing does not imply Apple notarization.
- Smoke-test on an Intel Mac and macOS 14 before claiming those runtime configurations are verified; cross-compilation alone does not verify them.
