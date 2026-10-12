# DICOMToolbox User Guide

## Overview

DICOMToolbox is a native macOS SwiftUI application that provides a graphical interface for all 29 DICOMKit command-line tools. Designed with an educational-first philosophy, DICOMToolbox makes DICOM file inspection, processing, networking, and automation accessible to both beginners and experienced medical imaging professionals.

Rather than replacing the command-line tools, DICOMToolbox acts as a visual command builder — every action generates the equivalent CLI command, helping users learn while they work.

### System Requirements

| Requirement       | Minimum                        |
|-------------------|--------------------------------|
| Operating System  | macOS 14.0 (Sonoma) or later   |
| Architecture      | Apple Silicon or Intel (x86_64)|
| Memory            | 4 GB RAM (8 GB recommended)    |
| Disk Space        | 50 MB for application          |
| Display           | 1280 × 800 minimum resolution  |

### Key Capabilities

- Visual parameter configuration for all 29 DICOM CLI tools
- Real-time command preview with syntax highlighting
- Drag-and-drop file handling
- Persistent PACS network configuration with server profiles
- In-app command execution with console output
- Command history with export support
- Beginner and Advanced modes
- Built-in DICOM glossary and example presets
- Full Dark Mode and accessibility support

---

## Getting Started

### Installation

**Via Homebrew:**

```bash
brew tap dicomkit/tap
brew install dicomtoolbox
```

**Via Swift Package Manager (build from source):**

```bash
git clone https://github.com/dicomkit/DICOMKit.git
cd DICOMKit
swift build -c release --product DICOMToolbox
```

**Via DMG Download:**

