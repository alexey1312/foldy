# Foldy

**Your desktop bends as you close the lid.** · [foldy.proteinunit.dev](https://foldy.proteinunit.dev/)

The fluid fold from iPhone Duo, for the MacBook you already have. As the lid comes
down, Foldy captures the desktop and draws it back as a sheet that tilts, bends,
blurs toward the top and falls into shadow. When the lid comes up, the desktop
clears with a soft click.

Foldy is an open, from-scratch re-creation of [Bendy](https://trybendy.app/):
a menu bar app for macOS, written in Swift with SwiftUI, Metal, ScreenCaptureKit
and IOKit. No account, no license key, no network code.

| The fold on the real display | Settings, with the drag-to-open preview |
| --- | --- |
| ![The desktop folded over the lid](docs/fold-overlay.png) | ![Appearance settings](docs/settings-appearance.png) |

## What it does

- **Lid sensor.** Reads the hinge angle from the Mac's own HID sensor (vendor
  `0x05AC`, product `0x8104`, Sensor page, Orientation usage). It registers for
  input reports and keeps a heartbeat poll that runs at 60 Hz only while the lid
  is moving and drops to 10 Hz once it settles.
- **Live desktop.** Captures the built-in display with ScreenCaptureKit, excluding
  Foldy's own windows, and uploads each frame straight to a mipmapped Metal texture.
- **The fold.** A 64×64 grid tilts about the hinge and, with the *Bend* slider,
  curls like a page so the base stays put and only the top folds back. The
  fragment shader blurs by mip level toward the top edge, shades the top corners,
  feathers the silhouette and rounds the corners. Progress follows the lid on a
  smoothstep, then a per-frame lerp, so a jumpy sensor still gives a fluid fold.
- **Three styles.** Silk, Shade and Frost, each with Perspective, Variable blur,
  Shadow, Bend and Frost on sliders. Set the angle where the desktop clears and
  the angle where the fold completes.
- **Take a closer look.** Settings shows a 3D MacBook, rendered by the same
  Metal code as the overlay, whose lid you open and close with a drag — the
  interaction from Apple's iPhone Duo page, with Open / Halfway / Closed /
  Silk / Shade / Frost chips.
- **Sound.** A synthesised click when the lid opens and the desktop clears.
- **Menu bar.** Lives in the menu bar. Pause, Try It Now (folds the real desktop
  once, down and back up), Settings, Quit. Click the fold or press Esc to clear
  it until the lid opens again.
- **Updates.** Sparkle checks GitHub Releases once a day (switch it off in
  General). Each release is signed with an EdDSA key; the feed is
  `site/appcast.xml` on GitHub Pages, written by the release workflow.

## Requirements

- macOS 14 Sonoma or later.
- An Apple silicon MacBook with a lid angle sensor (MacBook Pro 2021 onward,
  MacBook Air M2 onward, or the 2019 16-inch MacBook Pro).
- Screen Recording permission, so the desktop can be captured. Without it Foldy
  folds a built-in sample wallpaper instead.

On a Mac without the sensor (a desktop, or an older laptop) everything except the
lid still works: the settings preview, the style thumbnails and *Try It Now*.

## Install

Grab `Foldy-x.y.z.dmg` or the zip from the
[releases page](https://github.com/alexey1312/foldy/releases) and drag Foldy to
Applications. The build is ad-hoc signed, not notarized, so macOS blocks the first
launch: open it once, then go to System Settings › Privacy & Security, scroll to the
message about Foldy and click **Open Anyway**. Or clear the quarantine flag first:

```bash
xattr -dr com.apple.quarantine /Applications/Foldy.app
```

The first launch opens a short welcome tour: it shows the lid sensor live, asks for
Screen Recording (macOS gives the permission to a fresh process only, so the tour
offers a relaunch and continues where it left off), lets you pick a style and try
the fold on the real display. Until Screen Recording is allowed Foldy folds a
sample wallpaper instead of the live desktop. The tour is always a click away:
menu bar › Welcome Tour….

Releases are cut by `.github/workflows/release.yml` from a `v*` tag; CI on every
push builds the package, runs the tests and bundles the app.

### Signing

Releases are ad-hoc signed until the repository has signing secrets. With them, the
workflow signs the app with a Developer ID (hardened runtime, timestamp), notarizes
it and the DMG, and staples both, so the download opens without any warning.

1. Join the Apple Developer Program and note the Team ID (Membership page).
2. Xcode › Settings › Accounts › Manage Certificates › + › **Developer ID Application**.
3. In Keychain Access export that certificate as a `.p12` with a password, then
   `base64 -i DeveloperID.p12 | pbcopy`.
4. App Store Connect › Users and Access › Integrations › App Store Connect API ›
   Team Keys › Generate (role Developer). Download the `.p8`, note the Key ID and
   the Issuer ID.
5. Repository › Settings › Secrets and variables › Actions:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | the base64 from step 3 |
| `MACOS_CERTIFICATE_PASSWORD` | the `.p12` password |
| `APPLE_TEAM_ID` | from step 1 |
| `APP_STORE_CONNECT_KEY_ID` | from step 4 |
| `APP_STORE_CONNECT_ISSUER_ID` | from step 4 |
| `APP_STORE_CONNECT_KEY` | the contents of the `.p8` file |
| `SPARKLE_PRIVATE_KEY` | the base64 EdDSA seed matching `SUPublicEDKey` (see Updates) |

Locally, `CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make app`
signs the same way; notarize with `xcrun notarytool` if you ship that build.

### Updates (Sparkle)

The app carries `SUFeedURL` and `SUPublicEDKey` in `Support/Info.plist`. With the
secret `SPARKLE_PRIVATE_KEY` set (the base64 seed that pairs with that public key),
the release workflow signs the zip, adds it to `site/appcast.xml`, commits the
appcast to `main` and redeploys Pages. Without the secret the release still ships,
but installed copies are not told about it.

To rotate the key: generate a new pair (`openssl genpkey -algorithm ED25519`, the seed
is the last 32 bytes of the PKCS#8 DER, the public key the last 32 bytes of the SPKI
DER, both base64), put the public half in `Info.plist` and the seed in the secret.
Sparkle's own `generate_keys` does the same and keeps the seed in the login keychain.

## Build and run

Xcode 16 or later with the macOS 14 SDK. Everything is a Swift package.

```bash
make app          # swift build -c release, then wraps build/Foldy.app (ad-hoc signed)
open build/Foldy.app
```

Other targets:

```bash
make test         # unit tests for the angle curve, the HID report parser, the styles
make snapshot     # renders the fold and the MacBook preview to docs/snapshots/*.png
swift build       # debug build of every target
```

You can also open `Package.swift` in Xcode and run the `Foldy` scheme, but the
bare binary has no bundle identifier, so macOS keys the Screen Recording grant to
the path and the app will fold the sample wallpaper until you allow it in
System Settings › Privacy & Security › Screen Recording.

Launch at login uses `SMAppService`, which only works from an app bundle.

### Command-line switches

Useful while developing; none are needed to use the app.

| Switch | What it does |
| --- | --- |
| `--settings [--pane general\|appearance\|about]` | Opens Settings at launch |
| `--screenshot-settings out.png [--window-height N] [--scroll N]` | Opens Settings, captures the window, quits |
| `--screenshot-fold out.png` | Folds the sample wallpaper on the real display, captures the overlay, quits |
| `--onboarding` | Opens the welcome tour at launch |
| `--screenshot-onboarding out.png [--step 0-4]` | Opens the tour at a step, captures the window, quits |

Screenshot runs keep Sparkle dormant and never touch the persisted settings.

`foldy-snapshot` renders without a window:

```bash
.build/debug/foldy-snapshot --out fold.png --progress 0.7 --style frost
.build/debug/foldy-snapshot --out mac.png --scene macbook --lid 60 --background white
.build/debug/foldy-snapshot --out mine.png --scene macbook --lid 45 --source ~/Desktop/shot.png
```

## Layout

```
Sources/FoldyCore       The parts that need no window.
  FoldParameters.swift    Styles, parameters, the angle → progress curve.
  LidAngleReport.swift    The HID report format and a table of Macs with and without a lid.
  LidAngleSensor.swift    IOHIDManager: input reports plus an adaptive heartbeat poll.
  DisplayCapture.swift    ScreenCaptureKit stream of the built-in display, excluding Foldy.
  FoldShaders.swift       The Metal shaders, compiled once at launch from source.
  FoldGraphics.swift      Device, pipelines, texture cache.
  FoldRenderer.swift      The fold: grid mesh, smoothing, frame upload, offscreen or on-screen.
  MacBookScene.swift      The 3D MacBook for the preview; the fold renders to its screen.
  WallpaperArt.swift      The sample lock screen, drawn with CoreGraphics.
  FoldSound.swift         The click, synthesised with AVAudioEngine.
Sources/Foldy           The menu bar app.
  FoldyApp.swift          The scenes, the app delegate, the command-line switches (DevFlags).
  AppController.swift     Sensor + capture + overlay + sound + permission, and the decisions between them.
  SettingsStore.swift     Persisted settings, coalesced into one UserDefaults write.
  OverlayWindowController.swift  The full-screen window; click or Esc dismisses.
  Updater.swift           Sparkle, dormant outside a bundle and in screenshot runs.
  Onboarding/             The welcome tour: five steps, resumes after a relaunch.
  Views/                  Settings panes, the drag-to-open slider, the Metal preview views.
Sources/FoldySnapshot   Renders PNGs of the fold and the preview.
Tests/FoldyCoreTests    Swift Testing suites.
Support/Info.plist      The app bundle's plist: LSUIElement, bundle id, Sparkle feed and key.
Support/Foldy.entitlements  Hardened runtime, nothing relaxed.
Support/Foldy.icns      The icon, rendered by Scripts/make-icon.sh from the preview scene.
Scripts/bundle.sh       Builds Foldy.app: embeds Sparkle.framework, signs nested code, then the app.
.github/workflows       ci (build, test, bundle), pages (site/), release (tag → signed,
                        notarized zip + DMG, appcast).
site/index.html         The landing page: the same fold in WebGL, scroll-driven, plus
                        the drag-to-open 3D lid. No build step, no dependencies.
site/appcast.xml        Sparkle feed, written by the release workflow.
```

## The landing page

`site/index.html` is a single file, published to GitHub Pages at
<https://foldy.proteinunit.dev/> by `.github/workflows/pages.yml` on every
push to `main`. It ports the Metal shader to WebGL 2, so the MacBook at the top of
the page bends as you scroll exactly the way the app bends the desktop, and the
"Take a closer look" section swings a CSS 3D lid on its hinge with the fold on its
screen. Open the file in a browser, or serve the folder.

The custom domain is `site/CNAME` plus the same name in Settings › Pages. DNS
lives at Cloudflare: `foldy` CNAME `alexey1312.github.io`, proxy **off** (grey
cloud) so GitHub can issue the certificate and `.dev`, which is HSTS-preloaded,
stays reachable. `alexey1312.github.io/foldy/` keeps 301-ing to the domain, which
is what carries Sparkle feeds baked into copies older than 0.1.5.

## Status

Built and checked on a Mac mini (M4 Pro, macOS 26.6, Xcode 27 beta) and on the
GitHub `macos-15` runner:

- `swift build`, `swift test` (12 tests) and `make app` pass on both.
- The renderer, the 3D preview, the settings window, the welcome tour and the
  full-screen overlay were exercised with the sample wallpaper: `--screenshot-fold`
  runs *Try It Now* on the real display and captures the result
  (`docs/fold-overlay.png`).
- Release 0.1.3 from the workflow verifies as `Notarized Developer ID` with
  `spctl`, and `stapler validate` passes for the app and the DMG.
- The Sparkle key pair was checked end to end: a signature from `sign_update`
  verifies against the `SUPublicEDKey` in `Info.plist`.

Not yet checked, because this machine has no lid and no Screen Recording grant:

- Reading the real sensor. The report layout (feature report 1, bytes 1–2,
  little-endian degrees) follows [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor),
  whose author tested it on an M4 MacBook Pro; that project's issues report some
  M1/M2 machines exposing the device on a vendor-specific usage page instead,
  which Foldy reports as "found but not readable".
- Whether the sensor pushes input reports. If it does not, the heartbeat poll
  carries the angle on its own.
- The live ScreenCaptureKit path on a granted machine.

## Credits

- Apple's [iPhone Duo](https://www.apple.com/iphone-duo/), for the fold and the
  "drag below to open and close" interaction.
- [Bendy](https://trybendy.app/) by Adrian Abelarde, the app that first put the
  fold on a MacBook lid. Foldy borrows its idea, its three style names and the
  shape of its landing page; the code is new.
- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) by Sam Henri
  Gold, for the HID details of the hinge sensor.
- [Sparkle](https://sparkle-project.org), for the updates.

MIT licensed. See `LICENSE`.
