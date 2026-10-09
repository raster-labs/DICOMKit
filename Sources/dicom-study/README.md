# dicom-study

Organize and analyze DICOM studies and series with comprehensive metadata management and validation.

## Features

- **Study Organization**: Organize DICOM files by study/series hierarchy
- **Metadata Summarization**: Display comprehensive study and series metadata
- **Completeness Checking**: Validate study completeness and detect missing slices
- **Statistics**: Calculate study statistics including file sizes and modality distribution
- **Study Comparison**: Compare two studies for structural differences

## Installation

```bash
swift build -c release
.build/release/dicom-study --help
```

## Usage

### Organize Command

Organize DICOM files into a hierarchical study/series structure:

```bash
# Organize with descriptive names
dicom-study organize input_dir/ --output organized/

# Organize with UID-based names
dicom-study organize input_dir/ --output organized/ --pattern uid

# Copy instead of move
dicom-study organize input_dir/ --output organized/ --copy

# Verbose output
dicom-study organize input_dir/ --output organized/ --verbose
```

**Naming Patterns** (files are grouped by Study Instance UID (0020,000D) and Series Instance UID
(0020,000E), the Study and Series unique keys of PS3.4 C.6.1.1):
- `descriptive`: `<Patient's Name>_<Study Description>_<last 8 characters of Study Instance UID>/<Series Number>_<Modality>_<Series Description>/<n>.dcm`
- `uid`: `<Study Instance UID>/<Series Instance UID>/<n>.dcm`

### Summary Command

Display study and series metadata:

```bash
# Table format (default)
dicom-study summary study_dir/

# JSON format
dicom-study summary study_dir/ --format json

# CSV format
dicom-study summary study_dir/ --format csv

# Verbose output with series details
dicom-study summary study_dir/ --verbose
```

**Output Formats:**
- `table`: Human-readable tabular format
- `json`: Machine-readable JSON
- `csv`: CSV format for spreadsheet import. Columns: `StudyUID,StudyDate,PatientName,PatientID,SeriesCount,InstanceCount,StudyInstanceUID,NumberOfStudyRelatedSeries,NumberOfStudyRelatedInstances`.
  The last three are the PS3.6 2026a Table 6-1 keywords; `StudyUID`, `SeriesCount` and `InstanceCount` carry the same
  values and are **deprecated** (kept in place for existing spreadsheets; removed in the next major version).

### Check Command

Validate study completeness and detect missing instances:

```bash
# Basic completeness check
dicom-study check study_dir/

# Check with expected counts
dicom-study check study_dir/ \
  --expected-series 5 \
  --expected-instances 100

# Write report to file
dicom-study check study_dir/ \
  --expected-series 5 \
  --report missing.txt

# Verbose output
dicom-study check study_dir/ --verbose
```

**Validation:**
- Series count validation
- Instance count validation per series
- Missing slice detection: gaps in Instance Number (0020,0013) within a series. This is a heuristic —
  PS3.3 Table C.7-9 defines Instance Number as "A number that identifies this image" (Type 2) and
  does not require consecutive numbering.

### Stats Command

Calculate comprehensive study statistics:

```bash
# Basic statistics
dicom-study stats study_dir/

# Detailed statistics
dicom-study stats study_dir/ --detailed

# JSON output
dicom-study stats study_dir/ --format json
```

**Statistics Include:**
- Series and instance counts (JSON keys `StudyInstanceUID`, `NumberOfStudyRelatedSeries`,
  `NumberOfStudyRelatedInstances`, `ModalitiesInStudy` per PS3.6 2026a Table 6-1; the former keys `studyUID`,
  `seriesCount`, `totalInstances` are still written and are **deprecated**)
- Total and average file sizes
- Modality distribution
- Instance count distribution (detailed mode)

### Compare Command

Compare two studies for structural differences:

```bash
# Basic comparison
dicom-study compare study1/ study2/

# JSON output
dicom-study compare study1/ study2/ --format json

# Verbose comparison
dicom-study compare study1/ study2/ --verbose

# JSON: `study1` / `study2` objects carry StudyInstanceUID, NumberOfStudyRelatedSeries and
# NumberOfStudyRelatedInstances (PS3.6 2026a Table 6-1), seriesDifferences items carry SeriesInstanceUID;
# the former study1UID / study1SeriesCount / study1InstanceCount (and study2...) and seriesUID keys are
# still written and are deprecated
```

**Comparison Metrics:**
- Series count differences
- Instance count differences
- Series present in only one study
- Instance count differences per series

## Examples

### Workflow: Organize and Validate

```bash
# Step 1: Organize incoming DICOM files
dicom-study organize raw_dicoms/ --output organized_studies/ --verbose

# Step 2: Check study completeness
dicom-study check organized_studies/Study_1/ --expected-series 4 --report validation.txt

# Step 3: View detailed statistics
dicom-study stats organized_studies/Study_1/ --detailed

# Step 4: Generate JSON summary for archival
dicom-study summary organized_studies/Study_1/ --format json > metadata.json
```

### Workflow: Compare Studies

```bash
# Compare baseline and follow-up studies
dicom-study compare baseline_study/ followup_study/ --verbose

# Generate comparison report
dicom-study compare baseline_study/ followup_study/ --format json > comparison.json
```

## Error Handling

The tool provides clear error messages for common issues:

- **Directory Not Found**: Specified path does not exist
- **Invalid DICOM File**: File cannot be parsed as DICOM
- **No Files Found**: No DICOM files found in directory
- **Invalid Pattern**: Invalid naming pattern specified
- **Missing Required UIDs**: DICOM file missing required UIDs

## Performance

- **File Scanning**: Efficiently scans large directories using file system enumeration
- **Memory Usage**: Processes files sequentially to minimize memory footprint
- **I/O Optimization**: Uses streaming for large file operations

## Version

dicom-study v1.3.4 - Part of DICOMKit CLI Tools Suite

## See Also

- `dicom-info` - Display DICOM file metadata
- `dicom-archive` - Local DICOM archive management
- `dicom-query` - Query PACS for studies
- `dicom-split` - Extract frames from multi-frame files
- `dicom-merge` - Create multi-frame DICOM files
