import Foundation

/// Registry of all CLI tool definitions for the DICOMToolbox application
public enum ToolRegistry {
    /// All available tool definitions organized by category
    public static let allTools: [ToolDefinition] = [
        // Tab 1: File Inspection
        dicomInfo,
        dicomDump,
        dicomTags,
        dicomDiff,
        // Tab 2: File Processing
        dicomConvert,
        dicomValidate,
        dicomAnon,
        dicomCompress,
        // Tab 3: File Organization
        dicomSplit,
        dicomMerge,
        dicomDcmdir,
        dicomArchive,
        // Tab 4: Data Export
        dicomJson,
        dicomXml,
        dicomPdf,
        dicomImage,
        dicomExport,
        dicomPixedit,
        dicomReport,
        // Tab 5: Network Operations
        dicomEcho,
        dicomQuery,
        dicomSend,
        dicomRetrieve,
        dicomQR,
        dicomWado,
        dicomMWL,
        dicomMPPS,
        // Tab 6: Automation
        dicomStudy,
        dicomUID,
        dicomScript,
    ]

    /// Returns tools filtered by category
    public static func tools(for category: ToolCategory) -> [ToolDefinition] {
        allTools.filter { $0.category == category }
    }

    /// Looks up a tool by its ID
    public static func tool(withID id: String) -> ToolDefinition? {
        allTools.first { $0.id == id }
    }

    // MARK: - File Inspection Tools

    public static let dicomInfo = ToolDefinition(
        id: "dicom-info",
        name: "DICOM Info",
        icon: "info.circle",
        category: .fileInspection,
        description: "Display DICOM file metadata and header information",
        discussion: "Reads and displays metadata from DICOM files including patient demographics, study information, and technical parameters.",
        parameters: [
            ParameterDefinition(id: "filePath", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "format", cliFlag: "--format", shortFlag: "-f", label: "Output Format", help: "Output format", type: .enumeration, defaultValue: "text", enumValues: [
                EnumValue(label: "Text", value: "text", description: "Human-readable text output"),
                EnumValue(label: "JSON", value: "json", description: "Machine-readable JSON output"),
                EnumValue(label: "CSV", value: "csv", description: "Comma-separated values"),
            ]),
            ParameterDefinition(id: "tag", cliFlag: "--tag", shortFlag: "-t", label: "Filter Tags", help: "Filter specific tags", type: .repeatable),
            ParameterDefinition(id: "show-private", cliFlag: "--show-private", label: "Show Private Tags", help: "Include private tags in output", type: .boolean),
            ParameterDefinition(id: "statistics", cliFlag: "--statistics", label: "Show Statistics", help: "Show file statistics", type: .boolean),
            ParameterDefinition(id: "force", cliFlag: "--force", label: "Force Parse", help: "Parse without DICM prefix", type: .boolean),
        ]
    )

    public static let dicomDump = ToolDefinition(
        id: "dicom-dump",
        name: "DICOM Dump",
        icon: "doc.text",
        category: .fileInspection,
        description: "Hex dump of DICOM data elements",
        discussion: "Provides a detailed hex dump of DICOM file contents for low-level inspection and debugging.",
        parameters: [
            ParameterDefinition(id: "filePath", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "tag", cliFlag: "--tag", label: "Filter Tag", help: "Filter specific tag", type: .string),
            ParameterDefinition(id: "offset", cliFlag: "--offset", label: "Offset", help: "Start offset in hex", type: .string),
            ParameterDefinition(id: "length", cliFlag: "--length", label: "Length", help: "Number of bytes to display", type: .integer),
            ParameterDefinition(id: "bytes-per-line", cliFlag: "--bytes-per-line", label: "Bytes Per Line", help: "Number of bytes per line", type: .integer, defaultValue: "16"),
            ParameterDefinition(id: "annotate", cliFlag: "--annotate", label: "Annotate", help: "Add annotations to hex output", type: .boolean),
            ParameterDefinition(id: "no-color", cliFlag: "--no-color", label: "No Color", help: "Disable color output", type: .boolean),
            ParameterDefinition(id: "force", cliFlag: "--force", label: "Force Parse", help: "Parse without DICM prefix", type: .boolean),
        ]
    )

