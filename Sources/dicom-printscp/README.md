# dicom-printscp

DICOM Print SCP — a printer emulator. The receiving half of [`dicom-print`](../dicom-print/README.md).

## Overview

`dicom-printscp` listens for Print SCUs (modalities, workstations, `dicom-print send`, DCMTK's
`dcmprscu`), answers the Print Management N-services, and composes every printed film onto a
sheet it writes as PNG, TIFF or PDF — or spools to a real paper queue.

Because the printer is emulated, it can be made to misbehave on purpose:
`--printer-status failure` exercises an SCU's error path, and `--no-accept-color` /
`--film-size` narrow what is negotiated. That is the value an emulator has over hardware.

## Installation

```bash
swift build -c release --product dicom-printscp
cp .build/release/dicom-printscp /usr/local/bin/
```

## Usage

### Receive film

```bash
# Write each received sheet as a PNG
dicom-printscp serve --port 11113 --ae-title DCMPRINT \
    --output png --output-dir ~/Films

# Keep a PDF archive of everything, accept only two modalities
dicom-printscp serve --output pdf --output-dir ~/Films \
    --allow-ae CT1 --allow-ae MR1

# A printer that says it is out of film
dicom-printscp serve --printer-status failure

# Receive one film, then exit (scriptable)
dicom-printscp serve --max-films 1 --output png --output-dir ./out

# Spool received film to a real printer
dicom-printscp serve --paper-queue HP_LaserJet --allow-paper
```

`serve` runs until interrupted (Ctrl-C), until `--max-films` films have arrived, or until
`--duration` seconds have passed. Ctrl-C stops the listener rather than killing the process, so
open associations are released and the totals are still reported. A satisfied `--max-films`
waits for the association to release before stopping, so the SCU still gets its N-ACTION
response.

### Compose without a network

```bash
dicom-printscp simulate scan.dcm --output png
dicom-printscp simulate study/ --recursive --layout 2x2 --output pdf
dicom-printscp simulate ct.dcm --density film --dpi 150 --open
```

### Inspect

```bash
dicom-printscp status                      # what an SCU's N-GET would see
dicom-printscp status --verbose            # the full resolved configuration
dicom-printscp queues                      # CUPS queues for --paper-queue
```

## Options

### `serve`

**Transport**

| Option | Description |
|--------|-------------|
| `--port` | TCP port to listen on (default: 11113) |
| `--ae-title` | AE title the emulator answers as (default: DCMPRINT) |
| `--max-associations` | Maximum concurrent associations (default: 10) |
| `--idle-timeout` | Seconds an idle association may sit before it is aborted; 0 disables (default: 300) |
| `--allow-ae` | Calling AE title to accept (repeatable; default: accept all) |
| `--deny-ae` | Calling AE title to refuse (repeatable; takes precedence over `--allow-ae`) |
| `--max-pdu` | Maximum Length of a received P-DATA-TF PDU offered during negotiation (PS3.8 D.1) (default: 65536) |

**Negotiated capability**

| Option | Description |
|--------|-------------|
| `--accept-color` / `--no-accept-color` | Accept the Basic Color Print Management Meta SOP Class (1.2.840.10008.5.1.1.18) (default: yes) |
| `--presentation-lut` / `--no-presentation-lut` | Accept the Presentation LUT SOP Class (1.2.840.10008.5.1.1.23) N-CREATE (default: yes) |
| `--annotation-box` / `--no-annotation-box` | Accept the Basic Annotation Box SOP Class (1.2.840.10008.5.1.1.15) N-SET (default: yes; PS3.4 Table H.4.4.2-1 defines N-SET only) |
| `--annotation-boxes-per-film` | Basic Annotation Box instances created per film box, in Referenced Basic Annotation Box Sequence (2010,0520) (default: 6) |
| `--push-job-events` | Send a Print Job SOP Class N-EVENT-REPORT, Event Type Done (3, PS3.4 Table H.4-14), after each N-ACTION |
| `--film-size` | Film Size ID (2010,0050) to accept (repeatable; default: all): 8x10 = 8INX10IN, 8.5x11 = 8_5INX11IN, 10x12 = 10INX12IN, 10x14 = 10INX14IN, 11x14 = 11INX14IN, 11x17 = 11INX17IN, 14x14 = 14INX14IN, 14x17 = 14INX17IN, 24x24cm = 24CMX24CM, 24x30cm = 24CMX30CM, a4 = A4, a3 = A3 (the Defined Term is also accepted) |
| `--medium` | Medium Type (2000,0030) to accept (repeatable; default: all): paper, clear-film, blue-film, mammo-clear-film, mammo-blue-film = PAPER, CLEAR FILM, BLUE FILM, MAMMO CLEAR FILM, MAMMO BLUE FILM (the Defined Term is also accepted) |
| `--max-image-boxes` | Maximum image boxes an Image Display Format (2010,0010) may declare (default: 64) |
| `--max-image-dimension` | Largest image dimension accepted in an image box (default: 10000) |

**Reported identity (answers N-GET)**

| Option | Description |
|--------|-------------|
| `--printer-name` | Printer Name (2110,0030) |
| `--manufacturer` | Manufacturer (0008,0070) |
| `--model` | Manufacturer's Model Name (0008,1090) |
| `--serial-number` | Device Serial Number (0018,1000) |
| `--software-version` | Software Versions (0018,1020) |
| `--printer-status` | Printer Status (2110,0010), PS3.3 Table C.13-9: normal, warning, failure = NORMAL, WARNING, FAILURE |
| `--status-info` | Printer Status Info (2110,0020), a PS3.3 C.13.9.1 Defined Term such as SUPPLY EMPTY; empty uses the status's own term |

