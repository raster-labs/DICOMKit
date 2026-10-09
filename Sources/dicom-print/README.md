# dicom-print

DICOM Print Management CLI tool for sending medical images to DICOM-compliant printers.

## Overview

`dicom-print` provides command-line access to DICOM Print Management Service Class operations. It allows you to:

- Query printer status
- Send DICOM images to printers
- Monitor print job status
- Manage printer configurations

Reference: DICOM PS3.4 Annex H - Print Management Service Class

## Installation

The tool is included with DICOMKit and can be built using Swift Package Manager:

```bash
swift build -c release --product dicom-print
```

The executable will be available at `.build/release/dicom-print`.

## Usage

### Query Printer Status

```bash
# Query printer status
dicom-print status pacs://192.168.1.100:11112 --aet WORKSTATION

# With verbose output
dicom-print status pacs://192.168.1.100:11112 --aet WORKSTATION --verbose

# JSON output
dicom-print status pacs://192.168.1.100:11112 --aet WORKSTATION --format json
```

### Print DICOM Images

```bash
# Print single image
dicom-print send pacs://192.168.1.100:11112 image.dcm --aet WORKSTATION

# Print with custom options
dicom-print send pacs://server:11112 scan.dcm --aet APP \
    --copies 2 --film-size 14x17 --orientation landscape

# Print multiple images with layout
dicom-print send pacs://server:11112 *.dcm --aet APP --layout 2x3

# A scout over its slices — one image in the top row, three beneath it
dicom-print send pacs://server:11112 *.dcm --aet APP --layout 'ROW\1,3'

# Print directory recursively
dicom-print send pacs://server:11112 studies/ --aet APP --recursive

# Dry run (show what would be printed)
dicom-print send pacs://server:11112 *.dcm --aet APP --dry-run
```

### Monitor Print Jobs

```bash
# Query print job status
dicom-print job pacs://server:11112 --aet APP --job-id 1.2.840.113619.2.55.3.2024...

# JSON output
dicom-print job pacs://server:11112 --aet APP --job-id 1.2.840... --format json
```

### Printer Configuration

```bash
# List configured printers
dicom-print list-printers

# Add a new printer
dicom-print add-printer --name radiology-printer \
    --host 192.168.1.100 --port 11112 --called-ae PRINT_SCP

# Add a color printer as default
dicom-print add-printer --name color-printer \
    --host 10.0.0.50 --port 11112 --called-ae COLOR_PRINT \
    --color color --default

# Remove a printer
dicom-print remove-printer --name radiology-printer
```

## Options

### Global Options

| Option | Description |
|--------|-------------|
| `--aet` | Local Application Entity Title (calling AE) |
| `--called-aet` | Remote Application Entity Title (default: ANY-SCP) |
| `--timeout` | Connection timeout in seconds (default: 30-60) |
| `--verbose` / `-v` | Show verbose output |
| `--format` | Output format: text, json |

### Print Options

