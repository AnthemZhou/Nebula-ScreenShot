# Changelog

## 1.1.9 — 2026-11-29

- Add a read-only `--login-item-status` diagnostic using Service Management directly, without invoking privileged system diagnostic tools, starting capture or changing login settings.
- Simplify the README with Chinese/English quick-start instructions and version, platform, architecture, license and build badges; retain detailed help in the user guide.

- Add Settings → Launch at Login, enabled once by default using macOS Service Management. Start in the background and register the capture shortcut before asynchronous login-item work, without opening the main window or requesting screen access at login.
- Read the system login-item state for the menu. Respect manual disable/removal in both Nebula and System Settings across launches and upgrades; native approval settings open only after an explicit click. Surface registration failures without pretending the option is enabled.
- Add isolated login-item checks covering first-run defaults, retained choices, failed registration/removal, responsive startup, stale reads and native login/service Apple events.

- Double-click a Bézier anchor to enter whole-path free transform. Drag inside the box to move, its eight handles to resize, or just outside to rotate. Shift constrains proportions; Command resizes around the movable pivot. Transform every anchor and tangent together, retaining closed paths and existing eraser masks.
- Keep each transform drag as one undo step. Return, Escape or an inside right-click leaves transform mode without closing capture; Escape during a drag discards that uncommitted gesture. Preserve single-node editing, endpoint continuation, single-click closure and clean image exports.
- Add affine geometry, transformed eraser pixel checks and real AppKit interaction coverage for double-click/closure conflicts, pivot transforms, undo/redo, keyboard isolation and returning to node editing.

## 1.1.8 — 2026-11-23

- Add two pen modes: pull-circle smooth freehand is the initial default; select cubic Bézier paths from the pen dropdown or Shapes and settings. Match the icon to the selected mode and reduce pen widths by 20%.
- Add separate trailing Default radio controls to pen mode rows. Persist the chosen default across captures/relaunches and show its toolbar glyph on the next capture; temporary mode selection does not overwrite it.
- Support holding the pen or settings toolbar button to open its native menu, drag over an option and release to select. Keep short-click behavior and route custom mode/default row releases independently, with duplicate suppression.
- Match nib, node and closure cursor canvases at 18 pt and slim their outlines and silhouettes.
- Click to place Bézier anchors, drag new anchors to create tangent handles, and drag existing anchors or handles to edit. Highlight nearby controls and show a faint dashed preview of the next segment. Right-click inside the crop ends drawing/editing without adding a segment or closing capture; right-click on the shade exits capture in every pen state; click either endpoint of a finished path to continue it. Preserve undo/redo for pending edits and completed continuations.
- Use a small native nib cursor for Bézier drawing and hollow arrow cursors for nodes/tangents. Indicate the precise closing target with a small ring and a tangent-aware forecast. Close on a click-and-release of the starting anchor; latch real drags so dragging away and back never closes a path. Preserve endpoint continuation after finishing a path and undo after resumed closure.
- Use a distance-based freehand tether with spatial substeps and no release-time catch-up. Replace the painted pen cursor with a small native cursor and update live ink/guides on a separate vector layer without implicit animation or full-canvas redraws. Keep guides out of exported images and preserve local erasing.
- Add geometry, continuation, preview, tangent editing, event-rate consistency, jitter suppression and real AppKit path/export regression checks.
- Keep the image-copy hint and its glass width unchanged while exporting, rather than switching to a progress caption. Preserve background encoding, input isolation and normal capture completion.

## 1.1.7 — 2026-11-23

- Add an opt-in Extract Text toolbar icon. Recognize only the selected crop with on-device Vision, select partial or multiple lines by dragging, double-click a line or use Command–A, then copy plain text with Return, Command–C or the context menu. Switch tools to resume annotation; text mode resets for each capture.
- Run recognition and image cropping off the main actor, cancel stale work after crop changes or mode/session exit, and reuse results for an unchanged crop. Keep text highlights out of image exports.
- Keep the screenshot editor open after text copy for repeated selection and copying. Show one localized success message in the lower row that fades without moving the toolbar; repeated copies renew it. Lighten unselected text tint and exclude selected regions from that tint to avoid stacked backgrounds. Image copy still ends capture after key release.
- Move the text-extraction hint up one display pixel and keep its instruction fixed during text selection. Fade the success message and its glass surface together; leave the row hidden until another selection or copy, without blocking pointer input in the hidden row.
- Keep permission recovery responsive with an asynchronous, cancellable reset subprocess and a bounded timeout. Show one compact nonactivating progress row immediately, with a slower-system message after six seconds; repeated shortcuts reuse it. Dismiss it before native consent to avoid duplicate permission UI.
- Add subprocess success, failure, cancellation, timeout and main-actor responsiveness checks, plus progress-panel focus, layout and lifecycle checks.

## 1.1.6 — 2026-11-22

