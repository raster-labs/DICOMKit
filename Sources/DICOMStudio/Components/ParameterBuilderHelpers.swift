// ParameterBuilderHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helper enums for Dynamic GUI Controls & Parameter Builder (Milestone 21)
// NEMA-verified: 2026a, checked 2026-10-05 — the 12 tool configurations diffed by Scripts/diff_studio_g1_shell.py against each tool's ArgumentParser surface (diff_cli.extract_options): of the 59 previous option rows 29 were not options of the named tool (positional arguments spelled as --input/--host/--file-a, --calling-aet for --aet, --output-format for --format, --pretty-print for --pretty, dicom-image given dicom-convert's --format/--frame-*, --tls, --verbose on dicom-info) and 3 pickers offered values the tools refuse (dicom-anon --profile standard/full vs ps315 + legacy-*, dicom-compress --codec jpeg-baseline/rle-lossless vs the CompressionManager.codecMap names and --quality 0-100 vs presets/0.0-1.0; dicom-query --level instance is an alias of image); --retain-dates was the deprecated spelling; now 113 rows (93 per-tool plus the 5 shared network rows of 4 DIMSE tools), all real, picker values are the accepted enum/alias values, defaults are the tools' (port 11112 = PS3.8 2026a 9.1.1 registered port, called AE ANY-SCP, timeouts 30/60); validateAETitle 16 = PS3.5 2026a Table 6.2-1 AE; validatePort 1-65535

import Foundation
import DICOMKit

// MARK: - ParameterValidationHelpers

/// Helpers for validating parameter values against rules and DICOM-specific constraints.
public enum ParameterValidationHelpers {

    /// Validates a value against a list of rules and returns the first error message, or `nil` if valid.
    public static func validate(value: ParameterValue, against validations: [ParameterValidation]) -> String? {
        for validation in validations {
            switch validation {
            case .required:
                let str = value.stringRepresentation
                if str.trimmingCharacters(in: .whitespaces).isEmpty {
                    return "This field is required."
                }
            case .maxLength(let max):
                let str = value.stringRepresentation
                if str.count > max {
                    return "Must be \(max) characters or fewer (currently \(str.count))."
                }
            case .range(let min, let max):
                switch value {
                case .int(let v):
                    if Double(v) < min || Double(v) > max {
                        return "Must be between \(Int(min)) and \(Int(max))."
                    }
                case .double(let v):
                    if v < min || v > max {
                        return "Must be between \(min) and \(max)."
                    }
                default:
                    break
                }
            case .regex(let pattern):
                let str = value.stringRepresentation
                if str.range(of: pattern, options: .regularExpression) == nil {
                    return "Value does not match required pattern."
                }
            case .custom(let description):
                return description
            }
        }
        return nil
    }

    /// Validates a DICOM AE Title: must be non-empty and at most 16 characters (PS3.5 2026a Table 6.2-1,
    /// VR AE: 16 bytes maximum; a value solely of spaces shall not be used).
    public static func validateAETitle(_ title: String) -> String? {
        if title.isEmpty { return "AE Title must not be empty." }
        if title.count > 16 { return "AE Title must be 16 characters or fewer (currently \(title.count))." }
        return nil
    }

    /// Validates a TCP port number: must be in the range 1–65535 (PS3.8 2026a 9.1.1 recommends 104 or the
    /// registered 11112).
    public static func validatePort(_ port: Int) -> String? {
        if port < 1 || port > 65535 {
            return "Port must be between 1 and 65535."
        }
        return nil
    }

    /// Validates a hostname: must be non-empty.
    public static func validateHost(_ host: String) -> String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Host must not be empty."
        }
        return nil
    }
}

// MARK: - ParameterCatalogHelpers

/// Helpers for building and looking up per-tool parameter configurations.
///
/// Every parameter name below is an option or argument of the named `dicom-*` tool's
/// ArgumentParser surface (`python3 Scripts/diff_cli.py --list-surface --tool <tool>`), diffed by
/// `Scripts/diff_studio_g1_shell.py`. Positional arguments carry the ArgumentParser spelling
/// `<kebab-name>`; `FormRenderingHelpers.generateCommand` emits them as bare values.
public enum ParameterCatalogHelpers {

