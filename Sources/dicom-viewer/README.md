# dicom-viewer

Terminal-based DICOM image viewer for quick inspection and triage.

## Overview

`dicom-viewer` displays DICOM images directly in the terminal using various rendering methods including ASCII art, ANSI colors, and terminal graphics protocols (iTerm2, Kitty, Sixel). This enables rapid image inspection without launching a full GUI viewer.

## Features

- **ASCII Art Rendering**: Convert images to ASCII characters (low and high quality)
- **ANSI Color Rendering**: Use 256-color or 24-bit true color terminal support
- **iTerm2 Inline Images**: Native image display in iTerm2 terminal
- **Kitty Graphics Protocol**: High-quality rendering in Kitty terminal
- **Sixel Graphics**: Sixel protocol support for compatible terminals
- **Window/Level Control**: Custom windowing for optimal contrast
- **Multi-frame Navigation**: View specific frames from multi-frame images
- **Thumbnail Grid**: Display multiple files or frames as a grid
- **Information Overlay**: Show patient and study metadata
- **Image Inversion**: Invert pixel values for better visibility (MONOCHROME1 images are already shown with the minimum as white, PS3.3 C.7.6.3.1.2)
- **CodecRegistry Integration**: All registered codecs (J2K, HTJ2K, Part 2, JPEG-LS, RLE) used automatically _(v1.5)_
- **Resolution Reduce (`--reduce`)**: Fast low-resolution preview at 1/2ⁿ resolution _(v1.5)_
- **Region of Interest (`--roi`)**: Crop and display a rectangular subregion _(v1.5)_
- **Volume / JP3D Mode (`--volume`)**: Multi-frame filmstrip for CT/MR/JP3D series _(v1.5)_
- **JPIP Streaming (`--jpip`)**: Fetch and display images from JPIP servers _(v1.5)_

## Installation

```bash
swift build -c release
# Binary will be at .build/release/dicom-viewer
```

## Usage

### Basic Viewing

```bash
# View a DICOM image (defaults to ASCII art)
dicom-viewer scan.dcm

# View with high-quality ASCII art
dicom-viewer scan.dcm --mode ascii --quality high

# View with ANSI true color
dicom-viewer scan.dcm --mode ansi --color 24bit

# View with ANSI 256 colors (wider terminal compatibility)
dicom-viewer scan.dcm --mode ansi --color 256
```

### Terminal Graphics Protocols

```bash
# iTerm2 inline image (macOS iTerm2 terminal)
dicom-viewer scan.dcm --mode iterm2

# Kitty graphics protocol
dicom-viewer scan.dcm --mode kitty

# Sixel graphics (xterm, mlterm, etc.)
dicom-viewer scan.dcm --mode sixel
```

### Window/Level Adjustment

```bash
# CT Bone window
dicom-viewer ct.dcm --window-center 300 --window-width 1500

# CT Lung window
dicom-viewer ct.dcm --window-center -600 --window-width 1500

# CT Brain window
dicom-viewer ct.dcm --window-center 40 --window-width 80
```

### Multi-frame Images

```bash
# View Frame number 6 (frames are numbered from 1, PS3.3 Table 10-3)
dicom-viewer multiframe.dcm --frame-number 6

# View all frames as thumbnails
dicom-viewer multiframe.dcm --thumbnail
```

### Thumbnail Grid

```bash
# View multiple files as thumbnails
dicom-viewer series/*.dcm --thumbnail

# Custom grid size
dicom-viewer series/*.dcm --thumbnail --size 120x60
```

### Information Display

```bash
# Show patient and study information
dicom-viewer scan.dcm --show-info

# Show with overlay at bottom
dicom-viewer scan.dcm --show-info --show-overlay
```

### Additional Options

```bash
# Custom output dimensions
dicom-viewer scan.dcm --width 100 --height 50

# Invert image (useful for dark background terminals)
dicom-viewer scan.dcm --invert

# Force parsing without DICM prefix
dicom-viewer scan.dcm --force

# Verbose output for debugging
dicom-viewer scan.dcm --verbose
```

### Resolution Reduction (J2KSwift v3, Phase 7)

Preview large images at reduced resolution for fast triage. Factor `n` divides
each dimension by 2ⁿ (post-decode nearest-neighbour downscale).

```bash
# Half resolution (1/2 width × 1/2 height)
dicom-viewer j2k.dcm --reduce 1

# Quarter resolution (1/4 × 1/4)
dicom-viewer j2k.dcm --reduce 2

# Combine with ANSI color
dicom-viewer large_ct.dcm --mode ansi --reduce 2
```

### Region of Interest Crop (J2KSwift v3, Phase 7)

Decode the full image and display only the specified rectangular subregion.
Coordinates are in original pixel space (0-based), specified as `x,y,width,height`.

