# dicom-script

Execute DICOM workflow scripts and pipelines with support for conditional logic, variable substitution, and parallel execution.

## Features

- **Workflow Scripting DSL**: Simple, readable syntax for DICOM workflows
- **Pipeline Execution**: Chain multiple DICOM commands together
- **Conditional Logic**: Execute commands based on conditions
- **Variable Substitution**: Use variables throughout scripts
- **Parallel Execution**: Run commands in parallel when possible
- **Error Handling**: Robust error handling and reporting
- **Script Validation**: Validate scripts before execution
- **Template Generation**: Generate common workflow templates

## Installation

```bash
swift build -c release
.build/release/dicom-script --help
```

## Usage

### Run Command

Execute a DICOM workflow script:

```bash
# Basic execution
dicom-script run workflow.dcmscript

# With variables
dicom-script run workflow.dcmscript --var INPUT_DIR=/data --var PATIENT_ID=12345

# Parallel execution
dicom-script run workflow.dcmscript --parallel

# Dry run (show what would be executed)
dicom-script run workflow.dcmscript --dry-run

# Verbose output with logging
dicom-script run workflow.dcmscript --verbose --log execution.log
```

### Validate Command

Validate a script before execution:

```bash
# Basic validation
dicom-script validate workflow.dcmscript

# Verbose validation
dicom-script validate workflow.dcmscript --verbose
```

### Template Command

Generate workflow script templates:

```bash
# Generate workflow template
dicom-script template workflow > workflow.dcmscript

# Generate pipeline template
dicom-script template pipeline > pipeline.dcmscript

# Generate query template
dicom-script template query > query.dcmscript

# Generate archive template
dicom-script template archive > archive.dcmscript

# Generate anonymization template
dicom-script template anonymize > anonymize.dcmscript
```

## Script Syntax

### Basic Commands

Execute DICOM tools directly:

```bash
# Single command
dicom-info file.dcm

# Command with arguments
dicom-convert input.dcm --output output.png --format png

# A directory with --recursive (tools run without a shell: *.dcm and > are not expanded)
dicom-validate studies/ --recursive --level 2
```

### Variables

Define and use variables:

```bash
# Define variables
INPUT_DIR=/path/to/input
OUTPUT_DIR=/path/to/output
PATIENT_ID=12345

# Use variables
dicom-query --patient-id ${PATIENT_ID}
dicom-convert ${INPUT_DIR} --output ${OUTPUT_DIR} --recursive

# Alternative syntax
dicom-anon $INPUT_DIR --output $OUTPUT_DIR --recursive
```

### Pipelines

Chain commands together (sequential execution):

```bash
# Simple pipeline
dicom-query --patient-id 12345 | dicom-retrieve --output studies/

# Multi-stage pipeline
dicom-query --patient-name "DOE*" | \
dicom-retrieve --output studies/ | \
dicom-validate --level 2 | \
dicom-anon --profile ps315 --output anon/
```

### Conditional Logic

Execute commands based on conditions:

```bash
# Simple conditional
if exists /path/to/file.dcm
    dicom-info /path/to/file.dcm
endif

# Conditional with else (only dicom-* tools run: there is no echo or exit)
if exists ${INPUT_DIR}
    dicom-study summary ${INPUT_DIR}
else
    dicom-study summary ${FALLBACK_DIR}
endif

# Condition operators
if exists /path/to/file.dcm    # Check if file exists
if empty ${VARIABLE}            # Check if variable is empty
if equals ${VAR1} ${VAR2}       # Check if values are equal
```

### Comments

Add comments to scripts:

```bash
# This is a comment
# Comments start with # and are ignored

# Variables can be commented
# INPUT_DIR=/path/to/input

dicom-info file.dcm  # Inline comments are also supported
```

## Script Examples

### Example 1: Basic Workflow

```bash
# Define paths
INPUT_DIR=/data/dicom
OUTPUT_DIR=/data/processed

# Validate input files
dicom-validate ${INPUT_DIR} --recursive --level 2

# Convert to PNG
dicom-convert ${INPUT_DIR} --output ${OUTPUT_DIR} --format png --recursive

# Summarize the study (JSON goes to the script output / --log)
dicom-study summary ${INPUT_DIR} --format json
```

### Example 2: PACS Query and Retrieve

```bash
# PACS configuration
PACS_HOST=pacs.example.com
PACS_PORT=11112
PACS_AET=PACS
LOCAL_AET=WORKSTATION
PATIENT_ID=12345
# A Study Instance UID (0020,000D) returned by the query
STUDY_UID=1.2.3.4.5.6.7.8.9

# Query PACS (host is positional; --aet is the calling AE Title)
dicom-query ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --patient-id ${PATIENT_ID} --level study

# Query by a Study Date range: one PS3.4 C.2.2.2.5 range value
dicom-query ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --study-date 20240101-20241231 --level study

# Retrieve the study (dicom-retrieve retrieves by UID, not by Patient ID)
dicom-retrieve ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --study-uid ${STUDY_UID} --method c-get --output studies/

# Validate retrieved files
dicom-validate studies/ --recursive --level 2
```

### Example 3: Conditional Processing

```bash
# Input and output paths
INPUT_FILE=/data/study.dcm
OUTPUT_DIR=/data/processed

# Check if file exists before processing
if exists ${INPUT_FILE}
    # Validate file
    dicom-validate ${INPUT_FILE} --level 2
    
    # Convert to PNG
    dicom-convert ${INPUT_FILE} --output ${OUTPUT_DIR} --format png
    
    # Print the metadata (JSON goes to the script output / --log)
    dicom-info ${INPUT_FILE} --format json
else
    # The file is missing: dicom-info reports it and exits non-zero, and a failed
    # command stops the script with "Command failed with status 1" (no echo / exit 1)
    dicom-info ${INPUT_FILE}
endif
```