| Option | Description |
|--------|-------------|
| `--copies` | Number of Copies (2000,0010), 1 or more (default: 1) |
| `--film-size` | Film Size ID (2010,0050), PS3.3 Table C.13-3: 8x10 = 8INX10IN, 8.5x11 = 8_5INX11IN, 10x12 = 10INX12IN, 10x14 = 10INX14IN, 11x14 = 11INX14IN, 11x17 = 11INX17IN, 14x14 = 14INX14IN, 14x17 = 14INX17IN, 24x24cm = 24CMX24CM, 24x30cm = 24CMX30CM, a4 = A4, a3 = A3 (the Defined Term is also accepted; default: 14x17) |
| `--magnification` | Magnification Type (2010,0060): replicate, bilinear, cubic, none = REPLICATE, BILINEAR, CUBIC, NONE (default: replicate) |
| `--film-destination` | Film Destination (2000,0040): magazine = MAGAZINE, processor = PROCESSOR, bin-1 = BIN_1, bin-2 = BIN_2, ... bin-N = BIN_N (default: processor). PS3.3 Table C.13-1 numbers sorter bins from 1 with no maximum and no leading zeros: any `bin-N` or `BIN_N` is accepted and sent |
| `--check-status` | N-GET Printer Status (2110,0010) first; abort on FAILURE, warn on WARNING |
| `--verify` | C-ECHO connectivity check against the printer before printing |
| `--orientation` | Film Orientation (2010,0040): portrait = PORTRAIT, landscape = LANDSCAPE (default: portrait) |
| `--priority` | Print Priority (2000,0020): low = LOW, medium = MED, high = HIGH (default: medium) |
| `--layout` | Image Display Format (2010,0010): a grid `RxC` (1x1 … 4x5; R rows by C columns, sent as `STANDARD\C,R`) or any PS3.3 Table C.13-3 form — `STANDARD\C,R`, `ROW\R1,R2,…`, `COL\C1,C2,…`, `SLIDE`, `SUPERSLIDE`, `CUSTOM\i` (auto if omitted) |
| `--template` | Layout preset: single, comparison, grid, multi-phase (sets layout + film size + orientation; conflicts with `--layout`) |
| `--medium` | Medium Type (2000,0030): paper = PAPER, clear-film = CLEAR FILM, blue-film = BLUE FILM, mammo-clear-film = MAMMO CLEAR FILM, mammo-blue-film = MAMMO BLUE FILM (default: paper) |
| `--color` | Meta SOP Class: grayscale = Basic Grayscale Print Management Meta SOP Class (1.2.840.10008.5.1.1.9), color = Basic Color Print Management Meta SOP Class (1.2.840.10008.5.1.1.18) (default: grayscale) |
| `--frame` | 1-based frame to print from multi-frame files (default: 1) |
| `--all-frames` | Print every frame of multi-frame files (one image box per frame) |
| `--raw` | Send stored pixel values without preprocessing (compressed sources are still decoded) |
| `--window-center` / `--window-width` | Explicit VOI window (paired; overrides the data set's window) |
| `--bit-depth` | Grayscale output depth: 8 or 12, the Bits Stored values of PS3.3 Table C.13-5 (default: 8; a higher value is clamped) |
| `--presentation-lut` | Presentation LUT Shape (2050,0020), PS3.3 Table C.11-4: identity = IDENTITY, lin-od = LIN OD; inverse sends no shape (the table has none) and inverts the pixels (default: none) |
| `--annotate` | Text String (2030,0020) of a Basic Annotation Box (repeatable; requires `--annotation-format`) |
| `--annotation-format` | Annotation Display Format ID (2010,0030), from the printer's Conformance Statement |
| `--retries` | Retry on connection/setup failure, up to N times with backoff (default: 0) |
| `--recursive` / `-r` | Recursively scan directories |
| `--dry-run` | Show what would be printed without printing |

### Pixel preprocessing

By default `send` prepares each frame for film output: encapsulated transfer
syntaxes (JPEG, JPEG 2000, JPEG-LS, RLE) are decoded to native pixels, then the
frame is passed through the print pipeline — Rescale Slope/Intercept, VOI
window (from the data set, or auto-calculated), MONOCHROME1 inversion — and
emitted as 8-bit MONOCHROME2 (grayscale mode) or 8-bit RGB (color mode). This
matches what a viewer shows clinically. Use `--raw` to bypass the pipeline and
send stored values unchanged (compressed sources are still decoded first, since
Basic Image Boxes require uncompressed pixel data).

A failed print exits with a non-zero status code, so scripts can detect
failures reliably.

### Output contract

Scripts can rely on this split across all subcommands:

- **stdout** carries machine-readable output only: the JSON object produced by
  `--format json` (`status`, `job`, and `send` all support it). In text mode,
  stdout stays empty.
- **stderr** carries all human-readable text: progress, diagnostics, event
  notifications, and text-mode results.
- **Exit code** is `0` on success and non-zero on any failure (validation
  error, connection error, printer FAILURE via `--check-status`, or an
  unsuccessful print result).

`send --format json` emits `{"success": bool, "printJobUID"?, "filmSessionUID"?,
"filmBoxUID"?, "error"?}`.

`status --format json` and `job --format json` key each N-GET attribute by its PS3.6
Table 6-1 keyword:

| Subcommand | Keyword keys | Deprecated keys (same value, kept for now) |
|---|---|---|
| `status` | `PrinterStatus`, `PrinterStatusInfo`, `PrinterName`, `Manufacturer`, `ManufacturerModelName` | `status`, `statusInfo`, `name`, `manufacturer`, `model` |
| `job` | `ExecutionStatus`, `ExecutionStatusInfo`, `CreationDate` (DA, `YYYYMMDD`), `CreationTime` (TM, `HHMMSS`) | `status`, `statusInfo`, `creationDate` (ISO 8601) |

`status` also has `isNormal` and `job` has `jobUID` (the Print Job SOP Instance UID); neither
is an attribute keyword.

### Presentation LUT

`--presentation-lut` creates a Presentation LUT SOP Instance and references it
from each film box, controlling how stored pixel values map to display values:

```bash
# Print with an identity presentation LUT (no transformation)
dicom-print send pacs://server:11112 scan.dcm --aet APP --presentation-lut identity
```

### Film Annotations

`--annotate` places text on the film using Basic Annotation Boxes. Because
annotation box positions are defined by a printer-specific Annotation Display
Format, you must supply the format ID configured on your printer:

```bash
dicom-print send pacs://server:11112 scan.dcm --aet APP \
    --annotation-format STANDARD \
    --annotate "PATIENT: DOE^JOHN" \
    --annotate "STUDY: CHEST CT"
```

Annotations are placed in the order given (first `--annotate` → position 1, etc.).

### Retry on Failure

`--retries N` retries the print on connection/setup failures with exponential
backoff. A job that has been submitted to the printer is never retried, so this
cannot cause duplicate prints:

```bash
dicom-print send pacs://server:11112 scan.dcm --aet APP --retries 3
```

> **Note:** `--layout` selects the film's Image Display Format (2010,0010). A
> grid token is written `RxC`; the band forms of PS3.3 C.13.3 are given as the
> standard writes them — `'ROW\1,2'` puts one image over two, `'COL\1,4,4'` puts
> one beside two columns of four — and must be quoted so the shell keeps the
> backslash. Any valid format is accepted; the named ones the DICOMStudio print
> sheet also offers are `ROW\1,2`, `ROW\2,3`, `COL\1,2`, `COL\1,3`, `COL\1,4`,
> `COL\1,4,4` and `COL\2,4,4`. When omitted, an optimal grid is chosen
> automatically from the number of images. `--color color` negotiates the Basic Color Print Management Meta SOP
> Class and sends color image boxes; the default is grayscale.

### Printer Notifications (N-EVENT-REPORT)

While a print job runs, the printer (SCP) may push asynchronous status
notifications over the association — printer faults (out of film, jam) and
print-job progress (pending → printing → done/failure). `dicom-print send`
receives and acknowledges these automatically:

- **Faults** (printer warning/failure, print-job failure) are always printed,
  e.g. `⚠ Printer Failure: OUT OF SUPPLY`.
- **Routine progress** events are shown with `--verbose`, e.g. `• Print Job Printing`.

## Configuration File

Printer configurations are stored in:
- macOS/Linux: `~/.config/dicomkit/printers.json`

Example configuration:

```json
[
  {
    "name": "radiology-printer",
    "host": "192.168.1.100",
    "port": 11112,
    "calledAETitle": "PRINT_SCP",
    "callingAETitle": "WORKSTATION",
    "colorMode": "grayscale",
    "isDefault": true
  }
]
```

## Film Sizes

| Size | Description |
|------|-------------|
| `8x10` | 8×10 inches |
| `10x12` | 10×12 inches |
| `10x14` | 10×14 inches |
| `11x14` | 11×14 inches |
| `11x17` | 11×17 inches (Tabloid) |
| `14x14` | 14×14 inches |
| `14x17` | 14×17 inches |
| `a4` | A4 size (210×297 mm) |
| `a3` | A3 size (297×420 mm) |

## Image Layouts

| Layout | Description |
|--------|-------------|
| `1x1` | Single image |
| `1x2` | 2 images horizontal |
| `2x1` | 2 images vertical |
| `2x2` | 4 images in grid |
| `2x3` | 6 images (2 rows × 3 columns) |
| `3x3` | 9 images in grid |
| `3x4` | 12 images (3 rows × 4 columns) |
| `4x4` | 16 images in grid |
| `4x5` | 20 images (4 rows × 5 columns) |

## Examples

### Basic Workflow

```bash
# 1. Check printer status
dicom-print status pacs://192.168.1.100:11112 --aet APP

# 2. Print an image
dicom-print send pacs://192.168.1.100:11112 ct_scan.dcm --aet APP

# 3. Monitor the print job
dicom-print job pacs://192.168.1.100:11112 --aet APP --job-id 1.2.840...
```

### Batch Printing

```bash
# Print all DICOM files in a study directory
dicom-print send pacs://server:11112 study_folder/ --aet APP --recursive

# Print with specific layout for comparison
dicom-print send pacs://server:11112 pre.dcm post.dcm --aet APP --layout 1x2
```

### High Quality Mammography Print

```bash
dicom-print send pacs://mammo-printer:11112 mammo_*.dcm \
    --aet MAMMO_WS \
    --film-size 14x17 \
    --medium clear-film \
    --priority high \
    --layout 1x1
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success (for `status` / `job`, the printer answered; read Printer Status / Execution Status for its state) |
| 1 | Failure: the print was not accepted (an N-CREATE / N-SET / N-ACTION Failure status of PS3.4 Annex H), `--check-status` saw Printer Status FAILURE, or a connection / file error |
| 64 | Command line usage error (unknown option value, conflicting options, no DICOM files found) |

## Implementation

The command-line surface here is a thin ArgumentParser shell. Image preparation, the job
model, workflow orchestration and all console/JSON output live in the shared
**`DICOMPrintKit`** target (`PrintImagePreparer`, `PrintJobRequest`, `PrintOptionCatalog`,
`PrintWorkflow`, `PrintConsoleFormatter`), which DICOMStudio's print screens use as well, so
both surfaces run one pipeline and print identical output. The DIMSE sequence itself remains
`DICOMPrintService` in `DICOMNetwork`.

The printer registry read by `list-printers` / `add-printer` / `remove-printer`
(`~/.config/dicomkit/printers.json`) is the CLI's own; DICOMStudio keeps a separate,
sandbox-reachable store. That separation is by design, not a parity defect.

## See Also

- [DICOM_PRINTER_PLAN.md](../../DICOM_PRINTER_PLAN.md) - Full implementation plan
- [DICOM_PRINT_STUDIO_PLAN.md](../../DICOM_PRINT_STUDIO_PLAN.md) - The same capability in DICOMStudio
- [DICOM_PRINT_SCP_PLAN.md](../../DICOM_PRINT_SCP_PLAN.md) - The printer emulator (Print SCP) side
- [PRINT_CONFORMANCE.md](../../PRINT_CONFORMANCE.md) - Print conformance statement (SCU and SCP)
- [DICOM_PRINTER_QUICK_REFERENCE.md](../../DICOM_PRINTER_QUICK_REFERENCE.md) - Quick reference
- DICOM PS3.4 Annex H - Print Management Service Class specification

## Version

v1.4.5 - Part of DICOMKit Print Management (Phase 5)
