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
- Liquid Glass lives behind `Views/LiquidGlass.swift`: `glassButtonStyle`,
  `glassBackground`, `glassMorphID`, `GlassGroup`. Each picks the macOS 26 API or
  the pre-Tahoe control, so no view needs an `#available` of its own. Glass goes on
  buttons, pills and the bar over the preview; cards, thumbnails and text stay flat.
- `AppController` (`@MainActor @Observable`, singleton) owns every decision:
  `evaluate()` re-reads angle, permission, pause/dismiss/sweep state and makes the
  overlay, the capture and the sound match. Add new behaviour there, not in views.
- The Metal shaders live in `FoldShaders.swift` as a string, compiled at launch.
  That is deliberate: no resource bundle, no Metal build step, works from a hand-
  made app bundle. Keep `FoldUniforms`/`SceneUniforms` in Swift and MSL in sync
  field for field (floats and float4s only).
- `site/index.html` ports the fold shader to WebGL 2. If the fold changes in
  Metal, change it there too.

## Rules that came from bugs

- Register `IOHIDManagerRegisterInputReportCallback` on the manager **before**
  `IOHIDManagerActivate`; a device-level registration after activation never fires.
  The sensor stays alive until the manager's cancel handler runs.
- ScreenCaptureKit sizes come from `CGDisplayCopyDisplayMode().pixelWidth`, not
  `CGDisplayPixelsWide` (points on Retina). `showsCursor` stays off.
- Screen Recording is granted to a fresh process only: after a grant, offer
  `AppController.relaunch()`; never assume capture works in the same process.
- The overlay shows at fold progress > 0.02 and hides only at 0, so a lid resting
  at the clear angle does not flicker. Capture stops after 4 s of a flat fold.
- Dev switches must never persist state: use `forcesSampleWallpaper`, not
  `settings.sampleWallpaper`.
- Never put `.tint(.clear)` on `.buttonStyle(.glass)`, whatever the migration guides
  say. On macOS the tint reaches the label too, so the title disappears in the window
  that has focus. `.glassProminent` ignores a tint outright.
- `.navigationSplitViewColumnWidth` has to come after `.safeAreaInset` on the sidebar;
  the other way round the preference is swallowed and the column collapses.
- The split view hands itself a sidebar toggle. With no toolbar to hold it, it lands
  loose in the middle of the sidebar — `.toolbar(removing: .sidebarToggle)` on the
  sidebar content.
- `Scripts/bundle.sh`: the signing identity has spaces; it goes through the
  `sign` function, never an unquoted variable. Sparkle's XPC services,
  `Autoupdate` and `Updater.app` are signed before the framework, then the app.
- The user's shell aliases `cp` to `cp -i`; scripts use `command cp -f`.

## Releases

- `git tag vX.Y.Z && git push origin vX.Y.Z` runs `.github/workflows/release.yml`:
  version stamped from the tag, tests, `bundle.sh release`, zip + DMG, GitHub
  Release. With the signing secrets it signs with Developer ID, notarizes and
  staples; with `SPARKLE_PRIVATE_KEY` it also signs the zip, rewrites
  `site/appcast.xml` on `main` and triggers the Pages deploy (a GITHUB_TOKEN push
  starts no workflow by itself, hence `gh workflow run pages.yml`).
- The site and the Sparkle feed live on `https://foldy.proteinunit.dev/`
  (`site/CNAME` + Settings › Pages, Cloudflare DNS-only CNAME). `SUFeedURL`,
  the `--link` in `release.yml` and `site/CNAME` must name the same host.
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