- Render matching dark Liquid Glass for the toolbar and Return hint with Metal, adapting Liquid Glass Engineering's MIT-licensed optical model. Refract the frozen screenshot along rounded edges, add directional rim highlights and retain a charcoal body beneath sharp AppKit controls.
- Prewarm the GPU pipeline asynchronously after launch. Begin uploading one bounded backdrop texture at selection pointer-down, render only the two small rows when their geometry changes, coalesce pending requests and discard stale callbacks. No extra screen capture, continuous animation or main-thread GPU waits are introduced.
- Preserve control hit areas, text centering and existing spacing. Keep a dark fallback when Metal is unavailable and an opaque backing when Reduce Transparency is enabled. Bundle third-party notices with the app.
- Add real-GPU pixel, refraction, cancellation, foreground-visibility and timing checks alongside the existing repeated capture and shortcut checks.

## 1.1.5 — 2026-11-20

- Give the screenshot editor keyboard focus and route Return, keypad Enter and editing shortcuts at the panel level. Consume repeated confirmation keys during export and restore the previous app only after held keys are released, preventing input from reaching the underlying window.
- Keep every display covered during capture; shaded clicks remain in the editor. Switching apps cancels capture and prevents late export callbacks from restoring old overlays.
- Preserve the permission relaunch helper across Settings' consent quit, while respecting real shutdown and explicit quit. Register the global shortcut early at the Carbon dispatcher and retain requests received during launch so the first shortcut works without clicking the desktop.
- Keep exact crop geometry when releasing selections, resizing or moving. Shaded clicks and small pointer jitter preserve the existing crop; only a new drag replaces it. Keep the toolbar and copy hint visible and following the crop throughout adjustments.
- Use dark clear Liquid Glass with stable dimming and subtle rim reflections for the toolbar and Return hint. Center the 13 pt hint's rendered glyphs and refine the visible gaps, including fractional and Retina layouts.
- Default to blue and rotate the toolbar palette to blue, purple, white, coral, amber and mint. Changing ink affects new annotations and the corner glow.
- Replace open arrows with filled triangular heads and tapered shafts. Share the silhouette across preview, export, selection and erasing, retaining endpoint editing and undo/redo.
- Show resize feedback only at the four corners. A soft glow follows the rounded border in the selected ink, with rounded inner contours and a longer fade along the edges than into the crop. Keep straight edges draggable, clip glow away from the shaded desktop and exclude controls from exports.
- Retain annotation controls across a shape's interior and a forgiving stroke margin. Enlarge handle targets without letting their invisible margins steal nearby annotations; keep empty interiors available for drawing.
- Extend focus, held-key, repeated capture, permission relaunch, editing-hover and rendering regression checks. Update installation instructions, gestures and previews for build 43.

## 1.1.4 — 2026-11-16

- Composite the frozen desktop and rounded shade directly with Core Animation, drawing annotations in a separate crop-sized plane. Avoid full-screen bitmap redraws on entry and during selection; add separate panel setup, image-layer and presentation timings.
- Use one asynchronous ScreenCaptureKit consent request; remove the separate Core Graphics request path and concurrent Settings launch. Keep shortcuts waiting and the automatic relaunch watcher armed until access is confirmed. Perform a pending ad-hoc upgrade repair before the first dialog.
- Stop polling permission while the native consent dialog is active or handing off to Settings. Observe access when Settings closes/deactivates or the user retries capture, retaining the quit/reopen helper.
- Present the complete frozen desktop and shade together, eliminating the visible live-desktop-to-screenshot transition and its shadow change. Use macOS 26 direct region screenshots without metadata enumeration or application-layer exclusion; retain a display-filter fallback on macOS 14–15. Keep Escape available while preparing, releasing its temporary binding on success, error or cancellation.
- Use a thin, continuous white rounded crop outline without dashes, glow or a dark under-stroke. Keep resize hover emphasis and rectangular, undimmed exports.
- Keep compact pin delete badges clear of tiny pin numbers, let controls extend beyond the crop, and enlarge their invisible click margin without stealing pin-body drags. Keep badges on screen near display edges.
- Bias crop resize targets toward the shaded exterior, prioritize nearby annotation edits, and ignore sub-threshold pointer jitter. Tiny crop interiors remain available for drawing and pins.
- Replace the colorful app icon with a black rounded tile, white viewfinder and white teardrop pin; simplify the center detail at small icon sizes.
- Extend regression checks to 8–100 pt crops, pin deletion margins, edge/annotation conflicts, and 50 successful capture/copy cycles with editor and panel release checks.

## 1.1.3 — 2026-11-16

- Shrink the pin delete badge and attach it to the upper-right bubble edge, preserving stable hover, deletion and renumbering.
- Replace persistent crop handles with a subtle edge or corner highlight on hover and while resizing; retain all edge/corner drag targets.
- Remove pointer coordinates. Keep pixel dimensions anchored above the crop, without repainting the canvas during ordinary pointer motion.