    /// All tool names covered by this catalog.
    public static let allToolNames: [String] = [
        "dicom-info", "dicom-diff", "dicom-convert", "dicom-anon",
        "dicom-compress", "dicom-echo", "dicom-query", "dicom-send",
        "dicom-retrieve", "dicom-uid", "dicom-image", "dicom-json"
    ]

    /// Returns the `ToolParameterConfig` for `toolName`, or `nil` when not found.
    public static func config(for toolName: String) -> ToolParameterConfig? {
        allToolConfigs().first { $0.toolName == toolName }
    }

    /// Returns all 12 representative tool parameter configurations.
    public static func allToolConfigs() -> [ToolParameterConfig] {
        [
            dicomInfo(),
            dicomDiff(),
            dicomConvert(),
            dicomAnon(),
            dicomCompress(),
            dicomEcho(),
            dicomQuery(),
            dicomSend(),
            dicomRetrieve(),
            dicomUID(),
            dicomImage(),
            dicomJSON()
        ]
    }

    // MARK: Shared network parameters (dicom-echo, dicom-query, dicom-send, dicom-retrieve)

    /// The registered DICOM port of PS3.8 2026a 9.1.1 (104 is the well-known privileged port).
    static let defaultDICOMPort = 11112

    /// The default Called AE Title of the DIMSE tools (`--called-aet`, default: ANY-SCP).
    static let defaultCalledAETitle = "ANY-SCP"

    private static func networkParameters(hostDescription: String, timeoutDefault: Int) -> [ToolParameterDefinition] {
        [
            param("<host>", "Host", hostDescription, type: .host, required: true),
            param("--port", "Port", "PACS server port (default: 11112, overrides a port in the host argument).",
                  type: .port, defaultValue: .int(defaultDICOMPort)),
            param("--aet", "Calling AE Title", "Local Application Entity Title (calling AE).", type: .aeTitle),
            param("--called-aet", "Called AE Title", "Remote Application Entity Title (default: ANY-SCP).",
                  type: .aeTitle, defaultValue: .string(defaultCalledAETitle)),
            param("--timeout", "Timeout (s)", "Connection timeout in seconds.",
                  type: .number(min: 1, max: 3600, step: 1), defaultValue: .int(timeoutDefault))
        ]
    }

    // MARK: Private builders