**Composition**

| Option | Description |
|--------|-------------|
| `--dpi` | Rasterization resolution of the composed sheet (default: 300) |
| `--density` | Density interpretation: paper, film, gsdf (the PS3.14 Grayscale Standard Display Function) (default: paper) |
| `--margin-mm` | Sheet margin in millimetres (default: 5) |
| `--cell-spacing-mm` | Gap between image cells in millimetres (default: 2) |
| `--annotations` / `--no-annotations` | Draw Basic Annotation Box text (default: yes) |
| `--trim-marks` / `--no-trim-marks` | Print a trim box around each image when Trim (2010,0140) is YES, PS3.3 Table C.13-3 (default: yes) |
| `--max-pixels` | Cap on the composed bitmap's longest side (default: 12000) |

**Output**

| Option | Description |
|--------|-------------|
| `--output` | png, tiff, pdf, none (repeatable; default: png) |
| `--output-dir` | Directory written films are saved to (default: `~/Downloads/DICOMKit Films`) |
| `--name-pattern` | File-name pattern; tokens `{job}` `{session}` `{film}` `{ae}` `{index}` `{timestamp}` |
| `--paper-queue` | Spool film to this CUPS queue (requires `--allow-paper`) |
| `--allow-paper` | Enable paper spooling |
| `--open` | Open each written film in the default viewer |

**Run control**

| Option | Description |
|--------|-------------|
| `--max-films` | Stop after this many films |
| `--duration` | Stop after this many seconds |
| `--config` | Settings file to read (default: `~/.config/dicomkit/printscp.json` when it exists) |
| `--save-config` | Write the resolved settings back to the configuration file and exit |
| `--format` | text, json (json writes one object per line to stdout) |
| `--verbose` / `-v` | Show each film's attributes as it arrives |
| `--quiet` | Suppress console output; only errors are reported |

### `simulate`

Takes `<paths...>` plus the composition, output and config options above, and the job options a
Print SCU would have sent: `--layout`, `--film-size`, `--orientation`, `--magnification`,
`--medium`, `--copies`, `--polarity`, `--presentation-lut`, `--trim`, `--border-density`,
`--empty-density`, `--annotate` / `--annotation-format`, `--color`, `--frame`, `--all-frames`,
`--raw`, `--window-center` / `--window-width`, `--bit-depth`, `--recursive`, `--calling-ae`.

Each film-box option names its attribute in `--help` with the term every token sends
(`14x17 = 14INX17IN`), and takes the term itself as well. `--layout` takes a grid `RxC` (sent as
`STANDARD\C,R`) or any Image Display Format form of PS3.3 Table C.13-3 (`'ROW\1,2'`,
`'COL\1,4,4'`, `SLIDE`, `SUPERSLIDE`, `'CUSTOM\i'`). `--border-density` / `--empty-density`
take BLACK, WHITE or a density in hundredths of OD (`150` = 1.5 OD). `--bit-depth` is 8 or 12, the
Bits Stored values of Table C.13-5.

### `status` / `queues`

`status` takes every settings option plus `--format` and `--verbose`. `queues` takes `--format`.

`status --format json` keys each attribute by its PS3.6 Table 6-1 keyword (`PrinterStatus`,
`PrinterStatusInfo`, `PrinterName`, `Manufacturer`, `ManufacturerModelName`), the same object
`dicom-print status --format json` prints. The older keys `status`, `statusInfo`, `name`,
`manufacturer` and `model` carry the same values and are deprecated.

## Configuration file

`--config` reads and writes the same JSON document DICOM Studio's Print SCP screen persists, so
a configuration can be moved between the two. Flags override what the file holds:

```bash
dicom-printscp serve --config ~/printers/ct-room.json --save-config \
    --port 11500 --ae-title FILMBOX --printer-status warning --output pdf
dicom-printscp serve --config ~/printers/ct-room.json
```

Decoding is tolerant: a file written by an older build keeps every field it has and defaults
only what it lacks.

## End-to-end check

```bash
dicom-printscp serve --port 11113 --output png --output-dir ./out --max-films 1 &
dicom-print send pacs://127.0.0.1:11113 scan.dcm --aet MODALITY1 --called-aet DCMPRINT
```

## Exit codes

| Code | Description |
|------|-------------|
| 0 | Success (including a listener that stopped for its configured reason) |
| 1 | General error — bad option value, port in use, unreadable input |
| 64 | Command line usage error |

## Implementation

The command-line surface here is a thin ArgumentParser shell. The settings type
(`PrintSCPSettings`), the server/sink/composer assembly (`PrintSCPService`), the console wording
(`PrintSCPConsole`) and the local composer (`PrintSCPSimulator`) all live in the shared
**`DICOMPrintKit`** target, which DICOM Studio's Print SCP screen uses as well — so a film
received here and a film received in the app are negotiated, composed and described by identical
code. The protocol machine itself is `DICOMPrintServer` in `DICOMNetwork`.

The configuration file read by `--config` (`~/.config/dicomkit/printscp.json`) is the CLI's own;
DICOM Studio keeps a separate, sandbox-reachable store of the same document. That separation is
by design, not a parity defect.

## See Also

- [dicom-print](../dicom-print/README.md) — the SCU: send film to a printer
- [DICOM_PRINT_SCP_PLAN.md](../../DICOM_PRINT_SCP_PLAN.md) — the emulator's plan and milestones
- [PRINT_CONFORMANCE.md](../../PRINT_CONFORMANCE.md) — print conformance statement (SCU and SCP)

## Version

1.0.0