### Example 4: Anonymization Pipeline

```bash
# Paths
INPUT_DIR=/data/raw
TEMP_DIR=/data/temp
OUTPUT_DIR=/data/anonymized

# Validate input
dicom-validate ${INPUT_DIR} --recursive --level 2

# Anonymize with the PS3.15 Basic Application Level Confidentiality Profile
dicom-anon ${INPUT_DIR} --profile ps315 --output ${TEMP_DIR} --recursive

# Check for sensitive files
if exists ${INPUT_DIR}/sensitive.dcm
    # Also blank burned-in text in sensitive files (PS3.15 Clean Pixel Data Option)
    dicom-anon ${INPUT_DIR}/sensitive.dcm --profile ps315 --clean-pixel-data --output ${OUTPUT_DIR}
endif

# Move anonymized files
dicom-study organize ${TEMP_DIR} --output ${OUTPUT_DIR}

# Validate anonymized files
dicom-validate ${OUTPUT_DIR} --recursive --level 2
```

### Example 5: Multi-Stage Processing

```bash
# Configuration
SOURCE_DIR=/data/incoming
WORK_DIR=/data/work
ARCHIVE_DIR=/data/archive

# Step 1: Organize incoming files
dicom-study organize ${SOURCE_DIR} --output ${WORK_DIR}

# Step 2: Validate organized files
dicom-validate ${WORK_DIR} --recursive --level 2

# Step 3: Extract metadata (JSON goes to the script output / --log)
dicom-study summary ${WORK_DIR} --format json

# Step 4: Archive files
dicom-archive init --path ${ARCHIVE_DIR}
dicom-archive import ${WORK_DIR} --archive ${ARCHIVE_DIR} --recursive

# Step 5: Check the archive before the work directory is removed
dicom-archive check --archive ${ARCHIVE_DIR} --verify-files
dicom-archive stats --archive ${ARCHIVE_DIR}

# Scripts call only dicom-* tools (validate reports rm, echo or exit as unknown tools) and
# run them without a shell: delete ${WORK_DIR} outside the script once the check has passed.
```

## Supported Condition Operators

- `exists <path>` - Check if file or directory exists
- `empty <variable>` - Check if variable is empty
- `equals <value1> <value2>` - Check if two values are equal

## Supported DICOM Tools

All DICOMKit CLI tools are supported:

- `dicom-info` - Display metadata
- `dicom-convert` - Format conversion
- `dicom-validate` - Validation
- `dicom-anon` - Anonymization
- `dicom-dump` - Hex dump
- `dicom-query` - PACS query
- `dicom-send` - PACS send
- `dicom-diff` - File comparison
- `dicom-retrieve` - PACS retrieval
- `dicom-split` - Multi-frame extraction
- `dicom-merge` - Multi-frame creation
- `dicom-json` - JSON conversion
- `dicom-xml` - XML conversion
- `dicom-pdf` - PDF operations
- `dicom-image` - Image conversion
- `dicom-dcmdir` - DICOMDIR management
- `dicom-archive` - Archive management
- `dicom-export` - Export operations
- `dicom-qr` - Query/Retrieve
- `dicom-wado` - DICOMweb client
- `dicom-echo` - Network testing
- `dicom-mwl` - Worklist management
- `dicom-mpps` - MPPS operations
- `dicom-pixedit` - Pixel editing
- `dicom-tags` - Tag manipulation
- `dicom-uid` - UID management
- `dicom-compress` - Compression
- `dicom-study` - Study management

## Error Handling

The tool provides comprehensive error handling:

- **Script Not Found**: Specified script file does not exist
- **Parse Error**: Syntax error in script (with line number)
- **Invalid Variable**: Malformed variable assignment
- **Invalid Command**: Unknown DICOM tool (scripts call only the `dicom-*` tools listed above: `validate` reports any other command, such as `echo`, `exit` or `rm`, as an unknown DICOM tool, and the runner starts commands without a shell, so shell built-ins, globs and `>` do not work)
- **Execution Error**: Command execution failed
- **Condition Error**: Invalid condition syntax

## Logging

Scripts can log execution details:

```bash
# Enable verbose logging
dicom-script run workflow.dcmscript --verbose

# Write logs to file
dicom-script run workflow.dcmscript --log execution.log

# Both verbose and file logging
dicom-script run workflow.dcmscript --verbose --log execution.log
```

Log format:
```
[2024-01-15 10:30:45] Starting script execution: workflow.dcmscript
[2024-01-15 10:30:45] Variables: ["INPUT_DIR": "/data/input"]
[2024-01-15 10:30:45] Executing: dicom-validate /data/input --recursive --level 2
[2024-01-15 10:30:46] Output: Validated 10 files successfully
[2024-01-15 10:30:46] Script execution completed successfully
```

## Performance

- **Sequential Execution**: Commands run one after another by default
- **Parallel Execution**: Use `--parallel` flag for concurrent execution
- **Memory Efficient**: Streams data between pipeline stages
- **Error Recovery**: Continues execution after non-fatal errors (when appropriate)

## Version

dicom-script v1.3.5 - Part of DICOMKit CLI Tools Suite

## See Also

- All DICOMKit CLI tools for use in scripts
- Shell scripting for advanced workflows
- Make/rake for build automation
