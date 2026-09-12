---
format: 1920x1080
duration: 30s
message: "Your desktop bends as you close the lid."
arc: Future Pacing — spectacle hook → name product → mechanism (styles, real hinge) → outcome (private, free) → CTA
audience: Apple silicon MacBook owners who like their Mac to feel alive; indie Mac-app fans
mode: autonomous
music: none
---

# Foldy — 30 s silent promo

Silent: no narration, no music, no SFX. Every line the viewer reads is on-screen type, so each
frame's `onscreen:` field is the script and its cues pace the reveals the way a voiceover would.
Every image of the fold is a real Metal render from the app's own shader (`foldy-snapshot`), never
a CSS imitation.

## Video direction

- **Palette** (`frame.md`): ground `bg` #ECEDF2 with the site's ambient washes (soft blue top-left,
  peach top-right, teal bottom) as large blurred radial gradients; headlines `text` #0D0E12; secondary
  lines `text-muted` #5D6270; the ONE accent `primary` #0A84FF — only on the lid-angle readout, the
  slider, the active style pill and the Download pill. Frame 1 alone sits on pure black and hands
  over to the light ground at the Frame 2 transition.
- **Type**: the system SF stack from `frame.md` overrides. Display 600 at −0.02em for headlines;
  body 450–500 for secondary lines. Sentence case, no uppercase eyebrows, no italics.
- **Surfaces**: Liquid-Glass pills (white 55–72% fill, 1px white rim, backdrop blur) for labels and
  the CTA; no cards, no dashboards, no icons standing in for the product. The MacBook renders are
  transparent, so they sit straight on the ground with the site's soft `glow` shadow ellipse under
  the deck.
- **Motion grammar**: `power3.out` long-tail settles everywhere; text enters by a short rise
  (≈24px) + fade + slight blur-to-sharp; no bounce, no overshoot, no spring-pop. The Metal videos are
  the motion — type never moves while a lid is moving across it. Reveals are paced to the
  `onscreen:` cues and spread into the back half; nothing enters before its cue.
- **Media timing**: the `.webm`/`.mp4` clips are exactly 3.0 s / 2.5 s long. A clip's `data-duration`
  never exceeds its length; the matching end-state still (`macbook-closed-*.png`,
  `desktop-folded-silk.png`) takes over on the exact frame the clip ends, at identical position and
  scale, so the hand-off is invisible.
- **Rhythm / holds**: Frame 1 is fast and dark; Frame 2 builds; Frame 3 is the busiest (three
  surfaces); Frame 4 is one tight demo; **Frame 5 is the breather** (type only, long holds);
  Frame 6 settles and holds to the last frame.
- **Negative list**: no invented numbers (only 135°, 22°, macOS 14, Free); no fake UI chrome, no
  cursors except none at all; no bokeh, no purple AI gradients, no CSS-drawn laptops or fake folds;
  no lazy breathing, no slow back-half pan/push; no front-load-then-freeze; no `repeat`/`yoyo`,
  no `Math.random`, no CSS transitions. Keep the bottom ~17% clear of load-bearing content.

## Frame 1 — Close the lid

- scene: A full-bleed desktop tilts back and curls away into black while two short lines land
- voiceover: ""
- onscreen: "Close the lid." / "Watch the desktop bend."
- duration: 4.5s
- poster: 3s
- transition_in: cut
- status: animated
- src: compositions/frames/01-close-the-lid.html
- type: hook
- persuasion: Visual spectacle — show the impossible thing before naming it
- beat: curiosity + awe
- blueprint: kinetic-type-beats (Adapt)
- asset_candidates: assets/desktop-flat.png — the 9:41 desktop flat and sharp, first frame of the fold; assets/desktop-fold-silk.mp4 — full-bleed 9:41 desktop tilting and curling away into black, 2.5 s; assets/desktop-folded-silk.png — last frame of that fold, the sheet lying back over black
- focal: assets/desktop-fold-silk.mp4
- roles: desktop-fold-silk.mp4 = background (full-bleed, undimmed) · desktop-flat.png = background (pre-roll hold) · desktop-folded-silk.png = background (post-roll hold)

