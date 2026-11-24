# Toolsmith mark

A hammer that reads as a T: the tool and the first letter of the name. One color, lavender (#C7B8FF, the palette's accent) on the dark ink ground.

`generate.py` draws everything from one path definition and renders it with `rsvg-convert` (`brew install librsvg`):

```bash
python3 design/brand/generate.py
```

`hammer/` holds:

- `mark.svg`: the mark alone, one color, 512 × 512.
- `icon.svg`: the app icon on the macOS 26 grid (1024 canvas, 824 rounded square at 100, corner 185).
- `AppIcon.appiconset/`: every size Xcode needs (16 to 512, @1x and @2x) and `Contents.json`; the app uses these (`App/Main/Assets.xcassets/AppIcon.appiconset`).
- `menubar.svg` and `menubar-16pt/18pt` PNGs (@1x, @2x): the menu bar template, black on transparent, tinted by macOS. The app uses `menubar.svg` as `AppMark` (`App/Main/Assets.xcassets/AppMark.imageset`).

After changing the mark, run the script and copy `hammer/AppIcon.appiconset/*.png` and `hammer/menubar.svg` (as `AppMark.svg`) into the asset catalog.