## 1.1.2 — 2026-11-15

- Fix metadata-cache cancellation races during rapid Esc → capture cycles. Canceled waiters cannot invalidate a later capture, return stale display filters after a display change, or clear newer loading work.
- Encode clipboard PNG/TIFF and saved PNG data off the main actor, keeping the event loop responsive. Suppress duplicate exports and held-key repeats; canceled or stale completions cannot write to the clipboard or close another capture. Keep the editor available after an encoding failure.
- Close an outstanding save dialog when its capture ends, and clear Space-move mode when keyboard focus is lost. Avoid rebuilding unchanged annotation arrays for pointer hit tests.
- Release Carbon bindings and handlers with their owner. Add isolated checks for 100 shortcut deliveries, exclusive-registration conflict recovery, 100 rapid capture/cancel cycles, stale results/errors, export retries and background encoding. Keep the normal shortcut unchanged.

- Add a local Apple Development build path that pins the signing certificate and verifies each new build against the previous designated requirement on both architectures. Stop when the identity is missing or changed; never silently fall back to ad-hoc. Leave the installed app, screen-recording permission and public release packages untouched.
- Document the free Personal Team setup and the difference between local stable signing and Developer ID distribution. Actual permission-preserving upgrades require a development certificate and a two-build desktop acceptance check.

## 1.1.1 — 2026-11-15

- Give the pointer readout its own backing layer, disable position animations and reuse monospaced-digit measurements. Hover/readout updates use the latest pointer position and no longer repaint the screenshot unless editing controls actually change. Brush/eraser cursor redraws are limited to their old/new footprints.
- Increase the Return-to-copy hint from 11 to 14 pt; use subdued translucent light/dark ink according to the pixels beneath it. Keep Chinese/English language support and the centered placement.
- Increase toolbar tool glyphs from 18 to 19 pt and use native Liquid Glass on macOS 26 when built with Xcode 26 or newer; retain an in-window blur fallback on older systems/SDKs. Place controls inside the glass content view, preserving all gestures and export behavior.
- Check rapid coordinate updates, native-glass control containment, dark/light hint contrast and pending/export behavior. Offline preview images show control layout with a static neutral surface; live glass is composited by macOS.

## 1.1.0 — 2026-11-15

- Show an interactive translucent selection shade before capture metadata/pixels, then install fresh pixels into the same canvas without interrupting selection. Directly write pending alpha instead of blending a full-screen path, fixing a measured ~400 ms first-frame rasterization stall.
- Resolve Nebula's own application from current-process metadata when macOS omits it from the global shareable list. Never capture with a filter that could include the overlay; keep clipboard/PNG pixels undimmed.
- Use a thin neutral crop outline, smaller crosshair, and faint nearby coordinates without a background box.
- Consolidate ellipse, rounded rectangle, line, arrow and width into the slider menu. Remove reselect/clear entries, ellipsis, cancel and confirmation buttons. Center a Return-to-copy text hint below the icon row; keep Save PNG, undo and redo directly accessible.
- Change right-drag to draw arrows. Keep click-to-pin, left-drag thin rounded dashed rectangles, editing and local pen erasing.
- Stabilize pin deletion affordances: retain tracking areas across label movement, suppress a newly placed pin until the pointer leaves, and keep a continuous hover region through its delete badge.
- Follow system/per-app language preferences for Chinese or English interface text, menus, tooltips and messages.
- Extend hidden AppKit checks for hover stability, arrowheads, pending shade/crop alpha, undimmed export, uninterrupted image handoff and both editor languages. Add a no-permission current-process metadata regression fixture.

## 1.0.2 — 2026-11-15

- Fix a permission-relaunch race where LaunchServices briefly lists the exited parent as running, causing the helper to incorrectly report that macOS has already reopened the app.
- Exclude the exited parent and helper from replacement candidates, verify that the replacement PID is alive, and retry a stale launch result within a bounded handoff. Keep normal single-instance launching.
- Recognize the macOS Privacy & Security settings extension as a consent quit source, preserving the fallback helper when the system itself does not reopen the app.
- Add a regression check for the stale-parent result seen on the desktop and an isolated LaunchServices fixture that primes the app list before exit and verifies ten actual relaunches.

## 1.0.1 — 2026-11-14

- Automatically restore the app and capture hotkey after native screen-recording consent. Arm a temporary same-bundle helper before requesting consent, and restart once when access becomes available while the old process remains alive.
- Replace the shell/open-new-instance relaunch with LaunchServices, reusing an app already reopened by macOS. Helpers create no menu or hotkey, capture no pixels, and are bounded to the consent session.
- Cancel on successful capture, explicit quit, force quit, logout or timeout. Check clean process exit, current consent and a single-use handoff before reopening; never install a persistent launch agent.
- Add consent-transition and quit-policy tests plus native parent/child process checks for clean exit, force quit, cancellation and timeout; run them in CI.

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
