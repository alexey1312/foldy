.PHONY: build app run test snapshot clean

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

clean:
	rm -rf .build build