narrativeRole: Stops the scroll with the effect itself; the viewer sees a screen fold before knowing what it is.
keyMessage: Your screen can move with the lid.

Adapt: keep kinetic-type-beats' statement-builds-across-beats shape (two lines, each its own beat);
the "motion" between the beats is the real fold rather than a type trick.
Scene 1 (0.0–0.8s): black ground; `desktop-flat.png` fills the frame edge to edge (cover, anchored
bottom so the hinge edge stays on screen) — it reads as "your screen". "Close the lid." rises in
white display type, centered in the upper third, over a soft dark scrim behind the text only.
Scene 2 (0.8–3.3s): the text holds still while `desktop-fold-silk.mp4` plays in the same box: the
sheet tilts back, blurs toward the top and curls away into black — the signature beat.
Scene 3 (3.3–4.5s): `desktop-folded-silk.png` holds the folded sheet; in the black space the fold
opened above it, "Watch the desktop bend." rises in white display type at ~60% of the first line's
size, centered. Holds still to the cut.

## Frame 2 — Meet Foldy

- scene: On the light ground a 3D MacBook closes its lid and the desktop bends; the Foldy wordmark and the tagline build beside it
- voiceover: ""
- onscreen: "Foldy" / "Your desktop bends as you close the lid." / "The fluid fold from iPhone Duo — for the MacBook you already have."
- duration: 6s
- poster: 4.5s
- transition_in: blur-crossfade
- status: animated
- src: compositions/frames/02-meet-foldy.html
- type: product_intro
- persuasion: Future pacing — the iPhone Duo fold, on hardware you already own
- beat: clarity + desire
- blueprint: video-text-pivot (Adapt)
- asset_candidates: assets/macbook-open-silk.png — transparent MacBook fully open, flat desktop; assets/macbook-close-silk.webm — transparent 3D MacBook closing 135°→22°, desktop bending (Silk), 3 s; assets/macbook-closed-silk.png — transparent MacBook at 22°, last frame of the close
- focal: assets/macbook-close-silk.webm
- roles: macbook-close-silk.webm = cutout · macbook-open-silk.png = cutout (pre-roll hold) · macbook-closed-silk.png = cutout (post-roll hold)

narrativeRole: Names the product and lands the promise (the brief's message) by beat 2.
keyMessage: Foldy makes the desktop bend with the lid — on your current MacBook.

Adapt: keep the signature weight-transfer — the product video slides aside into the space the text
then owns; the "hero stat" becomes the wordmark + tagline, and the closing pill stamps the iPhone
Duo line. No typing effect (off-brand for Apple-calm type); lines rise instead.
Scene 1 (0.0–0.7s): light ground with ambient washes; `macbook-open-silk.png` centered, ~62% of
frame width, soft glow shadow under the deck. "Foldy" fades up small above it. Still.
Scene 2 (0.7–1.5s): the signature yield, done on the still (a hoisted video cannot be transformed):
the open-MacBook still glides left + scales down to its final box — ~46% of frame width, centre at
~31% x — on one `power3.inOut` move, its shadow travelling with it, while "Foldy" travels to the right
column and grows into the h1 wordmark.
Scene 3 (1.5–4.5s): `macbook-close-silk.webm` plays in the still's FINAL box (identical geometry, so
the swap is invisible): lid comes down, desktop bends. At 2.3s "Your desktop bends as you close the
lid." rises beneath the wordmark (h2, text colour), left-aligned in the right column (asymmetric
45/55, 3 depth layers: washes, MacBook + shadow, type).
Scene 4 (4.5–6.0s): `macbook-closed-silk.png` holds the closed pose in the same box. At 4.6s a glass pill scales open
on X under the tagline carrying "The fluid fold from iPhone Duo — for the MacBook you already have."
(body, text-muted). Holds still to the cut.

## Frame 3 — Three styles

