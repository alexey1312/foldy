# Foldy — notes for coding agents

Foldy is a macOS menu bar app: the lid angle sensor (IOKit HID) drives a Metal
"fold" of the live desktop (ScreenCaptureKit) in a full-screen overlay. Swift 6,
SwiftPM only, no Xcode project. `README.md` is the user-facing description; this
file is what you need before changing anything.

## Commands

```bash
swift build                 # every target, debug
swift test                  # 12 Swift Testing cases in Tests/FoldyCoreTests
make app                    # Scripts/bundle.sh release → build/Foldy.app (ad-hoc signed)
Scripts/bundle.sh debug     # same, debug
make snapshot               # docs/snapshots/*.png via foldy-snapshot (no window needed)
make shots                  # the window images in docs/ and site/settings.png
make icon                   # Support/Foldy.icns from the preview scene
make video                  # videos/foldy-promo: fold media via foldy-snapshot, the MP4, its copy on the site (Node 22+, ffmpeg)
```

Check UI without a lid or a Screen Recording grant (each run captures its own
window and quits; Sparkle stays dormant and settings are not touched):

```bash
build/Foldy.app/Contents/MacOS/Foldy --screenshot-settings out.png --pane general --window-height 960 --scroll 500
build/Foldy.app/Contents/MacOS/Foldy --screenshot-onboarding out.png --step 2 --appearance dark
build/Foldy.app/Contents/MacOS/Foldy --screenshot-fold out.png      # real overlay, sample wallpaper
.build/debug/foldy-snapshot --out fold.png --progress 0.7 --style frost
```

`screencapture` and the Chrome extension cannot see the overlay window
(`sharingType = .none`); use the switches above.

A shell that is not itself frontmost cannot bring the app forward, so a screenshot
run pins SwiftUI's control state to `.key` (`screenshotControlState()`); without it
glass, switches and buttons all photograph dimmed. The traffic lights still render
grey — they are AppKit's and out of reach.

## Shape

- `Sources/FoldyCore` has no AppKit windows: sensor, capture, shaders, renderers,
  sample wallpaper, sound. `Sources/Foldy` is the app. `Sources/FoldySnapshot` is
  a CLI over the core. Keep that split; the snapshot tool and the tests rely on it.
- Settings is Foldy's own `NSWindow`, made in `AppController.openSettings`, not a
  SwiftUI `Settings` scene. The scene brought chrome we could not reach and never
  opened for a shell-launched process, so the screenshot switches saw a different
  window from the one users get.
- Building needs the macOS 26 SDK (Xcode 26+), CI included: `#available` gates the
  call, not the symbol, so the glass APIs must exist at compile time. The floor for
  running stays macOS 14.
- Liquid Glass lives behind `Views/LiquidGlass.swift`: `glassButtonStyle`,
  `glassBackground`, `glassMorphID`, `GlassGroup`. Each picks the macOS 26 API or
  the pre-Tahoe control, so no view needs an `#available` of its own. Glass goes on
  buttons, pills and the bar over the preview; cards, thumbnails and text stay flat.
- `AppController` (`@MainActor @Observable`, singleton) owns every decision:
  `evaluate()` re-reads angle, permission, pause/dismiss/sweep state and makes the
  overlay, the capture and the sound match. Add new behaviour there, not in views.
  The one exception is `FoldyCore/CapturePolicy.swift`, the pure state machine behind
  "capture now?" and "fold now?". It lives in the core because it is the only part of
  this that can be tested, and both bugs it guards against shipped unnoticed on a Mac
  with no lid. `AppController` is its only caller: add a condition there, with a test,
  not inline in `evaluate()`.
- Settings are persisted as one JSON blob through `FoldyCore/SettingsSnapshot.swift`,
  which decodes by hand. Synthesized `Decodable` ignores property defaults, so a new
  field makes an older blob throw and the `try?` in `SettingsStore` then resets every
  setting the user had. That shipped in 0.1.2. Add fields to `SettingsSnapshot`, keep
  `init(from:)` in step, and `SettingsSnapshotTests` holds the line.
- The Metal shaders live in `FoldShaders.swift` as a string, compiled at launch.
  That is deliberate: no resource bundle, no Metal build step, works from a hand-
  made app bundle. Keep `FoldUniforms`/`SceneUniforms` in Swift and MSL in sync
  field for field (floats and float4s only).
- `site/index.html` ports the fold shader to WebGL 2. If the fold changes in
  Metal, change it there too.
- The promo in `videos/foldy-promo` shows the fold only through clips that
  `Scripts/video-assets.sh` renders with `foldy-snapshot`. After a fold change, `make video`.
  The site plays `site/promo.mp4`, a copy: Pages publishes `site/` only, and the render in
  `renders/` was on no page at all until it was copied in. `make video` refreshes the copy
  and its poster; after a render made any other way, `make site-video`.
  Its `README.md` lists hand edits to `index.html` that re-running the HyperFrames
  assembler would undo.

## Rules that came from bugs

- Register `IOHIDManagerRegisterInputReportCallback` on the manager **before**
  `IOHIDManagerActivate`; a device-level registration after activation never fires.
  The sensor stays alive until the manager's cancel handler runs.
- ScreenCaptureKit sizes come from `CGDisplayCopyDisplayMode().pixelWidth`, not
  `CGDisplayPixelsWide` (points on Retina). `showsCursor` stays off.
- Screen Recording is granted to a fresh process only: after a grant, offer
  `AppController.relaunch()`; never assume capture works in the same process.
- The overlay shows at fold progress > 0.02 and hides only at 0, so a lid resting
  at the clear angle does not flicker.
