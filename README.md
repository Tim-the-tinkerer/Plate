# Plate

A native macOS image editor. Open a photo, set exposure and color, crop it, mark it up, and save a new file.

**Version:** 1.3.0 (build 5)

The original is never overwritten. If the photo has unsaved edits, Plate asks before you open another one, paste, load the sample, close the window, or quit. Live preview downscales the long edge to 1600 px. Save and Copy render the full image, capped at 8192 px on the long edge.

## Edit

| Control | What it does |
|---|---|
| Exposure | Stops, −2 to +2 |
| Brightness, contrast | Lift and stretch around mid gray |
| Highlights, shadows | Bright areas and dark areas, separately |
| Saturation | −100 is gray |
| Temperature, tint | Warm/cool and green/magenta |
| Sharpness, vignette | Edge contrast and a corner falloff |
| Looks | Mono, sepia, warm, cool, fade, punch. They stack with the sliders |
| Crop | Free, original, 1:1, 3:2, 4:3, 16:9 |
| Straighten | A few degrees, from −45 to +45. The frame stays inside the photo, and the crop is that frame |
| Rotate, flip | Quarter-turns. A crop stays on the same pixels |
| Grade | One named set of the sliders and the look. The next photo starts there |
| Annotate | Pen, marker, line, arrow, box, oval, and text. Select a mark to move it, nudge it, duplicate it, reshape a line, arrow, box, or oval, change its width, or edit its text |

Hold **Original** to see the file you opened. Marks hide while you hold it, and they are painted into the picture when you Save or Copy. Undo keeps the last 50 edits.

The command line uses the same sliders, look, crop, turns, and straighten. It does not draw marks, it does not apply a saved grade, and it does not ask about unsaved edits.

## Saved files

Plate saves an 8-bit sRGB PNG or JPEG. The new file does not carry the original color profile, EXIF, IPTC, or GPS. A wide-gamut or HDR photo is written as ordinary sRGB, so colors outside sRGB are not kept.

Editing updates a preview whose long edge is at most 1600 pixels, so the controls stay light. Save and Copy render the full photo that Plate loaded, still capped at 8192 pixels on the long edge. One square RGBA buffer at that cap is about 256 MB, and a save briefly needs more than one of them.

## Keyboard

| | |
|---|---|
| ⌘O | Open |
| ⌘S | Save As |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘C | Copy the edited picture |
| ⌘V | Paste an image |
| ⌘K | Reset edits |
| ⌘L | Load the sample |
| ⌘] / ⌘[ | Rotate clockwise / counterclockwise |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Adjust / Crop / Looks / Annotate |
| ⌘⌫ | Delete the selected mark |
| ⌘D | Duplicate the selected mark |
| Arrow keys | Nudge the selected mark. Shift moves it farther |
| ⌘= / ⌘− | Zoom in / out |
| ⌘0 / ⌘9 | Fit / actual size |

Scroll zooms while the photo fits the window, and pans after you zoom in. Hold ⌘ or ⌥ while scrolling to keep zooming. Double-click the picture to jump between fit and actual size.

## Command line

```bash
Plate photo.jpg --exposure 0.3 --look warm -o print.jpg --jpeg
Plate photo.png --rotate 90 --crop 0.1,0.1,0.8,0.8
Plate --self-test
```

`--crop` is normalized and applied after `--rotate` and `--straighten`. `--straighten` is degrees clockwise, from −45 to 45, and the frame stays inside the photo. JPEG quality defaults to 0.92.

## Build

```bash
cd ~/Apps-Usefull/Plate
./build-app.sh
```

`./build-app.sh --no-launch` builds, runs the self-test, and skips opening the app.