- scene: Three MacBooks close side by side, each folding its desktop differently; a glass pill names each one
- voiceover: ""
- onscreen: "Three styles." / "Silk" / "Shade" / "Frost" / "Perspective, blur, shadow and bend — on sliders."
- duration: 6s
- poster: 4.2s
- transition_in: crossfade
- status: animated
- src: compositions/frames/03-three-styles.html
- type: feature_showcase
- persuasion: Rule of three — choice without complexity
- beat: delight + control
- blueprint: grid-card-assemble (Adapt)
- asset_candidates: assets/macbook-open-silk.png — transparent MacBook fully open, flat desktop (all three styles look identical when open); assets/macbook-close-silk.webm — transparent MacBook closing, Silk fold, 3 s; assets/macbook-close-shade.webm — transparent MacBook closing, Shade fold, 3 s; assets/macbook-close-frost.webm — transparent MacBook closing, Frost fold with heavy top blur, 3 s; assets/macbook-closed-silk.png — Silk end state; assets/macbook-closed-shade.png — Shade end state; assets/macbook-closed-frost.png — Frost end state
- focal: the three close videos as one triptych
- roles: macbook-close-*.webm = cutout ×3 · macbook-open-silk.png = cutout pre-roll ×3 · macbook-closed-*.png = cutout post-roll ×3

narrativeRole: Evidence that the fold is crafted and yours to tune.
keyMessage: Pick the fold that suits you.

Adapt: keep the staggered self-assemble into a row, but the items are three live devices, and each
arrival is followed by its own fold so the difference between styles is seen, not listed.
Scene 1 (0.0–0.9s): "Three styles." rises, centered, upper band (h2). Ground only below it.
Scene 2 (0.9–1.8s): three `macbook-open-silk.png` stills assemble into a triptych row (each ~30% of
frame width, even gutters, centred vertically ~55% down) — a left-to-right stagger of short rises.
Scene 3 (1.8–4.8s): the three close videos start together in place of the stills (same boxes) —
Silk left, Shade centre, Frost right; each glass label pill fades up under its device as its lid
passes halfway: "Silk" at 2.6s, "Shade" at 2.9s, "Frost" at 3.2s. The Frost pill is the active one
(accent-filled text) only after all three are in, at 3.6s, so the eye compares before it lands.
Scene 4 (4.8–6.0s): the three `macbook-closed-*.png` stills hold. "Perspective, blur, shadow and
bend — on sliders." rises under the row (body, text-muted), still to the cut.

## Frame 4 — Follows the hinge

- scene: A glass lid-angle slider scrubs 135° down to 22° in lock-step with a MacBook closing, then the lid lifts and the desktop clears
- voiceover: ""
- onscreen: "Reads the real hinge angle." / "135°" → "22°" / "Lid up — the desktop clears."
- duration: 5s
- poster: 2.6s
- transition_in: crossfade
- status: animated
- src: compositions/frames/04-follows-the-hinge.html
- type: feature_showcase
- persuasion: Show-don't-tell proof — the number and the picture move together
- beat: confidence
- blueprint: panel-edit-live-sync (Adapt)
- asset_candidates: assets/macbook-close-silk.webm — transparent MacBook closing 135°→22° on a cosine ease, 3 s; assets/macbook-open-silk.webm — the same shot reversed, lid opening and desktop clearing, 3 s; assets/macbook-open-silk.png — MacBook fully open, pre-roll
- focal: assets/macbook-close-silk.webm
- roles: macbook-close-silk.webm = cutout · macbook-open-silk.webm = cutout · macbook-open-silk.png = cutout (pre-roll hold)

narrativeRole: Explains the mechanism in one glance — the Mac's own lid sensor drives the fold, and opening clears it.
keyMessage: It follows your lid, and gets out of the way when you open it.

Adapt: keep the live-sync couple (`control-target-sync`) — the control and its bound surface change
in the same beat; the control is Foldy's own lid bar (glass track, blue knob, "135°" readout) from
its Settings window, rebuilt in HTML; the target is the real Metal render. No cursor.
Scene 1 (0.0–0.5s): `macbook-open-silk.png` centered, ~56% of frame width, upper-middle. Headline
"Reads the real hinge angle." (h2) sits top-centre. Below the MacBook, a glass lid bar (≈900px wide
pill: blue fill track, blue circular knob at the right end, readout "135°" in display 600 with
tabular numerals, accent colour) rises into place.
Scene 2 (0.5–3.5s): `macbook-close-silk.webm` plays (same box). In lock-step, over exactly the same
3.0s and the same cosine ease-in-out (`sine.inOut`), the knob and fill travel from 135° to 22° of a
0–135° track and the readout counts 135 → 22 as integers. This is the signature couple.
Scene 3 (3.5–5.0s): `macbook-open-silk.webm` plays from its start for the remaining 1.5s (lid rises,
desktop straightens and clears); knob and readout run back up in lock-step on the same ease over the
same clip time (22 → ≈78°, i.e. the angle the clip shows at 1.5s: 22 + 113·(1−cos(π·0.5))/2). At
3.8s "Lid up — the desktop clears." replaces the headline with a velocity-matched upward cut.
Holds on the last frame.