Download the latest release from the [DICOMKit Releases](https://github.com/dicomkit/DICOMKit/releases) page. Open the DMG and drag DICOMToolbox to your Applications folder.

### First Launch

On first launch, DICOMToolbox opens in **Beginner Mode** with a guided welcome panel. The welcome panel introduces the application layout and offers to configure a PACS connection. You can dismiss it and return to it later from **Help → Welcome Guide**.

---

## Application Layout

DICOMToolbox uses a structured layout with four main regions:

```
┌──────────────────────────────────────────────────────┐
│              Network Configuration Bar                │
├────────────┬─────────────────────────────────────────┤
│            │                                         │
│  Tool      │       Parameter Configuration           │
│  Sidebar   │              Panel                      │
│            │                                         │
├────────────┴─────────────────────────────────────────┤
│  [ File Inspection | Processing | Organization |     │
│    Data Export | Network Ops | Automation ]           │
├──────────────────────────────────────────────────────┤
│                Console Output                        │
│  ┌──────────────────────────────────────────────┐    │
│  │ $ dicom-info --tags 0010 patient.dcm         │    │
│  │ Patient Name: DOE^JOHN                       │    │
│  │ ...                                          │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Network Configuration Bar

The persistent bar at the top of the window holds PACS connection settings used by all network tools. Fields include:

| Field       | Description                              | Example          |
|-------------|------------------------------------------|------------------|
| Host        | PACS server hostname or IP address       | `192.168.1.100`  |
| Port        | PACS server port number                  | `11112`          |
| Called AE   | Application Entity title of the server   | `ORTHANC`        |
| Calling AE  | Your local Application Entity title      | `DICOMTOOLBOX`   |

A **Test Connection** button sends a C-ECHO to verify connectivity. A **Profile** dropdown lets you switch between saved server profiles.

### Tool Sidebar

Each tab displays a vertical list of tools on the left. Click a tool to load its parameter configuration panel. The sidebar shows the tool name and a brief description.

### Parameter Configuration Panel

The central area dynamically renders controls for the selected tool's parameters: file pickers, text fields, toggles, dropdowns, sliders, and date pickers. Parameters are mapped to their CLI equivalents and update the command preview in real time.

### Tab Bar

Six tabs group the 29 tools by category:

1. **File Inspection** — Examine DICOM file contents
2. **File Processing** — Transform and validate files
3. **File Organization** — Split, merge, and manage file collections
4. **Data Export** — Convert to JSON, XML, PDF, and image formats
5. **Network Operations** — PACS connectivity and data exchange
6. **Automation** — Study management, UID utilities, and scripting

### Console

The bottom panel displays the generated CLI command and its execution output. It uses a monospaced font (SF Mono) with syntax highlighting:

| Element     | Color  |
|-------------|--------|
| Tool name   | **Bold** |
| Flags       | Blue   |
| Values      | Green  |
| File paths  | Orange |

---

## Network Configuration

### Setting Up a PACS Connection

1. Enter the PACS server **Host**, **Port**, **Called AE Title**, and your **Calling AE Title** in the network configuration bar.
2. Click **Test Connection** to send a C-ECHO and verify the server responds.
3. A green checkmark indicates success; a red indicator shows the connection failed with an error message.

### Server Profiles

Save frequently used server configurations as profiles:

1. Configure the connection fields.
2. Click the **Profile** dropdown → **Save Current as Profile…**
3. Enter a descriptive name (e.g., "Radiology PACS", "Research Orthanc").

Switch between profiles using the dropdown. Profiles are stored locally and persist across sessions.

### Quick Presets

DICOMToolbox includes built-in presets for common configurations:

- **Local Orthanc** — `localhost:8042`, AE Title `ORTHANC`
- **Local DCM4CHEE** — `localhost:11112`, AE Title `DCM4CHEE`

Select a preset from **Profile → Presets** to populate the fields instantly.

---

## Tool Categories

### Tab 1: File Inspection

Tools for examining DICOM file contents and metadata.

#### dicom-info

Display DICOM metadata with filtering and statistics. Select a file or drag it onto the panel, then choose which tag groups to display. Supports output filtering by tag group, keyword search, and summary statistics.

#### dicom-dump

Hex dump of raw DICOM data with byte-level annotation. Useful for debugging encoding issues or inspecting the binary structure of DICOM files. Configure offset range and annotation verbosity.

#### dicom-tags

View and edit DICOM tags. Supports set, delete, and copy operations on individual tags. Use the tag browser to select tags by group/element number or keyword.

#### dicom-diff

Compare two DICOM files side by side with configurable tolerance for numeric values. Highlights differences in metadata and pixel data. Useful for verifying anonymization or conversion results.

### Tab 2: File Processing

Tools for transforming and validating DICOM files.

#### dicom-convert

Convert between DICOM transfer syntaxes and file formats. Select source and target transfer syntax from dropdowns. Supports batch conversion of entire directories.

#### dicom-validate

Validate DICOM conformance at multiple levels: file structure, IOD (Information Object Definition), and network protocol compliance. Displays validation results with severity levels and references to the DICOM standard.

#### dicom-anon

De-identify to the DICOM standard: the PS3.15 Annex E Basic Application Level
Confidentiality Profile is always applied to the header, and burned-in text is blanked
out of the pixels (Clean Pixel Data, on by default, with on-device OCR). The panel
offers only the standard's retention options:

| Option                        | Keeps                                              |
|-------------------------------|----------------------------------------------------|
| Retain Dates / Shift Dates    | dates as-is, or shifted so intervals survive       |
| Retain Patient Characteristics| age, sex, size, weight                             |
| Retain Device Identity        | model, station name, serial number                 |
| Retain Institution Identity   | institution name, address, department              |
| Retain UIDs                   | UIDs instead of regenerating them                  |
| Clean Descriptors             | study/series descriptions                          |

Burned In Annotation = YES is cleaned; absent, OCR decides; NO is trusted.

#### dicom-compress

Manage DICOM file compression. Subcommands include compress, decompress, info (show current encoding), and batch processing. Select compression codec and quality parameters from the panel.

### Tab 3: File Organization

Tools for managing collections of DICOM files.

#### dicom-split

Split multi-frame DICOM files into individual single-frame files. Configure output naming patterns and destination directory.

#### dicom-merge

Merge multiple single-frame DICOM files into a multi-frame file. Supports sorting by instance number, acquisition time, or custom tag before merging.

#### dicom-dcmdir

Create and manage DICOMDIR index files. Subcommands: create a new DICOMDIR, validate an existing one, dump its contents, or update it with new files.

#### dicom-archive

Archive management operations for organizing DICOM file collections. Supports creating structured archives from loose files.

### Tab 4: Data Export

Tools for converting DICOM data to other formats.

#### dicom-json

Convert DICOM files to JSON format and back. Supports the DICOM JSON Model (PS3.18 Annex F) for standards-compliant output.

#### dicom-xml

Convert DICOM files to XML format and back. Supports the DICOM XML (Native) format defined in PS3.19.

#### dicom-pdf

Encapsulate a PDF document inside a DICOM file or extract an embedded PDF from an Encapsulated PDF SOP Instance.

#### dicom-image

Encapsulate standard image files (JPEG, PNG, TIFF) as DICOM Secondary Capture objects with appropriate metadata.

#### dicom-export

Export DICOM pixel data as images. Subcommands include single-frame export, contact sheet generation, animated GIF/MP4 creation, and bulk export of entire series.

#### dicom-pixedit

Edit pixel data with operations like masking (burn-in redaction), cropping, region inversion, and windowing adjustments. Configure regions visually or by coordinates.

### Tab 5: Network Operations

Tools for PACS connectivity and DICOM network operations. These tools use the connection settings from the Network Configuration Bar.

#### dicom-echo

Test PACS connectivity by sending a C-ECHO request (DICOM "ping"). Confirms that the remote server is reachable and responds to association requests.

#### dicom-query

Perform C-FIND queries against a PACS. Build search criteria using the parameter panel: patient name, ID, study date range, modality, and more. Results display in a table.

#### dicom-send

Send DICOM files to a PACS using C-STORE. Drag files onto the panel or use the file picker. Supports batch sending with progress indication.

#### dicom-retrieve

Retrieve studies or series from a PACS using C-MOVE or C-GET. Specify the destination AE title and storage directory. Supports retrieval at study, series, or instance level.

#### dicom-qr

Combined query-and-retrieve workflow. First query the PACS to find matching studies, then select results to retrieve in a single operation.

#### dicom-wado

Access DICOMweb services. Subcommands include WADO-RS retrieve, QIDO-RS query, STOW-RS store, and UPS-RS worklist operations. Configure the DICOMweb base URL in the parameter panel.

#### dicom-mwl

Query a Modality Worklist (MWL) server to retrieve scheduled procedure information. Configure query filters for scheduled date, modality, and station.

#### dicom-mpps

Send Modality Performed Procedure Step (MPPS) messages. Create an in-progress notification or update with completion status and dose information.

### Tab 6: Automation

Tools for study management, UID operations, and scripting.

#### dicom-study

Study-level management operations. Subcommands: organize files into study/series folders, generate study summaries, check study completeness, compute statistics, and compare studies.

#### dicom-uid

DICOM UID utilities. Generate new UIDs, validate existing ones, look up well-known UID definitions, or regenerate all UIDs in a file for de-identification.

#### dicom-script

Execute DICOMKit automation scripts. Run a script file, validate script syntax, or generate a script from a built-in template. Useful for batch processing workflows.

---

## File Handling

### Drag-and-Drop

DICOMToolbox supports drag-and-drop throughout the application:

- **Single files** — Drop a `.dcm` file onto the parameter panel to populate the input file field.
- **Multiple files** — Drop a folder or multiple files for batch operations.
- **Cross-tab** — Drag a file onto a different tab to switch tabs and load the file simultaneously.

Visual feedback is provided during drag operations:
- A highlighted drop zone appears when a valid file is dragged over the panel.
- A badge shows the number of files being dropped.
- Invalid file types show a "not allowed" indicator.

### File Picker

Click any file input field to open a standard macOS file picker. The picker is pre-configured with appropriate file type filters (e.g., `.dcm` for DICOM files, `.json` for JSON export).

---

## Command Building and Execution

### Building Commands

As you configure parameters in the panel, the console area updates in real time to show the equivalent CLI command. This serves both as a preview before execution and as a learning tool.

Example preview:

```
$ dicom-anon --shift-dates 100 --output ./anonymized/ patient_study.dcm
```

### Executing Commands

1. Configure all required parameters (required fields are marked with an asterisk).
2. Review the command in the console preview.
3. Click the **Run** button (▶) or press **⌘R** to execute.
4. Output streams into the console in real time.
5. A status indicator shows success (✅) or failure (❌) upon completion.

### Stopping Execution

Click the **Stop** button (■) or press **⌘.** to cancel a running command.

---

## Command History

DICOMToolbox stores the last 50 executed commands. Access history from **View → Command History** or press **⌘Y**.

### History Features

- **Reload** — Click a history entry to repopulate the parameter panel with those settings.
- **Copy** — Copy any historical command to the clipboard.
- **Export** — Export the full history as a shell script for automation.
- **Search** — Filter history by tool name or parameter values.
- **Clear** — Remove all history entries from **Edit → Clear History**.

---

## Educational Features

### Beginner Mode

Enabled by default on first launch. In Beginner Mode:

- Advanced and rarely used parameters are hidden.
- Each visible parameter includes an expandable explanation.
- Tooltips provide DICOM standard references.
- A contextual help sidebar offers guidance for the selected tool.

Switch between modes from **View → Beginner Mode** or the toolbar toggle.

### Advanced Mode

Reveals all parameters and options for every tool. Intended for experienced users who need full control over command construction.

### DICOM Glossary

A searchable reference of DICOM terminology accessible from **Help → DICOM Glossary** or **⌥⌘G**. Entries include:

- Term definition
- Related DICOM standard section (e.g., PS3.3, PS3.5)
- Cross-references to related terms
- Context for how the term applies in DICOMToolbox

### Example Presets

Each tool includes one or more example presets that pre-fill the parameter panel with common configurations. Access presets from the **Examples** button in the parameter panel toolbar.

Examples include:
- **dicom-info**: "Show Patient Demographics", "List All Private Tags"
- **dicom-anon**: "De-identify (Basic Profile)", "Longitudinal study (shifted dates)"
- **dicom-query**: "Find Today's CT Studies", "Search by Patient ID"
- **dicom-export**: "Export as PNG", "Create Contact Sheet"

---

## Settings and Preferences

Open Preferences from **DICOMToolbox → Settings…** or **⌘,**.

### General

| Setting                  | Description                                      | Default        |
|--------------------------|--------------------------------------------------|----------------|
| Mode                     | Beginner or Advanced                             | Beginner       |
| Default output directory | Where exported files are saved                   | `~/Desktop`    |
| History size             | Maximum number of commands to retain             | 50             |
| Confirm before execute   | Show confirmation dialog before running commands | On             |

### Appearance

| Setting       | Description                               | Default |
|---------------|-------------------------------------------|---------|
| Theme         | Light, Dark, or System                    | System  |
| Console font  | Monospaced font for console output        | SF Mono |
| Font size     | Console and parameter label font size     | 13 pt   |

### Network Defaults

| Setting           | Description                              | Default        |
|-------------------|------------------------------------------|----------------|
| Default Calling AE| Default local AE title                   | `DICOMTOOLBOX` |
| Connection timeout| Seconds before connection attempt fails  | 30             |
| Max associations  | Maximum concurrent network associations  | 5              |

### Keyboard Shortcuts

Customize any keyboard shortcut from the **Shortcuts** tab. See the [Keyboard Shortcuts Reference](DICOMToolbox-KeyboardShortcuts.md) for the full list of defaults.

---

## Troubleshooting

### Common Issues

**Problem: "Connection failed" when testing PACS connectivity**

- Verify the PACS server is running and reachable on the network.
- Check that the Host, Port, and AE Titles are correct.
- Ensure your firewall allows outbound connections on the configured port.
- Confirm the PACS server has your Calling AE Title in its allowed list.

**Problem: Drag-and-drop does not recognize my file**

- Ensure the file has a `.dcm` extension or is a valid DICOM file.
- Try using the file picker instead if the file lacks a standard extension.
- Check that the file is not currently locked or open in another application.

**Problem: Command execution produces no output**

- Verify the input file path is correct and the file exists.
- Check the console for error messages (scroll down if output is long).
- Try running the equivalent command in Terminal to isolate the issue.

**Problem: Application is slow with large files**

- DICOM files with large pixel data (e.g., multi-frame CT) may take time to process.
- Close unused tabs to free memory.
- Use the CLI tools directly in Terminal for batch processing of very large datasets.

**Problem: Parameter panel shows unexpected options**

- Switch to Advanced Mode to see all available parameters.
- Reset the tool parameters using **Edit → Reset Parameters** or **⌘⇧R**.

### Getting Help

- **In-app help**: Press **⌘?** or select **Help → DICOMToolbox Help**.
- **DICOM Glossary**: **Help → DICOM Glossary** or **⌥⌘G**.
- **Report an issue**: **Help → Report Issue** opens the GitHub issue tracker.
- **Community**: Visit the DICOMKit GitHub Discussions page.

---

## Tool Reference Card

Quick reference table of all 29 tools available in DICOMToolbox.

| #  | Tool             | Category            | Purpose                                              |
|----|------------------|---------------------|------------------------------------------------------|
| 1  | dicom-info       | File Inspection     | Display DICOM metadata with filtering and statistics |
| 2  | dicom-dump       | File Inspection     | Hex dump of DICOM data with annotation               |
| 3  | dicom-tags       | File Inspection     | View and edit DICOM tags                             |
| 4  | dicom-diff       | File Inspection     | Compare two DICOM files with tolerance               |
| 5  | dicom-convert    | File Processing     | Transfer syntax conversion and format transformation |
| 6  | dicom-validate   | File Processing     | DICOM conformance validation at multiple levels      |
| 7  | dicom-anon       | File Processing     | PS3.15 Annex E de-identification, header and pixels  |
| 8  | dicom-compress   | File Processing     | Compression management (compress/decompress/batch)   |
| 9  | dicom-split      | File Organization   | Split multi-frame files into individual frames       |
| 10 | dicom-merge      | File Organization   | Merge multiple files with sorting options            |
| 11 | dicom-dcmdir     | File Organization   | DICOMDIR creation, validation, and management        |
| 12 | dicom-archive    | File Organization   | Archive management operations                        |
| 13 | dicom-json       | Data Export         | Convert DICOM to/from JSON format                    |
| 14 | dicom-xml        | Data Export         | Convert DICOM to/from XML format                     |
| 15 | dicom-pdf        | Data Export         | Encapsulate or extract PDF in DICOM                  |
| 16 | dicom-image      | Data Export         | Encapsulate images as DICOM files                    |
| 17 | dicom-export     | Data Export         | Export DICOM images (single/sheet/animate/bulk)      |
| 18 | dicom-pixedit    | Data Export         | Pixel data editing (mask/crop/invert/window)         |
| 19 | dicom-echo       | Network Operations  | Test PACS connectivity (C-ECHO)                      |
| 20 | dicom-query      | Network Operations  | C-FIND queries with search criteria                  |
| 21 | dicom-send       | Network Operations  | Send files to PACS (C-STORE)                         |
| 22 | dicom-retrieve   | Network Operations  | Retrieve from PACS (C-MOVE/C-GET)                    |
| 23 | dicom-qr         | Network Operations  | Combined query-retrieve workflow                     |
| 24 | dicom-wado       | Network Operations  | DICOMweb access (WADO-RS/QIDO-RS/STOW-RS)           |
| 25 | dicom-mwl        | Network Operations  | Modality Worklist queries                            |
| 26 | dicom-mpps       | Network Operations  | Modality Performed Procedure Step management         |
| 27 | dicom-study      | Automation          | Study management (organize/summary/stats/compare)    |
| 28 | dicom-uid        | Automation          | UID generation, validation, and lookup               |
| 29 | dicom-script     | Automation          | Script execution and template generation             |

---

*DICOMToolbox v1.0.16 — Part of the DICOMKit project*