- Capture stops after 4 s with nothing folded and then **parks**: it does not come back
  on the next movement, only when the lid closes 1.5° below where it parked (the park
  angle follows the lid up), when the fold is due, or on pause/sleep/display change.
  Without the park, `capture.stop()` → `.idle` → `evaluate()` → `start()` looped every
  four seconds and flashed the screen recording indicator for as long as the lid sat
  still. The idle timer must arm whenever the stream is running and nothing is folded —
  gating it on "capture wanted" left a lid resting between the bands streaming forever.
- An accessory app's window needs more than `NSApp.activate()` + `makeKeyAndOrderFront`
  to come up in front: `NSWindow.presentFront()` (`Views`-free, in
  `Foldy/WindowPresentation.swift`) raises it to `.floating`, orders it front
  regardless, and drops back to `.normal` on the next main-actor hop. Use it, and its
  `centerOnActiveScreen()`, rather than `center()`. Set the content size before
  `presentFront()`: the hosting controller can hand over a view it has not measured, and
  Settings opened from the menu was centred at zero size, then grew off the bottom right.
  The screenshot switches always passed a height and never showed it. Windows get a `WindowCloser`
  delegate too: both were kept alive after closing, and the Settings pane's previews
  keep redrawing at the sensor's report rate while they live.
- Errors go to `FoldyLog` (`os.Logger`, subsystem `app.foldy`) as well as to the status
  line. `log stream --predicate 'subsystem == "app.foldy"'`. The status line is only
  seen when the menu is open, which is not where a MacBook bug report comes from.
- Dev switches must never persist state: use `forcesSampleWallpaper`, not
  `settings.sampleWallpaper`, and guard any `settings` write a screenshot run can reach
  with `!DevFlags.isScreenshotRun` — `make shots` was parking the developer's own
  welcome tour at step 2.
- Never put `.tint(.clear)` on `.buttonStyle(.glass)`, whatever the migration guides
  say. On macOS the tint reaches the label too, so the title disappears in the window
  that has focus. `.glassProminent` ignores a tint outright, explicit `.tint(.accentColor)`
  included, and draws white in the light appearance: the same as plain `.glass` beside
  it. `Glass.tint` on `.regular` or `.clear` is a faint wash, and `.regular` glass over an
  accent capsule whitens it to pale cyan. The accent-coloured primary is therefore
  `ProminentGlassButtonStyle` in `LiquidGlass.swift`: `.clear.interactive()` glass over
  `Capsule().fill(.accentColor)`. Use `glassButtonStyle(.prominent)`; never reach for
  `.glassProminent` directly.
- A switch in a settings row is `SettingsToggleRow`, which gives the `Toggle` the row's
  title and hides it. `Toggle("", isOn:)` reads to VoiceOver as a nameless switch.
- Motion that is decoration goes through `decorativeAnimation(_:value:)`, which is off
  under Reduce Motion; the tour's slide and lid loop and the previews' easing
  (`MacBookPreviewView(immediate:)`) read the environment directly. The Metal preview
  following a drag is feedback, not decoration, and stays.
- `.navigationSplitViewColumnWidth` has to come after `.safeAreaInset` on the sidebar;
  the other way round the preference is swallowed and the column collapses.
- The split view hands itself a sidebar toggle. With no toolbar to hold it, it lands
  loose in the middle of the sidebar — `.toolbar(removing: .sidebarToggle)` on the
  sidebar content. With the toggle gone, a sidebar dragged shut had no way back, and
  `columnVisibility: .constant(.all)` does not stop the drag. `SidebarCollapseLock` holds
  the sidebar's `NSSplitViewItem.canCollapse` off, and watches it, because SwiftUI turns it
  back on after the window is built and on every pane change.
- `Scripts/bundle.sh`: the signing identity has spaces; it goes through the
  `sign` function, never an unquoted variable. Sparkle's XPC services,
  `Autoupdate` and `Updater.app` are signed before the framework, then the app.
- The user's shell aliases `cp` to `cp -i` and `rm` to `rm -i`; scripts use `command cp -f`
  and `command rm -f`, or a non-interactive run hangs on the prompt.

## Releases

- `git tag vX.Y.Z && git push origin vX.Y.Z` runs `.github/workflows/release.yml`:
  version stamped from the tag, tests, `bundle.sh release`, zip + DMG, GitHub
  Release. The release is created as a **draft** and only made public after the appcast
  is committed, so a run that dies half way leaves nothing users can install but never
  update from. `CFBundleVersion` is derived from the tag (0.1.5 → 105), not from the
  run number: Sparkle compares it first, and a run counter can reset or invert. With the signing secrets it signs with Developer ID, notarizes and
  staples; with `SPARKLE_PRIVATE_KEY` it also signs the zip, rewrites
  `site/appcast.xml` on `main` and triggers the Pages deploy (a GITHUB_TOKEN push
  starts no workflow by itself, hence `gh workflow run pages.yml`).
- The site and the Sparkle feed live on `https://foldy.proteinunit.dev/`
  (`site/CNAME` + Settings › Pages, Cloudflare DNS-only CNAME). `SUFeedURL`,
  the `--link` in `release.yml`, `site/CNAME` and `Links.site` in `AboutView.swift` must
  name the same host.
- To re-run a failed tag after a fix, move the tag: `git tag -d v && git push
  origin :refs/tags/v && git tag -a v && git push origin v`.
- Secrets are listed in README › Signing. Never print, commit or move them; the
  user sets them with `gh secret set`.
- Tagging publishes to real users. Ask before cutting a release.

## Unverified

This was built on a Mac mini. Reading the real lid sensor and the live
ScreenCaptureKit stream have not been observed on a MacBook; the HID layout
follows samhenrigold/LidAngleSensor. Treat any report from a laptop as the first
real test of those two paths.