## Frame 5 — Private by design

- scene: Three short statements relay one at a time on the light ground, sealed by a glass pill
- voiceover: ""
- onscreen: "No account." / "No license key." / "No network code." / "Every frame stays on your Mac."
- duration: 4.5s
- poster: 3.9s
- transition_in: crossfade
- status: animated
- src: compositions/frames/05-private-by-design.html
- type: benefit_highlight
- persuasion: Risk reversal — nothing to sign up for, nothing leaves the machine
- beat: trust + peace of mind
- blueprint: kinetic-type-beats (Reproduce — slow relay of 3 statements onto a payoff)
- asset_candidates:
- focal: typography
- roles: none — type-only breather

narrativeRole: Removes the last objection to installing a screen-capturing app.
keyMessage: It is private and has no strings attached.

Scene 1 (0.0–1.0s): ground with ambient washes only; "No account." rises into the centre (h1).
Scene 2 (1.0–2.0s): "No account." lifts up and dims to text-muted as "No license key." rises into
the centre — a velocity-matched waterfall cut (both moving up at matched speed).
Scene 3 (2.0–3.0s): the same relay: "No license key." lifts and dims, "No network code." takes the
centre. The three lines now stack as a quiet left-aligned-to-centre column, newest darkest.
Scene 4 (3.0–4.5s): a glass pill scales open on X beneath the stack with "Every frame stays on your
Mac." (body, text colour). The breather: holds completely still to the cut.

## Frame 6 — Download Foldy

- scene: The open MacBook settles center, the wordmark and a blue "Download Foldy · Free" pill land beneath, the site URL holds
- voiceover: ""
- onscreen: "Foldy" / "Download Foldy · Free" / "foldy.proteinunit.dev" / "macOS 14+ · Apple silicon MacBook"
- duration: 4.5s
- poster: 3.8s
- transition_in: blur-crossfade
- status: animated
- src: compositions/frames/06-download-foldy.html
- type: cta
- persuasion: Friction reduction — free, one download, one URL
- beat: motivation
- blueprint: cta-morph-press (Adapt)
- asset_candidates: assets/macbook-open-silk.png — transparent MacBook fully open, flat sharp desktop
- focal: assets/macbook-open-silk.png
- roles: macbook-open-silk.png = cutout

narrativeRole: Converts interest into a download and names where to get it.
keyMessage: It's free — get it at foldy.proteinunit.dev.

Adapt: keep the signature condense — the wordmark condenses at one centre into the CTA pill; drop the
cursor and click (the viewer can't click a video; a fake cursor is on the negative list).
Scene 1 (0.0–1.2s): `macbook-open-silk.png` rises a short distance into the upper-middle, ~44% of
frame width, glow shadow under the deck; "Foldy" (h1) rises beneath it.
Scene 2 (1.2–2.2s): "Foldy" condenses at its own centre into the accent CTA pill "Download Foldy ·
Free" (the pill: primary #0A84FF fill, white label, "Free" in a lighter inner glass chip, as on the
site) — shrink-fade of the word exactly as the pill scales up from the same origin.
Scene 3 (2.2–3.0s): "foldy.proteinunit.dev" rises beneath the pill (h3, text colour); a beat later
"macOS 14+ · Apple silicon MacBook" (body, text-muted) beneath it.
Scene 4 (3.0–4.5s): the pill's glass sheen travels across it once (`ambient-glow-bloom`, single
pass); then everything holds still to the final frame. Final frame of the film.