```bash
# Show a 256×256 crop starting at pixel (100, 50)
dicom-viewer ct.dcm --roi 100,50,256,256

# Zoom into a lesion with ANSI colours
dicom-viewer mri.dcm --mode ansi --roi 200,180,64,64
```

### Volume / Multi-frame Mode (J2KSwift v3, Phase 7)

Display all frames of a multi-frame DICOM or JP3D volume file as a thumbnail
filmstrip. Useful for quick slice-by-slice review without interactive controls.

```bash
# Display all frames as thumbnails
dicom-viewer volume.dcm --volume

# Multi-frame CT with custom terminal size
dicom-viewer ct_volume.dcm --volume --size 160x80

# JP3D volume with info overlay
dicom-viewer jp3d_ct.dcm --volume --show-info
```

### JPIP Remote Streaming (J2KSwift v3, Phase 7)

Fetch and display a single image from a JPIP (JPEG 2000 Interactive Protocol)
server. Requires the `JPIP` J2KSwift module to be linked.

```bash
# Display image from JPIP URL
dicom-viewer --jpip "http://pacs.example.com/wado?studyUID=1.2.3&seriesUID=4.5.6"

# JPIP with ROI and ANSI colour
dicom-viewer --jpip "jpip://server/image" --mode ansi --roi 0,0,512,512
```

## Display Modes

| Mode | Description | Terminal Support | Quality |
|------|-------------|-----------------|---------|
| `ascii` | ASCII character art | All terminals | Good |
| `ansi` | ANSI escape code colors | Most modern terminals | Very Good |
| `iterm2` | iTerm2 inline image protocol | iTerm2 (macOS) | Excellent |
| `kitty` | Kitty graphics protocol | Kitty terminal | Excellent |
| `sixel` | Sixel graphics protocol | xterm, mlterm, foot | Excellent |

## ASCII Quality Levels

- **low**: Uses 10-character ramp (` .:-=+*#%@`), faster rendering
- **high**: Uses 70-character ramp for much finer gradation

## Options Reference

| Option | Description | Default |
|--------|-------------|---------|
| `--mode` | Display mode (ascii, ansi, iterm2, kitty, sixel) | ascii |
| `--quality` | ASCII quality (low, high) | high |
| `--color` | ANSI color depth (256, 24bit) | 24bit |
| `--window-center` | Window Center (level), Modality LUT output units | file, else auto |
| `--window-width` | Window Width (>= 1 for LINEAR, > 0 for LINEAR_EXACT / SIGMOID) | file, else auto |
| `--voi-lut-function` | VOI LUT Function: LINEAR, LINEAR_EXACT, SIGMOID (PS3.3 C.11.2.1.3) | file, else LINEAR |
| `--frame-number` | Frame number to display, 1-based (PS3.3 Table 10-3: the first Frame is Frame number 1); labels read "Frame number N" | 1 |
| `--frame` | **Deprecated**: 0-based index (0 = Frame number 1); prints a note; giving it with `--frame-number` is refused (exit 1) | — |
| `--width` | Output width in characters | Auto |
| `--height` | Output height in characters | Auto |
| `--invert` | Invert pixel values | false |
| `--show-info` | Show patient/study info | false |
| `--show-overlay` | Draw overlay planes (60xx) and a frame/size status line | false |
| `--thumbnail` | Display as thumbnail grid | false |
| `--size` | Thumbnail grid size (WxH) | Auto |
| `--force` | Force parse without DICM prefix | false |
| `--verbose` | Verbose debug output | false |
| `--reduce` | Resolution reduce factor n (1/2ⁿ) | 0 |
| `--roi` | ROI as `x,y,width,height` | (full image) |
| `--volume` | Multi-frame filmstrip mode | false |
| `--jpip` | JPIP server URL | (local file) |

## Architecture

### Components

- **main.swift**: CLI interface with ArgumentParser, command routing
- **TerminalRenderer.swift**: Core rendering engine with all display modes

### Design Decisions

- Pure Swift implementation with no external graphics dependencies
- Terminal size auto-detection via `ioctl(TIOCGWINSZ)`
- Nearest-neighbor scaling for fast image resizing
- PGM format used for iTerm2 protocol (simple, no compression needed)
- Chunk-based encoding for Kitty protocol (4KB chunks)
- 64-level grayscale palette for Sixel rendering
- Half-block Unicode characters (▀) for ANSI mode (doubles vertical resolution)
- Pixel decoding routes through `CodecRegistry` via `DICOMFile.pixelData()` so all registered J2KSwift codecs (J2K, HTJ2K, Part 2, JPEG-LS, RLE) work automatically without viewer-level changes

## Dependencies

- **DICOMKit**: DICOM file parsing and pixel data access
- **DICOMCore**: Core data structures
- **DICOMDictionary**: Tag lookups
- **ArgumentParser**: Command-line argument parsing

## Version

Current: v1.5.0 (J2KSwift v3 Phase 7 — CodecRegistry integration, --reduce, --roi, --volume, --jpip)
