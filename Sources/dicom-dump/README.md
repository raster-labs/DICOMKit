# dicom-dump

Hexadecimal dump utility with DICOM structure visualization for low-level debugging and format inspection.

## Features

- **Hexadecimal Display**: Side-by-side hex and ASCII representation
- **Structure Annotations**: Automatic detection and annotation of DICOM tags
- **Flexible Navigation**: Dump entire file, specific byte ranges, or individual tags
- **Color-Coded Output**: Optional ANSI color for terminal readability
- **VR and Length Details**: Verbose mode shows Value Representation and length fields

## Usage

### Basic Hex Dump

```bash
dicom-dump file.dcm
```

Displays the file in hexadecimal format (the first 65,536 bytes unless `--length` is given).
Add `--annotate` for tag annotations.

### Dump Specific Tag

```bash
dicom-dump file.dcm --tag 7FE0,0010
dicom-dump file.dcm --tag PixelData
```

Displays only the specified tag (e.g., Pixel Data) with its raw bytes. The tag is given as
`GGGG,EEEE` or by its PS3.6 keyword (exact case, e.g. `PatientName`).

### Dump Byte Range

```bash
dicom-dump file.dcm --offset 0x1000 --length 256
```

Dumps 256 bytes starting at offset 0x1000 (hex format supported).

```bash
dicom-dump file.dcm --offset 4096 --length 512
```

Dumps 512 bytes starting at offset 4096 (decimal format).

### Verbose Mode

```bash
dicom-dump file.dcm --annotate --verbose
```

Shows detailed VR and length annotations for each tag.

### Plain Text Output

```bash
dicom-dump file.dcm --no-color > dump.txt
```

Disables ANSI color codes for redirected output or non-terminal use.

### Custom Bytes Per Line

```bash
dicom-dump file.dcm --bytes-per-line 32
```

Shows 32 bytes per line instead of the default 16.

## Output Format

```
00000080  02 00 00 00 55 4C 04 00  54 00 00 00 02 00 10 00  |....UL..T.......|  ← (0002,0000) FileMetaInformationGroupLength
00000090  55 49 1A 00 31 2E 32 2E  38 34 30 2E 31 30 30 30  |UI..1.2.840.1000|
000000A0  38 2E 31 2E 32 2E 31 00  08 00 16 00 55 49 1A 00  |8.1.2.1.....UI..|  ← (0008,0016) SOPClassUID
```

Each line shows:
- Offset (hex): Current byte position in file
- Hex bytes: Up to 16 bytes in hexadecimal
- ASCII: Printable ASCII representation (. for non-printable)
- Annotation: Tag number and name (when detected)

## Options

- `--tag <TAG>`: Dump specific tag only (format: 0010,0010 or PS3.6 keyword, e.g. PatientName)
- `--offset <OFFSET>`: Start offset in bytes (hex with 0x prefix or decimal)
- `--length <LENGTH>`: Number of bytes to dump (0 or more; default: up to 65,536)
- `--bytes-per-line <N>`: Bytes per line (at least 1; default: 16)
- `--highlight <TAG>`: Highlight specific tag in output (0010,0010 or PS3.6 keyword)
- `--no-color`: Disable ANSI color codes
- `--annotate`: Show tag annotations (off by default)
- `--force`: Force parsing of files without DICM prefix
- `--verbose`: Show VR and length details in annotations

## Use Cases

### Debugging Transfer Syntax Issues

```bash
dicom-dump file.dcm --offset 0x80 --length 128
```

Examine the file meta information to verify transfer syntax encoding.

### Locating Pixel Data

```bash
dicom-dump file.dcm --tag 7FE0,0010
```

Find and inspect the raw pixel data bytes.

### Inspecting Sequences

```bash
dicom-dump file.dcm --annotate --verbose
```

Shows each element's VR and length; a sequence of undefined length shows `Len=undefined`.
The Item (FFFE,E000), Item Delimitation Item (FFFE,E00D) and Sequence Delimitation Item
(FFFE,E0DD) of PS3.5 7.5 are stepped over, not labelled.

### Creating Debug Reports

```bash
dicom-dump file.dcm --no-color --verbose > debug_report.txt
```

Generate a plain text dump for bug reports or documentation.

## Examples

### Example 1: Quick File Inspection

```bash
$ dicom-dump sample.dcm | head -20
```

Shows the first 20 lines (preamble and file meta information).

### Example 2: Finding Corrupted Tags

```bash
$ dicom-dump corrupted.dcm --annotate --verbose
```

Look for irregular VR values or length fields.

### Example 3: Comparing File Formats

```bash
$ dicom-dump explicit.dcm --offset 0x80 --length 64 > explicit.txt
$ dicom-dump implicit.dcm --offset 0x80 --length 64 > implicit.txt
$ diff explicit.txt implicit.txt
```

Compare explicit vs implicit VR encoding.

## Limitations

- Very large files may take time to process completely
- Tag detection is heuristic-based and may not be 100% accurate for corrupted files
- Implicit VR format has limited annotation support
- Annotations and `--highlight` assume the dump starts at offset 0 (128-byte preamble + "DICM",
  PS3.10 7.1); with `--offset` greater than 0 they are missing or misplaced
- Elements inside defined-length Items are not annotated
- Compressed transfer syntaxes show compressed data, not decompressed pixels

## Technical Details

The tool reads DICOM files using DICOMKit and performs low-level byte-by-byte analysis:

1. **Preamble**: First 128 bytes (usually zeros)
2. **DICM Prefix**: 4 bytes at offset 128
3. **File Meta Information**: Group 0002 tags (explicit VR)
4. **Data Set**: Main DICOM tags (explicit or implicit VR depending on transfer syntax)

Tag detection walks the stream element by element after the 132-byte preamble and prefix: when the
two bytes after a tag are one of the 34 VR codes of PS3.5 Table 6.2-1 the element is read as Explicit
VR (4-byte length for OB, OD, OF, OL, OV, OW, SQ, SV, UC, UN, UR, UT, UV per Table 7.1-1), otherwise
as Implicit VR with the VR from the PS3.6 dictionary. Annotations print the PS3.6 keyword.

## See Also

- `dicom-info`: Display DICOM metadata
- `dicom-validate`: Validate DICOM file structure
- `dicom-convert`: Convert between transfer syntaxes

## Version

1.0.0