    private static func dicomInfo() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-info",
            parameters: [
                param("<file-path>", "Input File", "Path to the DICOM file.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("--format", "Output Format", "Output format: text, json, csv.",
                      type: .picker(options: options(["text", "json", "csv"])), defaultValue: .string("text")),
                param("--tag", "Tag Filter", "Filter by keyword, tag (GGGG,EEEE) or part of the Attribute name.",
                      type: .text(placeholder: "e.g. PatientName or 0010,0010")),
                param("--show-private", "Show Private Tags", "Include private tags in output.", type: .toggle),
                param("--statistics", "Statistics", "Show file statistics.", type: .toggle),
                param("--force", "Force", "Force parsing of files without DICM prefix.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomDiff() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-diff",
            parameters: [
                param("<file1>", "File A", "First DICOM file to compare.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("<file2>", "File B", "Second DICOM file to compare.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("--format", "Output Format", "Output format: text, json, summary.",
                      type: .picker(options: options(["text", "json", "summary"])), defaultValue: .string("text")),
                param("--ignore-private", "Ignore Private Tags", "Ignore private data elements (odd group number, PS3.5 7.1).", type: .toggle),
                param("--compare-pixels", "Compare Pixel Data", "Compare Pixel Data (7FE0,0010) sample by sample.", type: .toggle),
                param("--quick", "Quick", "Quick mode: metadata only, overrides --compare-pixels.", type: .toggle),
                param("--show-identical", "Show Identical", "Show identical tags in detailed mode.", type: .toggle),
                param("--verbose", "Verbose", "Verbose output with detailed information.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomConvert() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-convert",
            parameters: [
                param("<input-path>", "Input Path", "Path to DICOM file or directory.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("--output", "Output", "Output file or directory path.", type: .outputPath(defaultExtension: "dcm")),
                // Single source of truth: the shared DICOMConverter target catalog (DICOMKit).
                param("--transfer-syntax", "Transfer Syntax", "Target transfer syntax.",
                      type: .picker(options: options(DICOMConverter.aliasTokens))),
                param("--format", "Output Format", "Output format for image export: png, jpeg, tiff, dicom.",
                      type: .picker(options: options(["dicom", "png", "jpeg", "tiff"])), defaultValue: .string("dicom")),
                param("--quality", "JPEG Quality", "JPEG quality (1-100).",
                      type: .number(min: 1, max: 100, step: 1), defaultValue: .int(90)),
                param("--recursive", "Recursive", "Process directories recursively.", type: .toggle),
                param("--strip-private", "Strip Private Tags", "Strip private tags during conversion.", type: .toggle),
                param("--force", "Force", "Force parsing of files without DICM prefix.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomAnon() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-anon",
            parameters: [
                param("<input-path>", "Input Path", "Path to DICOM file or directory.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("--output", "Output", "Output file or directory path.", type: .outputPath(defaultExtension: "dcm")),
                // ps315 is the PS3.15 2026a E.1 Basic Application Level Confidentiality Profile and the tool's
                // default; the legacy-* lists are not PS3.15 profiles and are deprecated by dicom-anon.
                param("--profile", "Anonymisation Profile", "Anonymization profile: ps315 (PS3.15 Basic Profile, default) or a deprecated legacy list.",
                      type: .radio(options: options(["ps315", "legacy-basic", "legacy-clinical-trial", "legacy-research"])),
                      defaultValue: .string("ps315")),
                param("--retain-full-dates", "Retain Full Dates", "PS3.15 Retain Longitudinal Temporal Information With Full Dates Option.", type: .toggle),
                param("--retain-modified-dates", "Retain Modified Dates", "PS3.15 Retain Longitudinal Temporal Information With Modified Dates Option.", type: .toggle),
                param("--retain-uids", "Retain UIDs", "PS3.15 Retain UIDs Option: UIDs kept instead of replaced.", type: .toggle),
                param("--clean-descriptors", "Clean Descriptors", "PS3.15 Clean Descriptors Option.", type: .toggle),
                param("--shift-dates", "Shift Dates (days)", "Number of days to shift dates (preserves intervals).",
                      type: .number(min: -36500, max: 36500, step: 1)),
                param("--dry-run", "Dry Run", "Preview changes without modifying files.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomCompress() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-compress",
            parameters: [],
            subcommands: [
                ToolSubcommand(
                    name: "compress",
                    displayName: "Compress",
                    description: "Compress a DICOM file using the specified codec.",
                    parameters: [
                        param("<input>", "Input File", "Input DICOM file path.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                        param("--output", "Output File", "Output DICOM file path.", type: .outputPath(defaultExtension: "dcm")),
                        // The first spelling of each compressed-codec row of DICOMKit CompressionManager.codecMap.
                        param("--codec", "Codec", "Target codec.",
                              type: .picker(options: options([
                                "jpeg-baseline", "jpeg-extended", "jpeg-lossless", "jpeg-lossless-sv1",
                                "jpeg2000", "jpeg2000-lossless", "jpeg2000-lossless-only",
                                "htj2k", "htj2k-lossless", "htj2k-lossless-only",
                                "jpeg-ls", "jpeg-ls-lossless", "jpeg-xl", "jpeg-xl-lossless", "rle"
                              ]))),
                        param("--quality", "Quality", "Quality preset: maximum, high, medium, low (the CLI also accepts 0.0-1.0).",
                              type: .picker(options: options(["maximum", "high", "medium", "low"]))),
                        param("--backend", "Backend", "Hardware backend: auto, metal, accelerate, scalar.",
                              type: .picker(options: options(["auto", "metal", "accelerate", "scalar"])), defaultValue: .string("auto")),
                        param("--verbose", "Verbose", "Show verbose output.", type: .toggle)
                    ]
                ),
                ToolSubcommand(
                    name: "decompress",
                    displayName: "Decompress",
                    description: "Decompress a DICOM file to a native transfer syntax.",
                    parameters: [
                        param("<input>", "Input File", "Input DICOM file path.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                        param("--output", "Output File", "Output DICOM file path.", type: .outputPath(defaultExtension: "dcm")),
                        param("--syntax", "Target Syntax", "Native target syntax: explicit-le, implicit-le, deflate.",
                              type: .picker(options: options(["explicit-le", "implicit-le", "deflate"])), defaultValue: .string("explicit-le")),
                        param("--verbose", "Verbose", "Show verbose output.", type: .toggle)
                    ]
                ),
                ToolSubcommand(
                    name: "info",
                    displayName: "Info",
                    description: "Display compression information for a DICOM file.",
                    parameters: [
                        param("<input>", "Input File", "DICOM file path.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                        param("--json", "JSON", "Output as JSON.", type: .toggle)
                    ]
                )
            ]
        )
    }

    private static func dicomEcho() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-echo",
            parameters: networkParameters(hostDescription: "PACS server hostname or IP address, optionally with port (host:port).", timeoutDefault: 30) + [
                param("--count", "Count", "Number of echo requests to send.",
                      type: .number(min: 1, max: 1000, step: 1), defaultValue: .int(1)),
                param("--stats", "Statistics", "Show statistics (min/avg/max round-trip time).", type: .toggle),
                param("--verbose", "Verbose", "Show verbose output including connection details.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomQuery() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-query",
            parameters: networkParameters(hostDescription: "PACS server hostname or IP address, optionally with port (host:port).", timeoutDefault: 60) + [
                // Query/Retrieve Level (0008,0052) values of PS3.4 Tables C.6.1-1 / C.6.2-1 in lower case.
                param("--level", "Query Level", "Query/Retrieve Level (0008,0052): patient, study, series, image.",
                      type: .picker(options: options(["patient", "study", "series", "image"])), defaultValue: .string("study")),
                param("--patient-name", "Patient Name", "Patient's Name (0010,0010); * and ? wild cards.", type: .text(placeholder: "e.g. DOE^J*")),
                param("--patient-id", "Patient ID", "Patient ID (0010,0020).", type: .text(placeholder: "e.g. PAT001")),
                param("--accession-number", "Accession Number", "Accession Number (0008,0050).", type: .text(placeholder: "e.g. ACC123")),
                param("--modality", "Modality", "Modality (0008,0060) filter (e.g. CT).", type: .text(placeholder: "e.g. CT")),
                param("--study-date", "Study Date", "Study Date (0008,0020): YYYYMMDD or a range YYYYMMDD-YYYYMMDD.", type: .text(placeholder: "e.g. 20240101")),
                param("--format", "Output Format", "Output format: table, json, csv, compact, dicom-json.",
                      type: .picker(options: options(["table", "json", "csv", "compact", "dicom-json"])), defaultValue: .string("table")),
                param("--verbose", "Verbose", "Show verbose output including query details.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomSend() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-send",
            parameters: networkParameters(hostDescription: "Destination PACS server hostname or IP address, optionally with port (host:port).", timeoutDefault: 60) + [
                param("<paths>", "Files", "DICOM files or directories to send.", type: .filePath(allowedExtensions: ["dcm", "dicom"]), required: true),
                param("--recursive", "Recursive", "Recursively scan directories for DICOM files.", type: .toggle),
                param("--verify", "Verify First", "Verify connection with C-ECHO before sending.", type: .toggle),
                // Priority (0000,0700), PS3.7 Table 9.3-1: LOW 0002H, MEDIUM 0000H, HIGH 0001H.
                param("--priority", "Priority", "C-STORE Priority (0000,0700): low, medium, high.",
                      type: .picker(options: options(["low", "medium", "high"])), defaultValue: .string("medium")),
                param("--dry-run", "Dry Run", "Show what would be sent without actually sending.", type: .toggle),
                param("--verbose", "Verbose", "Show verbose output including progress.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomRetrieve() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-retrieve",
            parameters: networkParameters(hostDescription: "PACS server hostname or IP address, optionally with port (host:port).", timeoutDefault: 60) + [
                param("--study-uid", "Study Instance UID", "Study Instance UID (0020,000D) to retrieve.", type: .text(placeholder: "1.2.840...")),
                param("--series-uid", "Series Instance UID", "Series Instance UID (0020,000E) to retrieve.", type: .text(placeholder: "1.2.840...")),
                param("--method", "Retrieve Method", "Retrieval method: c-move or c-get.",
                      type: .picker(options: options(["c-move", "c-get"])), defaultValue: .string("c-move")),
                param("--move-dest", "Move Destination", "Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-MOVE.", type: .aeTitle),
                param("--output", "Output Directory", "Output directory for retrieved files.", type: .directoryPath, defaultValue: .directoryPath(".")),
                param("--priority", "Priority", "Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ: low, medium, high.",
                      type: .picker(options: options(["low", "medium", "high"])), defaultValue: .string("medium")),
                param("--verbose", "Verbose", "Show verbose output including progress.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomUID() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-uid",
            parameters: [],
            subcommands: [
                ToolSubcommand(
                    name: "generate",
                    displayName: "Generate",
                    description: "Generate one or more new DICOM UIDs.",
                    parameters: [
                        // The example is the tool's own (a registered organisation root, PS3.5 9.2.2); the
                        // DICOM root 1.2.840.10008 is reserved for the standard's UIDs (PS3.5 B.1).
                        param("--root", "UID Root", "Organisation root for generated UIDs (PS3.5 9.2.2); DICOMKit's root when omitted.",
                              type: .text(placeholder: "e.g. 1.2.826.0.1.3680043.9.1234")),
                        param("--count", "Count", "Number of UIDs to generate, 1 to 1000.",
                              type: .number(min: 1, max: 1000, step: 1), defaultValue: .int(1)),
                        param("--type", "UID Type", "UID type: study, series, instance, or generic.",
                              type: .picker(options: options(["generic", "study", "series", "instance"]))),
                        param("--uuid", "UUID Derived", "Generate UUID derived UIDs, 2.25.<UUID as decimal> (PS3.5 B.2).", type: .toggle),
                        param("--json", "JSON", "Output as JSON array.", type: .toggle)
                    ]
                ),
                ToolSubcommand(
                    name: "validate",
                    displayName: "Validate",
                    description: "Check whether a UID conforms to PS3.5 9.1.",
                    parameters: [
                        param("<uids>", "UID", "UID to validate.", type: .text(placeholder: "1.2.840..."), required: true),
                        param("--check-registry", "Check Registry", "Also print the PS3.6 Table A-1 name of registered UIDs.", type: .toggle),
                        param("--json", "JSON", "Output as JSON.", type: .toggle)
                    ]
                ),
                ToolSubcommand(
                    name: "lookup",
                    displayName: "Lookup",
                    description: "Look up a well-known UID in the PS3.6 Table A-1 registry.",
                    parameters: [
                        param("<uid>", "UID", "UID to look up.", type: .text(placeholder: "1.2.840..."), required: true),
                        param("--search", "Search", "Search UIDs by name keyword.", type: .text(placeholder: "e.g. CT Image")),
                        param("--json", "JSON", "Output as JSON.", type: .toggle)
                    ]
                )
            ]
        )
    }

    private static func dicomImage() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-image",
            parameters: [
                param("<input>", "Input Image", "Input image file or directory to convert to DICOM Secondary Capture.",
                      type: .filePath(allowedExtensions: ["png", "jpg", "jpeg", "tiff", "tif", "bmp"]), required: true),
                param("--output", "Output", "Output file or directory path.", type: .outputPath(defaultExtension: "dcm")),
                param("--patient-name", "Patient Name", "Patient's Name (0010,0010), PN, e.g. DOE^JOHN.", type: .text(placeholder: "e.g. DOE^JOHN")),
                param("--patient-id", "Patient ID", "Patient ID (0010,0020), LO.", type: .text(placeholder: "e.g. PAT001")),
                param("--study-description", "Study Description", "Study Description (0008,1030), LO.", type: .text(placeholder: "")),
                param("--series-description", "Series Description", "Series Description (0008,103E), LO.", type: .text(placeholder: "")),
                param("--modality", "Modality", "Modality (0008,0060), a PS3.3 C.7.3.1.1.1 Defined Term.", type: .text(placeholder: "e.g. OT")),
                param("--recursive", "Recursive", "Process directories recursively.", type: .toggle),
                param("--verbose", "Verbose", "Verbose output.", type: .toggle)
            ],
            subcommands: []
        )
    }

    private static func dicomJSON() -> ToolParameterConfig {
        ToolParameterConfig(
            toolName: "dicom-json",
            parameters: [
                param("<input>", "Input File", "Input file (DICOM or JSON).", type: .filePath(allowedExtensions: ["dcm", "dicom", "json"]), required: true),
                param("--output", "Output File", "Output file path.", type: .outputPath(defaultExtension: "json")),
                param("--reverse", "Reverse", "Convert from JSON to DICOM.", type: .toggle),
                param("--pretty", "Pretty Print", "Pretty-print JSON output.", type: .toggle),
                param("--metadata-only", "Metadata Only", "Metadata only (PS3.18 10.4.1.1.2): leave out bulk data.", type: .toggle),
                param("--verbose", "Verbose", "Verbose output.", type: .toggle)
            ],
            subcommands: []
        )
    }

    // MARK: Private factory helpers

    private static func param(
        _ name: String,
        _ displayName: String,
        _ description: String,
        type paramType: ParameterType,
        required: Bool = false,
        defaultValue: ParameterValue? = nil,
        group: String? = nil
    ) -> ToolParameterDefinition {
        ToolParameterDefinition(
            name: name,
            displayName: displayName,
            description: description,
            type: paramType,
            isRequired: required,
            defaultValue: defaultValue,
            group: group
        )
    }

    private static func options(_ names: [String]) -> [PickerOption] {
        names.map { name in
            PickerOption(
                id: name,
                displayName: name.replacingOccurrences(of: "-", with: " ").capitalized,
                cliValue: name
            )
        }
    }
}

// MARK: - FormRenderingHelpers

/// Helpers for rendering and managing the dynamic parameter form at runtime.
public enum FormRenderingHelpers {

    /// Returns `true` when `entry` should be visible given the currently populated `currentValues`.
    public static func isVisible(entry: ParameterFormEntry, currentValues: [String: ParameterValue]) -> Bool {
        entry.isVisible(currentValues: currentValues)
    }

    /// Builds the CLI command string from `toolName`, an optional `subcommand`, and the current form `entries`.
    public static func generateCommand(
        toolName: String,
        subcommand: String?,
        entries: [ParameterFormEntry]
    ) -> String {
        var parts: [String] = [toolName]
        if let subcommand {
            parts.append(subcommand)
        }

        for entry in entries {
            guard let value = entry.currentValue else { continue }

            switch entry.definition.type {
            case .toggle:
                if case .bool(let flag) = value, flag {
                    parts.append(entry.definition.name)
                }
            default:
                let str = value.stringRepresentation
                if !str.isEmpty {
                    // A `<positional>` argument is emitted as its bare value; an option as `--flag value`.
                    if !isPositional(entry.definition.name) {
                        parts.append(entry.definition.name)
                    }
                    if str.contains(" ") {
                        parts.append("\"\(str)\"")
                    } else {
                        parts.append(str)
                    }
                }
            }
        }

        return parts.joined(separator: " ")
    }

    /// Whether `name` is a positional argument in the ArgumentParser spelling (`<kebab-name>`) rather than
    /// an option flag.
    public static func isPositional(_ name: String) -> Bool {
        name.hasPrefix("<") && name.hasSuffix(">")
    }

    /// Returns a copy of `entries` where every entry's value is reset to its `defaultValue` (or `nil`).
    public static func resetToDefaults(entries: [ParameterFormEntry]) -> [ParameterFormEntry] {
        entries.map { entry in
            ParameterFormEntry(
                definition: entry.definition,
                currentValue: entry.definition.defaultValue,
                source: .defaultValue,
                validationError: nil
            )
        }
    }

    /// Returns a copy of `entries` where network-related fields are overwritten by `injection` values.
    public static func applyNetworkInjection(
        to entries: [ParameterFormEntry],
        injection: NetworkInjectionState
    ) -> [ParameterFormEntry] {
        guard injection.isServerConfigured else { return entries }

        let injectionMap: [String: InjectedNetworkParam] = Dictionary(
            uniqueKeysWithValues: injection.injectedParams.map { ($0.parameterName, $0) }
        )

        return entries.map { entry in
            guard let injected = injectionMap[entry.definition.name] else { return entry }
            return ParameterFormEntry(
                definition: entry.definition,
                currentValue: injected.value,
                source: .serverInjected,
                validationError: nil
            )
        }
    }
}

// MARK: - SubcommandHelpers

/// Helpers for resolving subcommand selections and their associated parameters.
public enum SubcommandHelpers {

    /// Returns the active `ToolParameterDefinition` list for `config` and an optional `subcommand` token.
    ///
    /// When `subcommand` is `nil` or the tool has no subcommands, the top-level parameters are returned.
    public static func activeParameters(
        for config: ToolParameterConfig,
        subcommand: String?
    ) -> [ToolParameterDefinition] {
        guard config.hasSubcommands, let subcommand else {
            return config.parameters
        }
        return config.subcommands.first { $0.name == subcommand }?.parameters ?? config.parameters
    }

    /// Returns the ordered list of subcommand token names for `config`.
    public static func subcommandNames(for config: ToolParameterConfig) -> [String] {
        config.subcommands.map(\.name)
    }
}
