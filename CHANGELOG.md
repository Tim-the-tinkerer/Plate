# Changelog

## 1.3.0

- Straighten turns the photo by a few degrees. The frame stays inside the picture, and the crop is that frame.
- One named grade stores the sliders and the look. The next photo starts there. The command line does not apply it.
- Arrow keys nudge the selected mark. Duplicate copies it, and ⌘D does the same.

## 1.2.1

- Copy uses the full photo, the same render as Save, capped at 8192. The live preview stays at 1600.

## 1.2.0

- Opening another photo, pasting, closing, or quitting asks before discarding unsaved edits.
- A selected line, arrow, box, or oval can be reshaped. Its width can change, and a note can be edited.
- Saved files are 8-bit sRGB. The original profile, EXIF, IPTC, and GPS are not copied. A save of a very large photo can use several hundred megabytes.

## 1.1.0

- Annotate. Pen, marker, line, arrow, box, oval, and text on the photo.
- Marks follow rotate and flip, and they stay when the crop changes.
- Save and Copy paint the marks into the new picture. The original file is still never overwritten.

## 1.0.0

- First release. Exposure, color, crop, looks, undo, and save-as.
- The original file is never overwritten.
- Command line takes the same grade, crop, and quarter-turns as the window.
