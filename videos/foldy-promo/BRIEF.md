---
workflow: product-launch-video
flow: automation
storyboard: no
message: "Your desktop bends as you close the lid."
destination: web-embed
aspect: 1920x1080
language: en
length: 30s
angle: promo
---

## Intent

A promo for Foldy, the macOS menu bar app that folds the live desktop back as a
bending, blurring sheet while the MacBook lid closes — the iPhone Duo fold, for the
MacBook you already have. Sell it, don't tour it: hook on the fold itself, then the
three styles, privacy (no account, no network code), and the download.

## Customizations

- Silent: no narration, no music, no SFX (`music: none`, no `SCRIPT.md`).

## Notes

- Source of truth: `../../README.md`, `../../site/index.html` (foldy.proteinunit.dev),
  real renders in `../../docs/` and `../../docs/snapshots/`.
- The overlay window cannot be screen-recorded (`sharingType = .none`); fold visuals
  come from the snapshot renders and the landing page's WebGL port of the shader.
- Destination: site, GitHub README, YouTube.
