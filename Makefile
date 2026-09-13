.PHONY: build app run test snapshot shots icon video-assets video site-video clean

build:
	swift build

app:
	Scripts/bundle.sh release

run: app
	open build/Foldy.app

test:
	swift test

snapshot:
	swift build --product foldy-snapshot
	mkdir -p docs/snapshots
	.build/debug/foldy-snapshot --out docs/snapshots/fold-silk.png --progress 0.7 --style silk --width 1200
	.build/debug/foldy-snapshot --out docs/snapshots/fold-shade.png --progress 0.7 --style shade --width 1200
	.build/debug/foldy-snapshot --out docs/snapshots/fold-frost.png --progress 0.7 --style frost --width 1200
	.build/debug/foldy-snapshot --out docs/snapshots/macbook-open.png --scene macbook --lid 135 --width 1200 --background white
	.build/debug/foldy-snapshot --out docs/snapshots/macbook-halfway.png --scene macbook --lid 60 --width 1200 --background white
	.build/debug/foldy-snapshot --out docs/snapshots/macbook-closing.png --scene macbook --lid 28 --style frost --width 1200 --background white

# The window images in README.md and on the site. Each run captures its own window
# and quits, so no lid, no Screen Recording grant and no clicking are needed.
shots: app
	build/Foldy.app/Contents/MacOS/Foldy --screenshot-settings docs/settings-general.png --pane general --appearance dark --window-height 820
	build/Foldy.app/Contents/MacOS/Foldy --screenshot-settings docs/settings-appearance.png --pane appearance --appearance dark --window-height 820
	build/Foldy.app/Contents/MacOS/Foldy --screenshot-onboarding docs/onboarding-capture.png --step 2 --appearance dark
	build/Foldy.app/Contents/MacOS/Foldy --screenshot-fold docs/fold-overlay.png
	command cp -f docs/settings-appearance.png site/settings.png

icon:
	Scripts/make-icon.sh

# The 30 s promo in videos/foldy-promo (HyperFrames). Needs Node 22+ and ffmpeg.
video-assets:
	Scripts/video-assets.sh

video: video-assets
	cd videos/foldy-promo && npx --yes hyperframes@0.8.36 check
	cd videos/foldy-promo && npx --yes hyperframes@0.8.36 render --quality high --output renders/video.mp4
	$(MAKE) site-video

# The site serves site/ and nothing else, so the render has to be copied in to be seen.
# The poster is the title shot at 8 s.
site-video:
	command cp -f videos/foldy-promo/renders/video.mp4 site/promo.mp4
	ffmpeg -v error -y -ss 8 -i site/promo.mp4 -frames:v 1 -q:v 4 site/promo-poster.jpg

clean:
	rm -rf .build build