    public static let dicomTags = ToolDefinition(
        id: "dicom-tags",
        name: "DICOM Tags",
        icon: "tag",
        category: .fileInspection,
        description: "View and edit DICOM tags",
        discussion: "Inspect and modify DICOM tag values in files.",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file path", type: .file),
            ParameterDefinition(id: "set", cliFlag: "--set", label: "Set Tags", help: "Set tag values (TAG=VALUE)", type: .repeatable),
            ParameterDefinition(id: "delete", cliFlag: "--delete", label: "Delete Tags", help: "Tags to delete", type: .repeatable),
            ParameterDefinition(id: "copy-from", cliFlag: "--copy-from", label: "Copy From", help: "Copy tags from another file", type: .file),
            ParameterDefinition(id: "tags", cliFlag: "--tags", label: "Tag List File", help: "File containing tag list", type: .file),
            ParameterDefinition(id: "delete-private", cliFlag: "--delete-private", label: "Delete Private", help: "Delete all private tags", type: .boolean),
            ParameterDefinition(id: "dry-run", cliFlag: "--dry-run", label: "Dry Run", help: "Preview changes without writing", type: .boolean),
        ]
    )

    public static let dicomDiff = ToolDefinition(
        id: "dicom-diff",
        name: "DICOM Diff",
        icon: "arrow.left.arrow.right",
        category: .fileInspection,
        description: "Compare two DICOM files",
        discussion: "Shows differences between two DICOM files including metadata and optionally pixel data.",
        parameters: [
            ParameterDefinition(id: "file1", cliFlag: "@argument", label: "File 1", help: "First DICOM file to compare", type: .file, isRequired: true),
            ParameterDefinition(id: "file2", cliFlag: "@argument", label: "File 2", help: "Second DICOM file to compare", type: .file, isRequired: true),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Output format", type: .enumeration, defaultValue: "text", enumValues: [
                EnumValue(label: "Text", value: "text"),
                EnumValue(label: "JSON", value: "json"),
                EnumValue(label: "Summary", value: "summary"),
            ]),
            ParameterDefinition(id: "ignore-tag", cliFlag: "--ignore-tag", label: "Ignore Tags", help: "Tags to ignore in comparison", type: .repeatable),
            ParameterDefinition(id: "tolerance", cliFlag: "--tolerance", label: "Tolerance", help: "Numeric comparison tolerance", type: .string),
            ParameterDefinition(id: "ignore-private", cliFlag: "--ignore-private", label: "Ignore Private", help: "Skip private tags", type: .boolean),
            ParameterDefinition(id: "compare-pixels", cliFlag: "--compare-pixels", label: "Compare Pixels", help: "Compare pixel data", type: .boolean),
            ParameterDefinition(id: "quick", cliFlag: "--quick", label: "Quick Mode", help: "Stop at first difference", type: .boolean),
            ParameterDefinition(id: "show-identical", cliFlag: "--show-identical", label: "Show Identical", help: "Show matching tags too", type: .boolean),
        ]
    )

    // MARK: - File Processing Tools

    public static let dicomConvert = ToolDefinition(
        id: "dicom-convert",
        name: "DICOM Convert",
        icon: "arrow.triangle.2.circlepath",
        category: .fileProcessing,
        description: "Convert DICOM transfer syntax or export to image formats",
        discussion: "Converts DICOM files between transfer syntaxes (e.g., Implicit VR to Explicit VR Little Endian) or exports pixel data to standard image formats like PNG, JPEG, and TIFF. Supports windowing parameters for proper visualization of medical images.",
        parameters: [
            ParameterDefinition(id: "inputPath", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Path", help: "Output file or directory", type: .file, isRequired: true),
            ParameterDefinition(id: "transfer-syntax", cliFlag: "--transfer-syntax", label: "Transfer Syntax", help: "Target transfer syntax", discussion: "Transfer syntax defines how DICOM data is encoded: byte ordering (Little vs Big Endian), Value Representation encoding (Explicit vs Implicit), and compression.", type: .enumeration, enumValues: [
                EnumValue(label: "Explicit VR LE", value: "explicit-vr-le", description: "Most common modern encoding with explicit type information"),
                EnumValue(label: "Implicit VR LE", value: "implicit-vr-le", description: "Legacy encoding requiring a data dictionary for type lookup"),
                EnumValue(label: "Explicit VR BE", value: "explicit-vr-be", description: "Big endian byte ordering (rarely used)"),
                EnumValue(label: "DEFLATE", value: "deflate", description: "Lossless compression using DEFLATE algorithm"),
            ]),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Image output format", type: .enumeration, enumValues: [
                EnumValue(label: "DICOM", value: "dicom", description: "DICOM format with converted transfer syntax"),
                EnumValue(label: "PNG", value: "png", description: "Lossless image format"),
                EnumValue(label: "JPEG", value: "jpeg", description: "Lossy compressed image format"),
                EnumValue(label: "TIFF", value: "tiff", description: "High-quality image format"),
            ]),
            ParameterDefinition(id: "quality", cliFlag: "--quality", label: "JPEG Quality", help: "JPEG quality (1-100)", type: .integer, defaultValue: "85", validation: ValidationRule(minValue: 1, maxValue: 100)),
            ParameterDefinition(id: "window-center", cliFlag: "--window-center", label: "Window Center", help: "Center of the display window", type: .string),
            ParameterDefinition(id: "window-width", cliFlag: "--window-width", label: "Window Width", help: "Width of the display window", type: .string),
            ParameterDefinition(id: "frame", cliFlag: "--frame", label: "Frame Number", help: "Frame to extract (0-indexed)", type: .integer),
            ParameterDefinition(id: "apply-window", cliFlag: "--apply-window", label: "Apply Window", help: "Apply window center/width values", type: .boolean),
            ParameterDefinition(id: "strip-private", cliFlag: "--strip-private", label: "Strip Private", help: "Remove private tags", type: .boolean),
            ParameterDefinition(id: "validate", cliFlag: "--validate", label: "Validate Output", help: "Validate output files", type: .boolean),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process directories recursively", type: .boolean),
            ParameterDefinition(id: "force", cliFlag: "--force", label: "Force Parse", help: "Parse files without DICM preamble", type: .boolean),
        ]
    )

    public static let dicomValidate = ToolDefinition(
        id: "dicom-validate",
        name: "DICOM Validate",
        icon: "checkmark.shield",
        category: .fileProcessing,
        description: "Validate DICOM conformance",
        discussion: "Validates DICOM files against the DICOM standard at multiple strictness levels, from basic structure checks to full IOD conformance validation. Generates detailed reports identifying non-conforming elements.",
        parameters: [
            ParameterDefinition(id: "inputPath", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "level", cliFlag: "--level", label: "Validation Level", help: "Validation strictness level", discussion: "Level 1: Basic structure. Level 2: Standard compliance. Level 3: IOD validation. Level 4: Full conformance.", type: .enumeration, defaultValue: "1", enumValues: [
                EnumValue(label: "Level 1", value: "1", description: "Basic structure validation"),
                EnumValue(label: "Level 2", value: "2", description: "Standard compliance checks"),
                EnumValue(label: "Level 3", value: "3", description: "IOD-specific validation"),
                EnumValue(label: "Level 4", value: "4", description: "Full conformance testing"),
            ]),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Report format", type: .enumeration, defaultValue: "text", enumValues: [
                EnumValue(label: "Text", value: "text", description: "Human-readable text report"),
                EnumValue(label: "JSON", value: "json", description: "Machine-readable JSON report"),
            ]),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output report file", type: .file),
            ParameterDefinition(id: "detailed", cliFlag: "--detailed", label: "Detailed Report", help: "Include detailed findings", type: .boolean),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process directories recursively", type: .boolean),
            ParameterDefinition(id: "strict", cliFlag: "--strict", label: "Strict Mode", help: "Treat warnings as errors", type: .boolean),
            ParameterDefinition(id: "force", cliFlag: "--force", label: "Force Parse", help: "Parse files without DICM preamble", type: .boolean),
        ]
    )

    public static let dicomAnon = ToolDefinition(
        id: "dicom-anon",
        name: "DICOM Anonymize",
        icon: "person.fill.questionmark",
        category: .fileProcessing,
        description: "Anonymize patient data in DICOM files",
        discussion: "Applies the CLI’s PS3.15 Basic Application Level Confidentiality Profile and default pixel-cleaning workflow. Retention options are explicit; a profile label does not certify that an output is de-identified. Review the output before release.",
        parameters: [
            ParameterDefinition(id: "inputPath", cliFlag: "@argument", label: "Input File", help: "Path to the DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Path", help: "Output file or directory", type: .file),
            ParameterDefinition(id: "profile", cliFlag: "--profile", label: "Profile", help: "PS3.15 Basic Application Level Confidentiality Profile; basic is an alias", type: .enumeration, defaultValue: "ps315", enumValues: [
                EnumValue(label: "PS3.15", value: "ps315", description: "Basic Application Level Confidentiality Profile; review retention options and output."),
                EnumValue(label: "Basic (alias)", value: "basic", description: "Alias for the same PS3.15 workflow; not a separate retention policy."),
            ]),
            ParameterDefinition(id: "shift-dates", cliFlag: "--shift-dates", label: "Date Shift (days)", help: "Retain Longitudinal Temporal Information With Modified Dates Option: shift dates by N days", type: .integer),
            ParameterDefinition(id: "retain-uids", cliFlag: "--retain-uids", label: "Retain UIDs", help: "Retain UIDs Option: preserve original UIDs. Off regenerates UIDs consistently.", type: .boolean),
            ParameterDefinition(id: "remove", cliFlag: "--remove", label: "Tags to Remove", help: "Tags to remove", type: .repeatable),
            ParameterDefinition(id: "replace", cliFlag: "--replace", label: "Tags to Replace", help: "Tags to replace (TAG=VALUE)", type: .repeatable),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process directories recursively", type: .boolean),
            ParameterDefinition(id: "dry-run", cliFlag: "--dry-run", label: "Dry Run", help: "Preview changes", type: .boolean),
            ParameterDefinition(id: "backup", cliFlag: "--backup", label: "Create Backup", help: "Back up original files", type: .boolean),
            ParameterDefinition(id: "audit-log", cliFlag: "--audit-log", label: "Audit Log", help: "Audit log file", type: .file),
        ]
    )

    public static let dicomCompress = ToolDefinition(
        id: "dicom-compress",
        name: "DICOM Compress",
        icon: "archivebox",
        category: .fileProcessing,
        description: "Manage DICOM file compression",
        discussion: "Compresses or decompresses DICOM files using industry-standard codecs including JPEG, JPEG 2000, JPEG-LS, and RLE. Supports single file and batch operations with configurable quality settings.",
        subcommands: [
            SubcommandDefinition(id: "compress", name: "Compress", description: "Compress DICOM files", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "File to compress", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file),
                ParameterDefinition(id: "codec", cliFlag: "--codec", label: "Codec", help: "Compression codec", type: .enumeration, enumValues: [
                    EnumValue(label: "JPEG", value: "jpeg"),
                    EnumValue(label: "JPEG 2000", value: "jpeg2000"),
                    EnumValue(label: "JPEG-LS", value: "jpeg-ls"),
                    EnumValue(label: "RLE", value: "rle"),
                ]),
                ParameterDefinition(id: "quality", cliFlag: "--quality", label: "Quality", help: "Compression quality (1-100)", type: .integer, validation: ValidationRule(minValue: 1, maxValue: 100)),
            ]),
            SubcommandDefinition(id: "decompress", name: "Decompress", description: "Decompress DICOM files", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "File to decompress", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file),
            ]),
            SubcommandDefinition(id: "info", name: "Info", description: "Show compression details", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "File to inspect", type: .file, isRequired: true),
            ]),
            SubcommandDefinition(id: "batch", name: "Batch", description: "Batch compress files", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Directory", help: "Directory to process", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file),
                ParameterDefinition(id: "codec", cliFlag: "--codec", label: "Codec", help: "Compression codec", type: .enumeration, enumValues: [
                    EnumValue(label: "JPEG", value: "jpeg"),
                    EnumValue(label: "JPEG 2000", value: "jpeg2000"),
                ]),
                ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
            ]),
        ]
    )

    // MARK: - File Organization Tools

    public static let dicomSplit = ToolDefinition(
        id: "dicom-split",
        name: "DICOM Split",
        icon: "rectangle.split.3x1",
        category: .fileOrganization,
        description: "Split multi-frame DICOM files",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "Multi-frame DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file),
            ParameterDefinition(id: "frames", cliFlag: "--frames", label: "Frame Range", help: "Frame range (e.g., 1-10)", type: .string),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Output format", type: .enumeration, enumValues: [
                EnumValue(label: "DICOM", value: "dicom"),
                EnumValue(label: "PNG", value: "png"),
                EnumValue(label: "JPEG", value: "jpeg"),
            ]),
            ParameterDefinition(id: "target", cliFlag: "--target", label: "Target SOP Class", help: "auto: classic single-frame class when one exists; same: keep the source class", type: .enumeration, enumValues: [
                EnumValue(label: "Auto", value: "auto"),
                EnumValue(label: "Same class", value: "same"),
                EnumValue(label: "Classic only", value: "classic"),
            ]),
            ParameterDefinition(id: "pixel-handling", cliFlag: "--pixel-handling", label: "Compressed Pixels", help: "Keep the transfer syntax per frame or decode to native", type: .enumeration, enumValues: [
                EnumValue(label: "Preserve", value: "preserve"),
                EnumValue(label: "Decode", value: "decode"),
            ]),
            ParameterDefinition(id: "private-groups", cliFlag: "--private-groups", label: "Private Functional Groups", help: "Flatten, keep, or drop vendor functional groups", type: .enumeration, enumValues: [
                EnumValue(label: "Flatten", value: "flatten"),
                EnumValue(label: "Keep", value: "keep"),
                EnumValue(label: "Drop", value: "drop"),
            ]),
            ParameterDefinition(id: "instance-number", cliFlag: "--instance-number", label: "Instance Numbering", help: "frame: 1-based frame number; instack: In-Stack Position Number; original: unchanged", type: .enumeration, enumValues: [
                EnumValue(label: "Frame number", value: "frame"),
                EnumValue(label: "In-Stack Position", value: "instack"),
                EnumValue(label: "Original", value: "original"),
            ]),
            ParameterDefinition(id: "split-by", cliFlag: "--split-by", label: "Split Series By", help: "Write one series per stack or temporal position", type: .enumeration, enumValues: [
                EnumValue(label: "None", value: "none"),
                EnumValue(label: "Stack", value: "stack"),
                EnumValue(label: "Temporal position", value: "temporal"),
            ]),
            ParameterDefinition(id: "new-series", cliFlag: "--new-series", label: "New Series UID", help: "Mint a new Series Instance UID for the extracted frames", type: .boolean),
            ParameterDefinition(id: "frames-per", cliFlag: "--frames-per", label: "Frames per Part", help: "Write concatenation parts of N frames instead of single frames", type: .string),
            ParameterDefinition(id: "random-uids", cliFlag: "--random-uids", label: "Random UIDs", help: "Generate random SOP/Series UIDs instead of deriving them from the source", type: .boolean),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
        ]
    )

    public static let dicomMerge = ToolDefinition(
        id: "dicom-merge",
        name: "DICOM Merge",
        icon: "rectangle.compress.vertical",
        category: .fileOrganization,
        description: "Merge DICOM files",
        parameters: [
            ParameterDefinition(id: "inputs", cliFlag: "@argument", label: "Input Files", help: "Files to merge", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file, isRequired: true),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Multi-frame object to build", type: .enumeration, enumValues: [
                EnumValue(label: "Standard", value: "standard"),
                EnumValue(label: "Auto (from source)", value: "auto"),
                EnumValue(label: "Enhanced CT", value: "enhanced-ct"),
                EnumValue(label: "Enhanced MR", value: "enhanced-mr"),
                EnumValue(label: "Enhanced PET", value: "enhanced-pet"),
                EnumValue(label: "Enhanced XA", value: "enhanced-xa"),
                EnumValue(label: "Enhanced XRF", value: "enhanced-xrf"),
                EnumValue(label: "Legacy Converted CT", value: "legacy-converted-ct"),
                EnumValue(label: "Legacy Converted MR", value: "legacy-converted-mr"),
                EnumValue(label: "Legacy Converted PET", value: "legacy-converted-pet"),
                EnumValue(label: "Multi-frame SC", value: "sc-multiframe"),
                EnumValue(label: "US Multi-frame", value: "us-multiframe"),
            ]),
            ParameterDefinition(id: "pixel-handling", cliFlag: "--pixel-handling", label: "Compressed Pixels", help: "Keep the transfer syntax (one fragment per frame) or decode to native", type: .enumeration, enumValues: [
                EnumValue(label: "Preserve", value: "preserve"),
                EnumValue(label: "Decode", value: "decode"),
            ]),
            ParameterDefinition(id: "make-stacks", cliFlag: "--make-stacks", label: "Make Stacks", help: "Group frames into stacks by orientation", type: .boolean),
            ParameterDefinition(id: "temporal-position", cliFlag: "--temporal-position", label: "Temporal Positions", help: "Derive Temporal Position Index from Trigger Time / Acquisition Time", type: .boolean),
            ParameterDefinition(id: "new-series", cliFlag: "--new-series", label: "New Series UID", help: "Mint a new Series Instance UID for the merged object", type: .boolean),
            ParameterDefinition(id: "allow-any-source", cliFlag: "--allow-any-source", label: "Allow Any Source", help: "Skip the source SOP class check for enhanced targets", type: .boolean),
            ParameterDefinition(id: "level", cliFlag: "--level", label: "Merge Level", help: "file, series, or study", type: .enumeration, enumValues: [
                EnumValue(label: "File", value: "file"),
                EnumValue(label: "Series", value: "series"),
                EnumValue(label: "Study", value: "study"),
            ]),
            ParameterDefinition(id: "sort-by", cliFlag: "--sort-by", label: "Sort By", help: "Sort files by field", type: .string),
            ParameterDefinition(id: "validate", cliFlag: "--validate", label: "Validate", help: "Validate output", type: .boolean),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
        ]
    )

    public static let dicomDcmdir = ToolDefinition(
        id: "dicom-dcmdir",
        name: "DICOMDIR",
        icon: "folder",
        category: .fileOrganization,
        description: "Manage DICOMDIR files",
        subcommands: [
            SubcommandDefinition(id: "create", name: "Create", description: "Create a DICOMDIR", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Directory", help: "Directory containing DICOM files", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "DICOMDIR output path", type: .file),
            ]),
            SubcommandDefinition(id: "validate", name: "Validate", description: "Validate a DICOMDIR", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "DICOMDIR File", help: "DICOMDIR to validate", type: .file, isRequired: true),
            ]),
            SubcommandDefinition(id: "dump", name: "Dump", description: "Dump DICOMDIR contents", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "DICOMDIR File", help: "DICOMDIR to dump", type: .file, isRequired: true),
            ]),
        ]
    )

    public static let dicomArchive = ToolDefinition(
        id: "dicom-archive",
        name: "DICOM Archive",
        icon: "archivebox.fill",
        category: .fileOrganization,
        description: "Archive DICOM files",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input", help: "Files or directory to archive", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output", help: "Archive output path", type: .file, isRequired: true),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Archive format", type: .enumeration, enumValues: [
                EnumValue(label: "ZIP", value: "zip"),
                EnumValue(label: "TAR", value: "tar"),
            ]),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
        ]
    )

    // MARK: - Data Export Tools

    public static let dicomJson = ToolDefinition(
        id: "dicom-json",
        name: "DICOM JSON",
        icon: "curlybraces",
        category: .dataExport,
        description: "Convert DICOM to/from JSON",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "Input file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file),
            // (--format removed: the CLI dropped it — it was a declared no-op;
            // output is always the DICOMweb PS3.18 JSON model.)
            ParameterDefinition(id: "reverse", cliFlag: "--reverse", label: "Reverse", help: "Convert JSON to DICOM", type: .boolean),
            ParameterDefinition(id: "pretty", cliFlag: "--pretty", label: "Pretty Print", help: "Pretty-print JSON output", type: .boolean),
            ParameterDefinition(id: "metadata-only", cliFlag: "--metadata-only", label: "Metadata Only", help: "Export metadata only", type: .boolean),
        ]
    )

    public static let dicomXml = ToolDefinition(
        id: "dicom-xml",
        name: "DICOM XML",
        icon: "chevron.left.forwardslash.chevron.right",
        category: .dataExport,
        description: "Convert DICOM to/from XML",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "Input file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file),
            ParameterDefinition(id: "reverse", cliFlag: "--reverse", label: "Reverse", help: "Convert XML to DICOM", type: .boolean),
            ParameterDefinition(id: "pretty", cliFlag: "--pretty", label: "Pretty Print", help: "Pretty-print XML output", type: .boolean),
            ParameterDefinition(id: "no-keywords", cliFlag: "--no-keywords", label: "No Keywords", help: "Omit keyword attributes", type: .boolean),
            ParameterDefinition(id: "metadata-only", cliFlag: "--metadata-only", label: "Metadata Only", help: "Export metadata only", type: .boolean),
        ]
    )

    public static let dicomPdf = ToolDefinition(
        id: "dicom-pdf",
        name: "DICOM PDF",
        icon: "doc.richtext",
        category: .dataExport,
        description: "Encapsulate or extract PDF in DICOM",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "Input file (DICOM or PDF)", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file, isRequired: true),
            ParameterDefinition(id: "patient-name", cliFlag: "--patient-name", label: "Patient Name", help: "Patient name for encapsulation", type: .string),
            ParameterDefinition(id: "patient-id", cliFlag: "--patient-id", label: "Patient ID", help: "Patient ID for encapsulation", type: .string),
            ParameterDefinition(id: "extract", cliFlag: "--extract", label: "Extract", help: "Extract PDF from DICOM", type: .boolean),
            ParameterDefinition(id: "show-metadata", cliFlag: "--show-metadata", label: "Show Metadata", help: "Display metadata", type: .boolean),
        ]
    )

    public static let dicomImage = ToolDefinition(
        id: "dicom-image",
        name: "DICOM Image",
        icon: "photo",
        category: .dataExport,
        description: "Encapsulate images as DICOM",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Image", help: "Input image file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "patient-name", cliFlag: "--patient-name", label: "Patient Name", help: "Patient name", type: .string),
            ParameterDefinition(id: "patient-id", cliFlag: "--patient-id", label: "Patient ID", help: "Patient ID", type: .string),
            ParameterDefinition(id: "modality", cliFlag: "--modality", label: "Modality", help: "Imaging modality", type: .string),
            ParameterDefinition(id: "use-exif", cliFlag: "--use-exif", label: "Use EXIF", help: "Import EXIF data", type: .boolean),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
        ]
    )

    public static let dicomExport = ToolDefinition(
        id: "dicom-export",
        name: "DICOM Export",
        icon: "square.and.arrow.up.on.square",
        category: .dataExport,
        description: "Export DICOM images to standard formats",
        subcommands: [
            SubcommandDefinition(id: "single", name: "Single", description: "Export a single image", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "DICOM file", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output image file", type: .file, isRequired: true),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Image format", type: .enumeration, enumValues: [
                    EnumValue(label: "PNG", value: "png"),
                    EnumValue(label: "JPEG", value: "jpeg"),
                    EnumValue(label: "TIFF", value: "tiff"),
                ]),
            ]),
            SubcommandDefinition(id: "bulk", name: "Bulk", description: "Export multiple images", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Directory", help: "Directory of DICOM files", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file, isRequired: true),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Image format", type: .enumeration, enumValues: [
                    EnumValue(label: "PNG", value: "png"),
                    EnumValue(label: "JPEG", value: "jpeg"),
                ]),
                ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process recursively", type: .boolean),
            ]),
        ]
    )

    public static let dicomPixedit = ToolDefinition(
        id: "dicom-pixedit",
        name: "DICOM Pixel Edit",
        icon: "pencil.and.outline",
        category: .dataExport,
        description: "Edit pixel data in DICOM files",
        parameters: [
            ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "DICOM file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file", type: .file, isRequired: true),
            ParameterDefinition(id: "mask-region", cliFlag: "--mask-region", label: "Mask Region", help: "Region to mask (x,y,w,h)", type: .string),
            ParameterDefinition(id: "fill-value", cliFlag: "--fill-value", label: "Fill Value", help: "Fill value for masked region", type: .integer),
            ParameterDefinition(id: "crop", cliFlag: "--crop", label: "Crop", help: "Crop region (x,y,w,h)", type: .string),
            ParameterDefinition(id: "invert", cliFlag: "--invert", label: "Invert", help: "Invert pixel values", type: .boolean),
        ]
    )

    public static let dicomReport = ToolDefinition(
        id: "dicom-report",
        name: "DICOM Report",
        icon: "doc.richtext",
        category: .dataExport,
        description: "Generate clinical reports from DICOM Structured Report objects",
        discussion: "Parse DICOM SR documents and generate professional clinical reports in various formats. Supports specialty-specific templates (cardiology, radiology, oncology), multi-language output (English, Spanish, French, German), image embedding, and custom branding with institution logos.",
        parameters: [
            ParameterDefinition(id: "filePath", cliFlag: "@argument", label: "DICOM SR File", help: "Path to the DICOM SR file", type: .file, isRequired: true),
            ParameterDefinition(id: "output", cliFlag: "--output", shortFlag: "-o", label: "Output File", help: "Output report file path", type: .file, isRequired: true),
            ParameterDefinition(id: "format", cliFlag: "--format", shortFlag: "-f", label: "Output Format", help: "Report output format", type: .enumeration, defaultValue: "text", enumValues: [
                EnumValue(label: "Text", value: "text", description: "Plain text report"),
                EnumValue(label: "HTML", value: "html", description: "Styled HTML report with CSS"),
                EnumValue(label: "JSON", value: "json", description: "Structured JSON data"),
                EnumValue(label: "Markdown", value: "markdown", description: "Markdown format"),
                EnumValue(label: "PDF", value: "pdf", description: "PDF format (requires additional library)"),
            ]),
            ParameterDefinition(id: "template", cliFlag: "--template", label: "Report Template", help: "Specialty-specific report template", type: .enumeration, defaultValue: "default", enumValues: [
                EnumValue(label: "Default", value: "default", description: "Standard clinical report"),
                EnumValue(label: "Cardiology", value: "cardiology", description: "Cardiac findings, hemodynamics, recommendations"),
                EnumValue(label: "Radiology", value: "radiology", description: "Indication, technique, findings, impressions"),
                EnumValue(label: "Oncology", value: "oncology", description: "Tumor assessment, staging, recommendations"),
            ]),
            ParameterDefinition(id: "language", cliFlag: "--language", label: "Language", help: "Report language for section headers and labels", type: .enumeration, defaultValue: "en", enumValues: [
                EnumValue(label: "English", value: "en", description: "English"),
                EnumValue(label: "Spanish", value: "es", description: "Español"),
                EnumValue(label: "French", value: "fr", description: "Français"),
                EnumValue(label: "German", value: "de", description: "Deutsch"),
            ]),
            ParameterDefinition(id: "title", cliFlag: "--title", label: "Custom Title", help: "Custom report title (overrides SR title)", type: .string),
            ParameterDefinition(id: "logo", cliFlag: "--logo", label: "Logo Image", help: "Path to hospital logo image for branding", type: .file),
            ParameterDefinition(id: "footer", cliFlag: "--footer", label: "Footer Text", help: "Custom footer text for report", type: .string),
            ParameterDefinition(id: "embed-images", cliFlag: "--embed-images", label: "Embed Images", help: "Embed referenced images in HTML/PDF output", type: .boolean),
            ParameterDefinition(id: "image-dir", cliFlag: "--image-dir", label: "Image Directory", help: "Directory containing referenced image files", type: .file),
            ParameterDefinition(id: "include-measurements", cliFlag: "--include-measurements", label: "Include Measurements", help: "Include measurement tables", type: .boolean, defaultValue: "true"),
            ParameterDefinition(id: "include-summary", cliFlag: "--include-summary", label: "Include Summary", help: "Include finding summaries", type: .boolean, defaultValue: "true"),
            ParameterDefinition(id: "force", cliFlag: "--force", label: "Force Parse", help: "Parse files without DICM prefix", type: .boolean),
            ParameterDefinition(id: "verbose", cliFlag: "--verbose", label: "Verbose", help: "Verbose output for debugging", type: .boolean),
        ],
        requiresOutput: true
    )

    // MARK: - Network Operations Tools

    public static let dicomEcho = ToolDefinition(
        id: "dicom-echo",
        name: "DICOM Echo",
        icon: "wave.3.right",
        category: .networkOperations,
        description: "Test PACS connectivity with C-ECHO",
        parameters: [
            ParameterDefinition(id: "count", cliFlag: "--count", shortFlag: "-c", label: "Count", help: "Number of echo requests", type: .integer, defaultValue: "1", validation: ValidationRule(minValue: 1, maxValue: 100)),
            ParameterDefinition(id: "stats", cliFlag: "--stats", label: "Show Statistics", help: "Show timing statistics", type: .boolean),
            ParameterDefinition(id: "diagnose", cliFlag: "--diagnose", label: "Run Diagnostics", help: "Run comprehensive diagnostics", type: .boolean),
            ParameterDefinition(id: "verbose", cliFlag: "--verbose", shortFlag: "-v", label: "Verbose", help: "Detailed output", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomQuery = ToolDefinition(
        id: "dicom-query",
        name: "DICOM Query",
        icon: "magnifyingglass",
        category: .networkOperations,
        description: "Query PACS with C-FIND",
        parameters: [
            ParameterDefinition(id: "level", cliFlag: "--level", label: "Query Level", help: "Query level", type: .enumeration, defaultValue: "study", enumValues: [
                EnumValue(label: "Patient", value: "patient"),
                EnumValue(label: "Study", value: "study"),
                EnumValue(label: "Series", value: "series"),
                EnumValue(label: "Instance", value: "instance"),
            ]),
            ParameterDefinition(id: "patient-name", cliFlag: "--patient-name", label: "Patient Name", help: "Patient name (wildcards supported)", type: .string),
            ParameterDefinition(id: "patient-id", cliFlag: "--patient-id", label: "Patient ID", help: "Patient ID", type: .string),
            ParameterDefinition(id: "study-date", cliFlag: "--study-date", label: "Study Date", help: "Study date (YYYYMMDD)", type: .string),
            ParameterDefinition(id: "modality", cliFlag: "--modality", label: "Modality", help: "Imaging modality", type: .enumeration, enumValues: [
                EnumValue(label: "CT", value: "CT"),
                EnumValue(label: "MR", value: "MR"),
                EnumValue(label: "US", value: "US"),
                EnumValue(label: "CR", value: "CR"),
                EnumValue(label: "DX", value: "DX"),
            ]),
            ParameterDefinition(id: "format", cliFlag: "--format", label: "Output Format", help: "Output format", type: .enumeration, defaultValue: "table", enumValues: [
                EnumValue(label: "Table", value: "table"),
                EnumValue(label: "JSON", value: "json"),
                EnumValue(label: "CSV", value: "csv"),
                EnumValue(label: "Compact", value: "compact"),
            ]),
            ParameterDefinition(id: "verbose", cliFlag: "--verbose", shortFlag: "-v", label: "Verbose", help: "Detailed output", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomSend = ToolDefinition(
        id: "dicom-send",
        name: "DICOM Send",
        icon: "arrow.up.doc",
        category: .networkOperations,
        description: "Send DICOM files with C-STORE",
        parameters: [
            ParameterDefinition(id: "paths", cliFlag: "@argument", label: "Files", help: "Files to send", type: .file, isRequired: true),
            ParameterDefinition(id: "recursive", cliFlag: "--recursive", label: "Recursive", help: "Process directories recursively", type: .boolean),
            ParameterDefinition(id: "verify", cliFlag: "--verify", label: "Verify First", help: "Run C-ECHO before sending", type: .boolean),
            ParameterDefinition(id: "retry", cliFlag: "--retry", label: "Retry Count", help: "Number of retries", type: .integer, defaultValue: "0", validation: ValidationRule(minValue: 0, maxValue: 10)),
            ParameterDefinition(id: "priority", cliFlag: "--priority", label: "Priority", help: "Send priority", type: .enumeration, defaultValue: "medium", enumValues: [
                EnumValue(label: "Low", value: "low"),
                EnumValue(label: "Medium", value: "medium"),
                EnumValue(label: "High", value: "high"),
            ]),
            ParameterDefinition(id: "dry-run", cliFlag: "--dry-run", label: "Dry Run", help: "Preview without sending", type: .boolean),
            ParameterDefinition(id: "transfer-syntax", cliFlag: "--transfer-syntax", label: "Transfer Syntax", help: "Preferred transfer syntax for C-STORE negotiation", type: .enumeration, enumValues: [
                EnumValue(label: "Explicit VR LE", value: "explicit-vr-le"),
                EnumValue(label: "Implicit VR LE", value: "implicit-vr-le"),
                EnumValue(label: "JPEG Baseline", value: "jpeg-baseline"),
                EnumValue(label: "JPEG 2000", value: "jpeg2000"),
                EnumValue(label: "HTJ2K Lossless", value: "htj2k-lossless"),
                EnumValue(label: "HTJ2K RPCL", value: "htj2k-rpcl"),
                EnumValue(label: "HTJ2K", value: "htj2k"),
                EnumValue(label: "RLE Lossless", value: "rle-lossless"),
            ]),
            ParameterDefinition(id: "verbose", cliFlag: "--verbose", shortFlag: "-v", label: "Verbose", help: "Detailed output", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomRetrieve = ToolDefinition(
        id: "dicom-retrieve",
        name: "DICOM Retrieve",
        icon: "arrow.down.doc",
        category: .networkOperations,
        description: "Retrieve DICOM files with C-MOVE/C-GET",
        parameters: [
            ParameterDefinition(id: "study-uid", cliFlag: "--study-uid", label: "Study UID", help: "Study Instance UID", type: .string),
            ParameterDefinition(id: "series-uid", cliFlag: "--series-uid", label: "Series UID", help: "Series Instance UID", type: .string),
            ParameterDefinition(id: "instance-uid", cliFlag: "--instance-uid", label: "Instance UID", help: "SOP Instance UID", type: .string),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file, isRequired: true),
            ParameterDefinition(id: "method", cliFlag: "--method", label: "Method", help: "Retrieval method", type: .enumeration, defaultValue: "c-move", enumValues: [
                EnumValue(label: "C-MOVE", value: "c-move"),
                EnumValue(label: "C-GET", value: "c-get"),
            ]),
            ParameterDefinition(id: "move-dest", cliFlag: "--move-dest", label: "Move Destination", help: "Move destination AET", type: .string),
            ParameterDefinition(id: "parallel", cliFlag: "--parallel", label: "Parallel", help: "Number of parallel operations", type: .integer, defaultValue: "1", validation: ValidationRule(minValue: 1, maxValue: 8)),
            ParameterDefinition(id: "transfer-syntax", cliFlag: "--transfer-syntax", label: "Transfer Syntax", help: "Requested transfer syntax for C-GET and advisory syntax for C-MOVE", type: .enumeration, enumValues: [
                EnumValue(label: "Explicit VR LE", value: "explicit-vr-le"),
                EnumValue(label: "Implicit VR LE", value: "implicit-vr-le"),
                EnumValue(label: "JPEG Baseline", value: "jpeg-baseline"),
                EnumValue(label: "JPEG 2000", value: "jpeg2000"),
                EnumValue(label: "HTJ2K Lossless", value: "htj2k-lossless"),
                EnumValue(label: "HTJ2K RPCL", value: "htj2k-rpcl"),
                EnumValue(label: "HTJ2K", value: "htj2k"),
                EnumValue(label: "RLE Lossless", value: "rle-lossless"),
            ]),
            ParameterDefinition(id: "verbose", cliFlag: "--verbose", shortFlag: "-v", label: "Verbose", help: "Detailed output", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomQR = ToolDefinition(
        id: "dicom-qr",
        name: "DICOM Q/R",
        icon: "arrow.triangle.2.circlepath.doc.on.clipboard",
        category: .networkOperations,
        description: "Combined query-retrieve operations",
        parameters: [
            ParameterDefinition(id: "method", cliFlag: "--method", label: "Method", help: "Retrieval method", type: .enumeration, defaultValue: "c-move", enumValues: [
                EnumValue(label: "C-MOVE", value: "c-move"),
                EnumValue(label: "C-GET", value: "c-get"),
            ]),
            ParameterDefinition(id: "move-dest", cliFlag: "--move-dest", label: "Move Destination", help: "Move destination AET", type: .string),
            ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file),
            ParameterDefinition(id: "interactive", cliFlag: "--interactive", label: "Interactive", help: "Interactive mode", type: .boolean),
            ParameterDefinition(id: "auto", cliFlag: "--auto", label: "Auto Retrieve", help: "Automatic retrieve mode", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomWado = ToolDefinition(
        id: "dicom-wado",
        name: "DICOM WADO",
        icon: "globe",
        category: .networkOperations,
        description: "DICOMweb access (WADO-RS, STOW-RS, QIDO-RS)",
        subcommands: [
            SubcommandDefinition(id: "retrieve", name: "Retrieve", description: "Retrieve via WADO-RS", parameters: [
                ParameterDefinition(id: "study", cliFlag: "--study", label: "Study UID", help: "Study Instance UID", type: .string, isRequired: true),
                ParameterDefinition(id: "series", cliFlag: "--series", label: "Series UID", help: "Series Instance UID", type: .string),
                ParameterDefinition(id: "instance", cliFlag: "--instance", label: "Instance UID", help: "SOP Instance UID", type: .string),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file),
                ParameterDefinition(id: "metadata", cliFlag: "--metadata", label: "Metadata Only", help: "Retrieve metadata only", type: .boolean),
            ]),
            SubcommandDefinition(id: "store", name: "Store", description: "Store via STOW-RS", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Files", help: "Files to store", type: .file, isRequired: true),
            ]),
            SubcommandDefinition(id: "query", name: "Query", description: "Query via QIDO-RS", parameters: [
                ParameterDefinition(id: "level", cliFlag: "--level", label: "Query Level", help: "Query level", type: .enumeration, enumValues: [
                    EnumValue(label: "Study", value: "study"),
                    EnumValue(label: "Series", value: "series"),
                    EnumValue(label: "Instance", value: "instance"),
                ]),
            ]),
        ],
        requiresNetwork: true
    )

    public static let dicomMWL = ToolDefinition(
        id: "dicom-mwl",
        name: "DICOM MWL",
        icon: "list.clipboard",
        category: .networkOperations,
        description: "Modality Worklist query",
        parameters: [
            ParameterDefinition(id: "date", cliFlag: "--date", label: "Date", help: "Scheduled date", type: .string),
            ParameterDefinition(id: "station", cliFlag: "--station", label: "Station", help: "Scheduled station", type: .string),
            ParameterDefinition(id: "patient", cliFlag: "--patient", label: "Patient", help: "Patient name", type: .string),
            ParameterDefinition(id: "modality", cliFlag: "--modality", label: "Modality", help: "Modality type", type: .string),
            ParameterDefinition(id: "json", cliFlag: "--json", label: "JSON Output", help: "Output as JSON", type: .boolean),
        ],
        requiresNetwork: true
    )

    public static let dicomMPPS = ToolDefinition(
        id: "dicom-mpps",
        name: "DICOM MPPS",
        icon: "checkmark.rectangle",
        category: .networkOperations,
        description: "Modality Performed Procedure Step",
        subcommands: [
            SubcommandDefinition(id: "create", name: "Create", description: "Create MPPS", parameters: [
                ParameterDefinition(id: "study-uid", cliFlag: "--study-uid", label: "Study UID", help: "Study Instance UID", type: .string, isRequired: true),
                ParameterDefinition(id: "status", cliFlag: "--status", label: "Status", help: "Procedure status", type: .enumeration, defaultValue: "IN PROGRESS", enumValues: [
                    EnumValue(label: "In Progress", value: "IN PROGRESS"),
                    EnumValue(label: "Completed", value: "COMPLETED"),
                    EnumValue(label: "Discontinued", value: "DISCONTINUED"),
                ]),
            ]),
            SubcommandDefinition(id: "update", name: "Update", description: "Update MPPS", parameters: [
                ParameterDefinition(id: "study-uid", cliFlag: "--study-uid", label: "Study UID", help: "Study Instance UID", type: .string, isRequired: true),
                ParameterDefinition(id: "status", cliFlag: "--status", label: "Status", help: "Updated status", type: .enumeration, enumValues: [
                    EnumValue(label: "Completed", value: "COMPLETED"),
                    EnumValue(label: "Discontinued", value: "DISCONTINUED"),
                ]),
            ]),
        ],
        requiresNetwork: true
    )

    // MARK: - Automation Tools

    public static let dicomStudy = ToolDefinition(
        id: "dicom-study",
        name: "DICOM Study",
        icon: "rectangle.stack",
        category: .automation,
        description: "Study management operations",
        subcommands: [
            SubcommandDefinition(id: "organize", name: "Organize", description: "Organize study files into a structured directory layout", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input Directory", help: "Directory to organize", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output Directory", help: "Output directory", type: .file),
                ParameterDefinition(id: "pattern", cliFlag: "--pattern", label: "Pattern", help: "Organization pattern (e.g., {PatientName}/{StudyDate}/{Modality})", type: .string),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Output format", type: .enumeration, enumValues: [
                    EnumValue(label: "Text", value: "text"),
                    EnumValue(label: "JSON", value: "json"),
                ]),
            ]),
            SubcommandDefinition(id: "summary", name: "Summary", description: "Show study summary with series and instance counts", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input", help: "Study directory", type: .file, isRequired: true),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Output format", type: .enumeration, enumValues: [
                    EnumValue(label: "Text", value: "text"),
                    EnumValue(label: "JSON", value: "json"),
                ]),
            ]),
            SubcommandDefinition(id: "check", name: "Check", description: "Check study completeness and integrity", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input", help: "Study directory to check", type: .file, isRequired: true),
                ParameterDefinition(id: "expected-series", cliFlag: "--expected-series", label: "Expected Series", help: "Expected number of series", type: .integer),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Output format", type: .enumeration, enumValues: [
                    EnumValue(label: "Text", value: "text"),
                    EnumValue(label: "JSON", value: "json"),
                ]),
            ]),
            SubcommandDefinition(id: "stats", name: "Stats", description: "Display detailed study statistics", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input", help: "Study directory", type: .file, isRequired: true),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Output format", type: .enumeration, enumValues: [
                    EnumValue(label: "Text", value: "text"),
                    EnumValue(label: "JSON", value: "json"),
                ]),
            ]),
            SubcommandDefinition(id: "compare", name: "Compare", description: "Compare two studies for differences", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "First Study", help: "First study directory", type: .file, isRequired: true),
                ParameterDefinition(id: "input2", cliFlag: "@argument", label: "Second Study", help: "Second study directory", type: .file, isRequired: true),
                ParameterDefinition(id: "format", cliFlag: "--format", label: "Format", help: "Output format", type: .enumeration, enumValues: [
                    EnumValue(label: "Text", value: "text"),
                    EnumValue(label: "JSON", value: "json"),
                ]),
            ]),
        ]
    )

    public static let dicomUID = ToolDefinition(
        id: "dicom-uid",
        name: "DICOM UID",
        icon: "number",
        category: .automation,
        description: "UID generation and management",
        subcommands: [
            SubcommandDefinition(id: "generate", name: "Generate", description: "Generate new DICOM UIDs", parameters: [
                ParameterDefinition(id: "count", cliFlag: "--count", label: "Count", help: "Number of UIDs to generate", type: .integer, defaultValue: "1"),
                ParameterDefinition(id: "type", cliFlag: "--type", label: "Type", help: "UID type", type: .string),
                ParameterDefinition(id: "root", cliFlag: "--root", label: "Root OID", help: "Root OID for UIDs", type: .string),
                ParameterDefinition(id: "json", cliFlag: "--json", label: "JSON Output", help: "Output as JSON", type: .boolean),
            ]),
            SubcommandDefinition(id: "validate", name: "Validate", description: "Validate UID format and structure", parameters: [
                ParameterDefinition(id: "uid", cliFlag: "@argument", label: "UID", help: "UID to validate", type: .string, isRequired: true),
            ]),
            SubcommandDefinition(id: "lookup", name: "Lookup", description: "Look up well-known UIDs in the DICOM registry", parameters: [
                ParameterDefinition(id: "uid", cliFlag: "@argument", label: "UID", help: "UID to look up", type: .string, isRequired: true),
            ]),
            SubcommandDefinition(id: "regenerate", name: "Regenerate", description: "Regenerate UIDs in DICOM files", parameters: [
                ParameterDefinition(id: "input", cliFlag: "@argument", label: "Input File", help: "DICOM file to regenerate UIDs in", type: .file, isRequired: true),
                ParameterDefinition(id: "output", cliFlag: "--output", label: "Output File", help: "Output file path", type: .file),
                ParameterDefinition(id: "root", cliFlag: "--root", label: "Root OID", help: "Root OID for new UIDs", type: .string),
                ParameterDefinition(id: "json", cliFlag: "--json", label: "JSON Output", help: "Output mapping as JSON", type: .boolean),
            ]),
        ]
    )

    public static let dicomScript = ToolDefinition(
        id: "dicom-script",
        name: "DICOM Script",
        icon: "terminal",
        category: .automation,
        description: "Execute DICOM automation scripts",
        subcommands: [
            SubcommandDefinition(id: "run", name: "Run", description: "Run a script", parameters: [
                ParameterDefinition(id: "script", cliFlag: "@argument", label: "Script File", help: "Script file to run", type: .file, isRequired: true),
                ParameterDefinition(id: "variables", cliFlag: "--variables", label: "Variables", help: "Script variables (KEY=VALUE)", type: .repeatable),
                ParameterDefinition(id: "parallel", cliFlag: "--parallel", label: "Parallel", help: "Run tasks in parallel", type: .boolean),
                ParameterDefinition(id: "dry-run", cliFlag: "--dry-run", label: "Dry Run", help: "Preview without executing", type: .boolean),
                ParameterDefinition(id: "log", cliFlag: "--log", label: "Log File", help: "Log file path", type: .file),
            ]),
            SubcommandDefinition(id: "validate", name: "Validate", description: "Validate a script", parameters: [
                ParameterDefinition(id: "script", cliFlag: "@argument", label: "Script File", help: "Script file to validate", type: .file, isRequired: true),
            ]),
            SubcommandDefinition(id: "template", name: "Template", description: "Print a named script template to the console", parameters: [
                ParameterDefinition(id: "template-name", cliFlag: "@argument", label: "Template Name", help: "Required template name; generated script is printed to the console", type: .enumeration, isRequired: true, enumValues: ToolboxCommandContract.scriptTemplates.map { EnumValue(label: $0.capitalized, value: $0) }),
            ]),
        ]
    )
}
