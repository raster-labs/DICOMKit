// CLIWorkshopHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for CLI Tools Workshop (Milestone 16)
// NEMA-verified: 2026a, checked 2026-10-06 — the 33 CLI Workshop forms diffed by script against the dicom-* ArgumentParser surfaces (Scripts/diff_studio.py --group G1 parity: flags, defaults, picker values and the cli_contracts.py standard rows; 0 FAIL, 2 PEND: P-STUDIO-ANON-PS315 --profile default, P-STUDIO-MWL-CREATE; DEFR rows are diff_studio.py parser limits) in three passes — file tools (14 ids: PS3.11 Tables A.1-1..N.1-1 profile identifiers, PS3.10 8.1/8.2/8.5 File-set rules, PS3.3 Table 10-3 / C.7.6.16.1.2 Frame numbers from 1, PS3.18 F.2.5 / PS3.19 Table A.1.5-2 empty attributes, PS3.6 Table A-1 keywords), network tools (11 ids: PS3.4 Tables C.6.1-1 / B.2-1 / C.4-2 / C.4-3 / K.6-1a / F.7.2-1, PS3.7 Tables 9.3-1 / 9.3-9 / 9.3-6, PS3.3 C.4.10 / C.30.1 / C.30.2, PS3.16 CID 9301, PS3.18 Tables 9.1.2-2 / 8.7.4-1 / 11.7.1.4), pixel and codec tools (8 ids: PS3.15 Annex E Table E.1-1 Option columns and E.3 / PS3.16 CID 7050, PS3.3 Table C.8-24 Conversion Type terms, Table C.24-2, PS3.16 CID 3000 and PS3.3 A.32.5-A.32.7 / Table C.7-1 for video, PS3.6 Table A-1 convert tokens = DICOMConverter.cliTokens and the compress native --syntax set, PS3.5 Table 6.2-1 / 9.1 refusals); pickers come from the shared engine enums / catalogs or the DocBook terms, help texts are the CLIs' (Scripts/diff_studio_g1.py, 20 checks); the help texts and pickers of the rules lifted out of the CLIs are the engine symbols the CLIs use (DICOMConverter.transferSyntaxOptionHelpWithKeywords D268, VideoOptionConformance / AudioChannelSourceOption D269, CompressionConsole.NativeTargetSyntax D267); no Workshop copy of a CLI rule is left here (WorkshopConvertPicker only maps a typed --transfer-syntax value onto its picker entry), script-checked by Scripts/diff_studio_g1.py

import Foundation
import DICOMCore
import DICOMKit
import DICOMDictionary
import DICOMWeb

// MARK: - 16.1 Network Configuration Helpers

/// Helpers for PACS network configuration validation and defaults.
public enum NetworkConfigHelpers: Sendable {

    /// Maximum allowed length for a DICOM AE Title (PS3.8).
    public static let maxAETitleLength: Int = 16

    /// Default DICOM port number.
    public static let defaultPort: Int = 11112

    /// Default timeout in seconds.
    public static let defaultTimeout: Int = 60

    /// Validates an AE Title string.
    public static func validateAETitle(_ aeTitle: String) -> Bool {
        !aeTitle.isEmpty && aeTitle.count <= maxAETitleLength && aeTitle == aeTitle.trimmingCharacters(in: .whitespaces)
    }

    /// Validates a port number.
    public static func validatePort(_ port: Int) -> Bool {
        port >= 1 && port <= 65535
    }

    /// Validates a timeout value in seconds.
    public static func validateTimeout(_ timeout: Int) -> Bool {
        timeout >= 5 && timeout <= 300
    }

    /// Validates a hostname or IP address (non-empty check).
    public static func validateHost(_ host: String) -> Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Returns a default network profile.
    public static func defaultProfile() -> CLINetworkProfile {
        CLINetworkProfile(
            name: "Default",
            aeTitle: "DICOMSTUDIO",
            calledAET: "ANY-SCP",
            host: "localhost",
            port: defaultPort,
            timeout: defaultTimeout,
            protocolType: .dicom,
            isDefault: true
        )
    }

    /// Builds the connection summary string for a profile.
    public static func connectionSummary(for profile: CLINetworkProfile) -> String {
        "\(profile.aeTitle) → \(profile.calledAET)@\(profile.host):\(profile.port) (\(profile.protocolType.displayName))"
    }
}

// MARK: - 16.2 Tool Catalog Helpers

/// Helpers for building the catalog of all 29 CLI tools.
public enum ToolCatalogHelpers: Sendable {

    /// Canonical modality codes for CLI Workshop modality pickers, drawn from
    /// ``ModalityMapping/allCodes`` — every current PS3.3 C.7.3.1.1.1 defined
    /// term (2026a), not a hand-maintained subset. Sorted alphabetically here
    /// because this flat list has no section headers; views that can show
    /// sections should prefer ``ModalityPicker``, which groups by category.
    private static let modalityAllowedValues: [String] = ModalityMapping.allCodes.sorted()

    /// Modality picker values including a leading empty "any modality" option,
    /// for optional filter fields (e.g. C-FIND / query modality filters).
    private static let optionalModalityAllowedValues: [String] = [""] + modalityAllowedValues

    /// Returns all 29 CLI tool definitions organized by tab.
    public static func allTools() -> [CLIToolDefinition] {
        var tools: [CLIToolDefinition] = []
        tools.append(contentsOf: fileInspectionTools())
        tools.append(contentsOf: fileProcessingTools())
        tools.append(contentsOf: fileOrganizationTools())
        tools.append(contentsOf: dataExportTools())
        tools.append(contentsOf: networkOperationsTools())
        tools.append(contentsOf: automationTools())
        return tools
    }

    /// Returns tools for the File Inspection tab.
    public static func fileInspectionTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-info", name: "dicom-info", displayName: "DICOM Info",
                              category: .fileInspection, sfSymbol: "info.circle",
                              briefDescription: "Display DICOM file metadata, tags, and statistics",
                              dicomStandardRef: "PS3.10"),
            CLIToolDefinition(id: "dicom-dump", name: "dicom-dump", displayName: "DICOM Dump",
                              category: .fileInspection, sfSymbol: "text.alignleft",
                              briefDescription: "Hexadecimal dump with DICOM structure annotations",
                              dicomStandardRef: "PS3.5"),
            CLIToolDefinition(id: "dicom-tags", name: "dicom-tags", displayName: "DICOM Tags",
                              category: .fileInspection, sfSymbol: "tag",
                              briefDescription: "Tag dictionary lookup, set, and delete operations",
                              dicomStandardRef: "PS3.6"),
            CLIToolDefinition(id: "dicom-diff", name: "dicom-diff", displayName: "DICOM Diff",
                              category: .fileInspection, sfSymbol: "arrow.left.arrow.right",
                              briefDescription: "Compare two DICOM files and show differences"),
        ]
    }

    /// Returns tools for the File Processing tab.
    public static func fileProcessingTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-convert", name: "dicom-convert", displayName: "DICOM Convert",
                              category: .fileProcessing, sfSymbol: "arrow.triangle.2.circlepath",
                              briefDescription: "Transfer syntax conversion and image export",
                              dicomStandardRef: "PS3.5"),
            CLIToolDefinition(id: "dicom-validate", name: "dicom-validate", displayName: "DICOM Validate",
                              category: .fileProcessing, sfSymbol: "checkmark.shield",
                              briefDescription: "DICOM conformance validation against IODs",
                              dicomStandardRef: "PS3.3"),
            CLIToolDefinition(id: "dicom-anon", name: "dicom-anon", displayName: "DICOM Anon",
                              category: .fileProcessing, sfSymbol: "person.crop.circle.badge.minus",
                              briefDescription: "Anonymize DICOM files following PS3.15 profiles",
                              dicomStandardRef: "PS3.15"),
            CLIToolDefinition(id: "dicom-compress", name: "dicom-compress", displayName: "DICOM Compress",
                              category: .fileProcessing, sfSymbol: "archivebox",
                              briefDescription: "Compress and decompress DICOM pixel data",
                              dicomStandardRef: "PS3.5", hasSubcommands: true),
        ]
    }

    /// Returns tools for the File Organization tab.
    public static func fileOrganizationTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-split", name: "dicom-split", displayName: "DICOM Split",
                              category: .fileOrganization, sfSymbol: "rectangle.split.2x1",
                              briefDescription: "Split multi-frame DICOM files into single frames"),
            CLIToolDefinition(id: "dicom-merge", name: "dicom-merge", displayName: "DICOM Merge",
                              category: .fileOrganization, sfSymbol: "rectangle.compress.vertical",
                              briefDescription: "Merge single-frame DICOM files into multi-frame"),
            CLIToolDefinition(id: "dicom-dcmdir", name: "dicom-dcmdir", displayName: "DICOMDIR",
                              category: .fileOrganization, sfSymbol: "folder.badge.plus",
                              briefDescription: "Create, validate, and manage DICOMDIR files",
                              dicomStandardRef: "PS3.10", hasSubcommands: true),
            CLIToolDefinition(id: "dicom-archive", name: "dicom-archive", displayName: "DICOM Archive",
                              category: .fileOrganization, sfSymbol: "tray.full",
                              briefDescription: "Archive DICOM files into organized directory structures"),
        ]
    }

    /// Returns tools for the Data Export tab.
    public static func dataExportTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-json", name: "dicom-json", displayName: "DICOM JSON",
                              category: .dataExport, sfSymbol: "curlybraces",
                              briefDescription: "Convert DICOM to/from JSON format",
                              dicomStandardRef: "PS3.18"),
            CLIToolDefinition(id: "dicom-xml", name: "dicom-xml", displayName: "DICOM XML",
                              category: .dataExport, sfSymbol: "chevron.left.forwardslash.chevron.right",
                              briefDescription: "Convert DICOM to/from XML format",
                              dicomStandardRef: "PS3.19"),
            CLIToolDefinition(id: "dicom-pdf", name: "dicom-pdf", displayName: "DICOM PDF",
                              category: .dataExport, sfSymbol: "doc.richtext",
                              briefDescription: "Extract or encapsulate PDF documents in DICOM"),
            CLIToolDefinition(id: "dicom-image", name: "dicom-image", displayName: "DICOM Image",
                              category: .dataExport, sfSymbol: "photo",
                              briefDescription: "Extract images and create Secondary Capture objects"),
            CLIToolDefinition(id: "dicom-export", name: "dicom-export", displayName: "DICOM Export",
                              category: .dataExport, sfSymbol: "square.and.arrow.up.on.square",
                              briefDescription: "Export frames as images, contact sheets, or animations",
                              hasSubcommands: true),
            CLIToolDefinition(id: "dicom-pixedit", name: "dicom-pixedit", displayName: "Pixel Edit",
                              category: .dataExport, sfSymbol: "pencil.and.outline",
                              briefDescription: "Edit pixel data: mask, crop, fill, and invert"),
            CLIToolDefinition(id: "dicom-video", name: "dicom-video", displayName: "DICOM Video",
                              category: .dataExport, sfSymbol: "film",
                              briefDescription: "Wrap H.264/HEVC/MPEG-2 video in DICOM Video IODs and extract it back",
                              dicomStandardRef: "PS3.3 A.32.5", hasSubcommands: true),
        ]
    }

    /// Returns tools for the Network Operations tab.
    public static func networkOperationsTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-echo", name: "dicom-echo", displayName: "DICOM Echo",
                              category: .networkOperations, sfSymbol: "wave.3.right",
                              briefDescription: "Verify DICOM network connectivity with C-ECHO",
                              dicomStandardRef: "PS3.7", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-query", name: "dicom-query", displayName: "DICOM Query",
                              category: .networkOperations, sfSymbol: "magnifyingglass",
                              briefDescription: "Query DICOM servers with C-FIND",
                              dicomStandardRef: "PS3.4", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-send", name: "dicom-send", displayName: "DICOM Send",
                              category: .networkOperations, sfSymbol: "arrow.up.circle",
                              briefDescription: "Send DICOM files to servers with C-STORE",
                              dicomStandardRef: "PS3.4", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-retrieve", name: "dicom-retrieve", displayName: "DICOM Retrieve",
                              category: .networkOperations, sfSymbol: "arrow.down.circle",
                              briefDescription: "Retrieve DICOM files from PACS with C-MOVE/C-GET",
                              dicomStandardRef: "PS3.4", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-qr", name: "dicom-qr", displayName: "Query-Retrieve",
                              category: .networkOperations, sfSymbol: "arrow.up.arrow.down.circle",
                              briefDescription: "Combined query-retrieve workflow",
                              dicomStandardRef: "PS3.4", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-mwl", name: "dicom-mwl", displayName: "Modality Worklist",
                              category: .networkOperations, sfSymbol: "list.clipboard",
                              briefDescription: "Query Modality Worklist for scheduled procedures",
                              dicomStandardRef: "PS3.4", requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-mpps", name: "dicom-mpps", displayName: "MPPS",
                              category: .networkOperations, sfSymbol: "clock.arrow.2.circlepath",
                              briefDescription: "Modality Performed Procedure Step management",
                              dicomStandardRef: "PS3.4", hasSubcommands: true, requiresNetwork: true,
                              networkToolGroup: .dimse),
            CLIToolDefinition(id: "dicom-qido", name: "dicom-wado query", displayName: "QIDO-RS Query",
                              category: .networkOperations, sfSymbol: "magnifyingglass.circle",
                              briefDescription: "Query DICOMweb servers with QIDO-RS",
                              dicomStandardRef: "PS3.18", requiresNetwork: true,
                              networkToolGroup: .dicomweb),
            CLIToolDefinition(id: "dicom-wado", name: "dicom-wado retrieve", displayName: "WADO-RS Retrieve",
                              category: .networkOperations, sfSymbol: "arrow.down.circle",
                              briefDescription: "Retrieve DICOM objects via WADO-RS or WADO-URI",
                              dicomStandardRef: "PS3.18", requiresNetwork: true,
                              networkToolGroup: .dicomweb),
            CLIToolDefinition(id: "dicom-stow", name: "dicom-wado store", displayName: "STOW-RS Store",
                              category: .networkOperations, sfSymbol: "arrow.up.circle",
                              briefDescription: "Upload DICOM files via STOW-RS",
                              dicomStandardRef: "PS3.18", requiresNetwork: true,
                              networkToolGroup: .dicomweb),
            CLIToolDefinition(id: "dicom-ups", name: "dicom-wado ups", displayName: "UPS-RS Worklist",
                              category: .networkOperations, sfSymbol: "list.bullet.clipboard",
                              briefDescription: "Manage Unified Procedure Steps via UPS-RS",
                              dicomStandardRef: "PS3.18", hasSubcommands: true, requiresNetwork: true,
                              networkToolGroup: .dicomweb),
        ]
    }

    /// Returns network operations tools grouped by DIMSE vs DICOMweb.
    public static func groupedNetworkOperationsTools() -> [(group: NetworkToolGroup, tools: [CLIToolDefinition])] {
        let tools = networkOperationsTools()
        return NetworkToolGroup.allCases.compactMap { group in
            let matching = tools.filter { $0.networkToolGroup == group }
            return matching.isEmpty ? nil : (group: group, tools: matching)
        }
    }

    /// Returns tools for the Automation tab.
    public static func automationTools() -> [CLIToolDefinition] {
        [
            CLIToolDefinition(id: "dicom-study", name: "dicom-study", displayName: "Study Tools",
                              category: .automation, sfSymbol: "folder.badge.person.crop",
                              briefDescription: "Study-level organize, summary, check, stats, compare",
                              hasSubcommands: true),
            CLIToolDefinition(id: "dicom-uid", name: "dicom-uid", displayName: "UID Tools",
                              category: .automation, sfSymbol: "number",
                              briefDescription: "Generate, validate, lookup, and regenerate UIDs",
                              hasSubcommands: true),
            CLIToolDefinition(id: "dicom-script", name: "dicom-script", displayName: "Scripting",
                              category: .automation, sfSymbol: "scroll",
                              briefDescription: "Run, validate, and template DICOM processing scripts",
                              hasSubcommands: true),
        ]
    }

    /// Returns tools filtered by the given tab category.
    public static func tools(for tab: CLIWorkshopTab) -> [CLIToolDefinition] {
        allTools().filter { $0.category == tab }
    }

    /// Returns the total count of tools.
    public static var totalToolCount: Int { 33 }

    // MARK: - Tool Purpose Descriptions

    /// Returns a rich multi-sentence purpose description for the given tool ID.
    /// Used in the CLI Workshop tool header panel.
    public static func toolPurposeDescription(for toolID: String) -> String {
        switch toolID {
        case "dicom-convert":
            return """
                dicom-convert re-encodes DICOM files into a different transfer syntax, \
                or exports their pixel data to a standard image format (PNG, JPEG, or TIFF). \
                It supports single-file and bulk-directory conversion. \
                For image export it can apply window/level values so output images are \
                correctly windowed — useful for CT, MR, and X-ray reading applications. \
                Conversions are handled natively using DICOMKit without any third-party dependencies.
                """
        case "dicom-info":
            return "Displays all DICOM tags, pixel statistics, and file metadata from a DICOM file or directory."
        case "dicom-dump":
            return "Prints a hex dump of a DICOM file annotated with tag names and VR information."
        case "dicom-tags":
            return "Adds, modifies, or deletes tags in a DICOM file using set/delete/copy-from operations."
        case "dicom-diff":
            return "Compares two DICOM files and reports tag differences, added/removed tags, and optionally pixel data differences."
        case "dicom-validate":
            return "Checks a DICOM file for conformance against the matching IOD and returns a structured report."
        case "dicom-anon":
            return "Removes or replaces patient-identifying attributes according to PS3.15 anonymization profiles."
        case "dicom-compress":
            return "Compresses or decompresses DICOM pixel data using standard photometric and codec options."
        case "dicom-query":
            return "Queries a DICOM server using C-FIND to search for patients, studies, series, or instances."
        case "dicom-send":
            return "Sends DICOM files to a remote storage SCP using C-STORE."
        case "dicom-retrieve":
            return "Retrieves DICOM objects from a remote server using C-MOVE or C-GET."
        case "dicom-echo":
            return "Sends one or more C-ECHO requests to verify DICOM network connectivity and round-trip latency."
        case "dicom-video":
            return """
                dicom-video wraps an already-conformant H.264/HEVC/MPEG-2 bitstream in a \
                DICOM Video IOD without re-encoding it, and extracts it back out. Remuxing \
                preserves the camera's pixel data bit-for-bit; non-conformant input is \
                rejected with the specific violated constraint rather than silently \
                re-encoded, because re-encoding degrades diagnostic imagery on every pass.
                """
        default:
            return ""
        }
    }

    /// Returns short capability bullet points for the given tool ID.
    /// Each string is a terse label (no trailing punctuation).
    public static func toolCapabilities(for toolID: String) -> [String] {
        switch toolID {
        case "dicom-convert":
            return [
                "Transfer syntax re-encoding (PS3.5)",
                "Compressed encoding: JPEG, JPEG 2000, JPEG-LS, RLE",
                "Export to PNG, JPEG, TIFF",
                "Window / level adjustment on export",
                "Multi-frame: choose specific frame",
                "Batch directory conversion",
                "Strip private tags",
                "Post-conversion DICOM validation",
            ]
        case "dicom-video":
            return [
                "Remux without re-encoding (bit-for-bit pixel data)",
                "H.264 / HEVC / MPEG-2 in MP4 or MPEG-TS",
                "Conformance rejection naming the violated constraint",
                "Attributes derived from the bitstream, not the caller",
                "Endoscopic / microscopic / photographic SOP classes",
                "Batch a folder as one series or one series per clip",
                "Extract the bitstream back out",
            ]
        default:
            return []
        }
    }

    /// Returns M16-style parameter definitions for a tool by ID.
    static func rawParameterDefinitions(for toolID: String) -> [CLIParameterDefinition] {
        switch toolID {
        case "dicom-echo":
            return [
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "PACS server hostname or IP address (optionally host:port)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "Local Application Entity title (calling AE)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote server Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                CLIParameterDefinition(
                    id: "count", flag: "--count", displayName: "Echo Count",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Number of echo requests to send (default: 1)",
                    defaultValue: "1", minValue: 1, maxValue: 1000
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "30",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "30",
                    allowedValues: ["5", "10", "15", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "stats", flag: "--stats", displayName: "Show Statistics",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show statistics (min/avg/max round-trip time)"
                ),
                CLIParameterDefinition(
                    id: "diagnose", flag: "--diagnose", displayName: "Network Diagnostics",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Run network diagnostics"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including connection details"
                ),
            ]
        case "dicom-query":
            return [
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "PACS server hostname or IP address (optionally host:port)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "Local Application Entity title (calling AE)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote server Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                // The Query/Retrieve Level (0008,0052) values of PS3.4 2026a Tables C.6.1-1 /
                // C.6.2-1 in lower case — PATIENT, STUDY, SERIES, IMAGE — exactly the CLI's
                // QueryLevelOption (commit 695d961). The CLI still accepts "instance" as an
                // alias of image; the executor does too, but the picker names the wire value.
                CLIParameterDefinition(
                    id: "level", flag: "--level", displayName: "Query Level",
                    parameterType: .enumPicker, placeholder: "study",
                    helpText: "Query/Retrieve Level (0008,0052): patient, study, series, image — the values of PS3.4 Tables C.6.1-1 / C.6.2-1; 'instance' is accepted as an alias of image (default: study)",
                    defaultValue: "study",
                    allowedValues: ["patient", "study", "series", "image"]
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID (0010,0020)"
                ),
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN or DOE*",
                    helpText: "Patient's Name (0010,0010); * and ? wild cards per PS3.4 C.2.2.2.4"
                ),
                CLIParameterDefinition(
                    id: "study-date", flag: "--study-date", displayName: "Study Date",
                    parameterType: .textField, placeholder: "e.g. 20260101 or 20260101-20260310",
                    helpText: "Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD (up to and including) or YYYYMMDD- (from, PS3.4 C.2.2.2.5)"
                ),
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: ModalityOptionValidator.helpText("filter"),
                    allowedValues: optionalModalityAllowedValues
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID to filter by (0020,000D)"
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series-uid", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Series Instance UID to filter by (0020,000E)"
                ),
                CLIParameterDefinition(
                    id: "accession-number", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession Number to filter by (0008,0050)"
                ),
                CLIParameterDefinition(
                    id: "study-description", flag: "--study-description", displayName: "Study Description",
                    parameterType: .textField, placeholder: "e.g. CHEST* or *ABDOMEN*",
                    helpText: "Study description filter — supports wildcards (0008,1030)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "referring-physician", flag: "--referring-physician", displayName: "Referring Physician",
                    parameterType: .textField, placeholder: "e.g. SMITH^JANE",
                    helpText: "Referring physician name (0008,0090)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["5", "10", "15", "30", "60", "120", "300"]
                ),
                // dicom-json is the PS3.18 2026a F.2 DICOM JSON Model (P-QUERY-JSON); json / csv
                // are the tool's "(GGGG,EEEE)"-keyed summaries. Rendered by the shared
                // DICOMQueryResultFormatter with DICOMWeb's DICOMJSONEncoder, as the CLI does.
                CLIParameterDefinition(
                    id: "output-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "table",
                    helpText: "Output format: table, json, csv, compact, dicom-json (default: table). json is the tool's {\"(GGGG,EEEE)\": \"value\"} summary; dicom-json is the PS3.18 F.2 DICOM JSON Model (\"00100010\": {\"vr\": \"PN\", \"Value\": [...]})",
                    defaultValue: "table",
                    allowedValues: ["table", "json", "csv", "compact", "dicom-json"]
                ),
                CLIParameterDefinition(
                    id: "csv-keywords", flag: "--csv-keywords", displayName: "CSV Keyword Header",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "CSV header row names each column by its PS3.6 keyword (e.g. PatientName) instead of (GGGG,EEEE)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "output-format", values: ["csv"])
                ),
                CLIParameterDefinition(
                    id: "include-parent-keys", flag: "--include-parent-keys", displayName: "Include Parent Keys",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Non-baseline: at SERIES/IMAGE level also request parent-level attributes (Patient Name/ID, Study Date/Description, Accession) as return keys, for lenient SCPs such as dcm4chee (PS3.4 C.4.1.2.1 does not allow them)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "level", values: ["series", "image"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including query details"
                ),
            ]
        case "dicom-send":
            return [
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "PACS server hostname or IP address (optionally host:port)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "Local Application Entity title (calling AE)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote server Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                CLIParameterDefinition(
                    id: "files", flag: "", displayName: "DICOM Files",
                    parameterType: .filePath, placeholder: "e.g. a.dcm; b.dcm or a directory",
                    helpText: "DICOM files or directories to send (C-STORE). Separate with “ ; ”. Picked/dropped files are mirrored into the previewed command.",
                    isRequired: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive Scan",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Recursively scan directories for DICOM files",
                    defaultValue: "false"
                ),
                CLIParameterDefinition(
                    id: "verify", flag: "--verify", displayName: "Verify (C-ECHO)",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verify connection with C-ECHO before sending"
                ),
                // Priority (0000,0700) of the C-STORE-RQ, PS3.7 2026a Table 9.3-1: LOW = 0002H,
                // MEDIUM = 0000H, HIGH = 0001H — the CLI's PriorityOption, mapped onto DIMSEPriority.
                CLIParameterDefinition(
                    id: "priority", flag: "--priority", displayName: "Priority",
                    parameterType: .enumPicker, placeholder: "medium",
                    helpText: "C-STORE Priority (0000,0700): low (0002H), medium (0000H), high (0001H) — PS3.7 Table 9.3-1 (default: medium)",
                    defaultValue: "medium",
                    allowedValues: ["low", "medium", "high"]
                ),
                CLIParameterDefinition(
                    id: "retry", flag: "--retry", displayName: "Retry Attempts",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Number of retry attempts on failure (exponential backoff)",
                    isAdvanced: true,
                    defaultValue: "0", minValue: 0, maxValue: 10
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["10", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "dry-run", flag: "--dry-run", displayName: "Dry Run",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show what would be sent without actually sending",
                    isAdvanced: true
                ),
                // Transfer Syntax Name of the proposed Presentation Context (PS3.8 7.1.1.13;
                // PS3.6 Table A-1). dicom-send never transcodes: the value must be the file's
                // own transfer syntax, so the default (empty) sends the file unchanged.
                // Tokens: DICOMCore.TransferSyntax.negotiableImageTokens — the SAME alias
                // list TransferSyntax.parse resolves on both surfaces.
                CLIParameterDefinition(
                    id: "transfer-syntax", flag: "--transfer-syntax", displayName: "Transfer Syntax",
                    parameterType: .enumPicker, placeholder: "Send unchanged",
                    helpText: "Transfer syntax to negotiate for the C-STORE presentation context. dicom-send sends files as-is and never transcodes, so this must match the file's own transfer syntax (the send fails otherwise — use dicom-convert to change it). Omit to send the file unchanged.",
                    isAdvanced: true,
                    allowedValues: [""] + TransferSyntax.negotiableImageTokens
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including progress"
                ),
            ]
        case "dicom-retrieve":
            return [
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "PACS server hostname or IP address (optionally host:port)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "Local Application Entity title (calling AE)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote server Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                CLIParameterDefinition(
                    id: "method", flag: "--method", displayName: "Retrieval Method",
                    parameterType: .enumPicker, placeholder: "c-move",
                    helpText: "C-MOVE instructs the server to push files to a destination; C-GET pulls directly",
                    defaultValue: "c-move",
                    allowedValues: ["c-move", "c-get"]
                ),
                CLIParameterDefinition(
                    id: "move-dest", flag: "--move-dest", displayName: "Move Destination AET",
                    parameterType: .textField, placeholder: "e.g. MY_STORE_SCP",
                    helpText: "Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)"
                ),
                // Query/Retrieve Level (0008,0052) follows the most specific UID given
                // (PS3.4 2026a Table C.6.1-1: STUDY / SERIES / IMAGE); baseline retrieval
                // needs the Unique Key of every level above (C.4.2.2.1 / C.4.3.2.1) unless
                // relational-retrieval is negotiated (C.4.2.2.2.1 / C.4.3.2.2.1).
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID (0020,000D) to retrieve — Query/Retrieve Level STUDY"
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series-uid", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Series Instance UID (0020,000E) to retrieve — Query/Retrieve Level SERIES (requires --study-uid unless --relational-retrieve)"
                ),
                CLIParameterDefinition(
                    id: "instance-uid", flag: "--instance-uid", displayName: "SOP Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "SOP Instance UID (0008,0018) to retrieve — Query/Retrieve Level IMAGE (requires --study-uid and --series-uid unless --relational-retrieve)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "uid-list", flag: "--uid-list", displayName: "UID List File",
                    parameterType: .filePath, placeholder: "e.g. study_uids.txt",
                    helpText: "File containing list of Study UIDs to retrieve (one per line)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "Choose a folder… (defaults to ~/Downloads/DICOMStudio)",
                    helpText: "Directory where retrieved files will be saved. Leave empty to use ~/Downloads/DICOMStudio.",
                    defaultValue: ""
                ),
                CLIParameterDefinition(
                    id: "hierarchical", flag: "--hierarchical", displayName: "Hierarchical Output",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Organize C-GET output hierarchically (<output>/<Study Instance UID>/<Series Instance UID>/); C-MOVE output is stored by the move destination"
                ),
                CLIParameterDefinition(
                    id: "parallel", flag: "--parallel", displayName: "Parallel Operations",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Number of parallel retrieval operations (default: 1)",
                    isAdvanced: true,
                    defaultValue: "1", minValue: 1, maxValue: 8
                ),
                // Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ, PS3.7 2026a Tables 9.3-9 /
                // 9.3-6: LOW = 0002H, MEDIUM = 0000H, HIGH = 0001H (RetrievePriorityOption →
                // DIMSEPriority → RetrieveConfiguration.priority).
                CLIParameterDefinition(
                    id: "priority", flag: "--priority", displayName: "Priority",
                    parameterType: .enumPicker, placeholder: "medium",
                    helpText: "Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ: low (0002H), medium (0000H), high (0001H) — PS3.7 Tables 9.3-9 / 9.3-6 (default: medium)",
                    isAdvanced: true,
                    defaultValue: "medium",
                    allowedValues: ["low", "medium", "high"]
                ),
                CLIParameterDefinition(
                    id: "relational-retrieve", flag: "--relational-retrieve", displayName: "Relational Retrieve",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Propose relational-retrieval in a SOP Class Extended Negotiation Sub-Item (PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1). With it, --series-uid or --instance-uid may be given without the UIDs of the levels above (PS3.4 C.4.2.2.2.1); if the SCP turns relational-retrieval down, such a request is not sent (exit 1)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["10", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "transfer-syntax", flag: "--transfer-syntax", displayName: "Transfer Syntax",
                    parameterType: .enumPicker, placeholder: "Any (negotiate)",
                    helpText: "Requested transfer syntax for retrieved files — applies directly to C-GET and is advisory for C-MOVE. Accepts any name/UID the shared parser understands; canonical tokens: \(TransferSyntax.negotiableImageTokens.joined(separator: ", ")).",
                    // Single source of truth: DICOMCore's TransferSyntax.negotiableImageTokens —
                    // the same UID-level list the dicom-retrieve/dicom-qr CLIs derive their
                    // --transfer-syntax help from. Every token parses via TransferSyntax.parse
                    // (the SAME parser the CLI uses), so the picker never drifts from the CLI.
                    allowedValues: [""] + TransferSyntax.negotiableImageTokens
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including progress"
                ),
            ]
        case "dicom-qr":
            return [
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "PACS server hostname or IP address (optionally host:port)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "Local Application Entity title (calling AE)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote server Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                CLIParameterDefinition(
                    id: "mode", flag: "", displayName: "Operation Mode",
                    parameterType: .flagPicker, placeholder: "interactive",
                    helpText: "Interactive: in-app retrieves all results without a prompt (previews as --auto); Auto: retrieve all matches; Review: query only",
                    defaultValue: "interactive",
                    allowedValues: ["interactive", "auto", "review"],
                    // The app cannot prompt for a study selection, so its
                    // "interactive" state behaves as --auto — preview the
                    // truthful token rather than a --interactive the pasted
                    // command would answer differently.
                    cliMapping: ["interactive": "--auto"]
                ),
                CLIParameterDefinition(
                    id: "method", flag: "--method", displayName: "Retrieval Method",
                    parameterType: .enumPicker, placeholder: "c-move",
                    helpText: "C-MOVE instructs the server to push files; C-GET pulls directly",
                    defaultValue: "c-move",
                    allowedValues: ["c-move", "c-get"]
                ),
                CLIParameterDefinition(
                    id: "move-dest", flag: "--move-dest", displayName: "Move Destination AET",
                    parameterType: .textField, placeholder: "e.g. MY_STORE_SCP",
                    helpText: "Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)"
                ),
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN or DOE*",
                    helpText: "Patient's Name (0010,0010) — wildcards * and ? per PS3.4 C.2.2.2.4 (case handling of PN matching is the SCP's)"
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID (0010,0020)"
                ),
                CLIParameterDefinition(
                    id: "study-date", flag: "--study-date", displayName: "Study Date",
                    parameterType: .textField, placeholder: "e.g. 20260101 or 20260101-20260310",
                    helpText: "Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD or YYYYMMDD- (PS3.4 C.2.2.2.5)"
                ),
                CLIParameterDefinition(
                    id: "accession", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession Number (0008,0050)"
                ),
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: ModalityOptionValidator.helpText("filter"),
                    allowedValues: optionalModalityAllowedValues
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID (0020,000D)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "study-description", flag: "--study-description", displayName: "Study Description",
                    parameterType: .textField, placeholder: "e.g. CHEST* or *ABDOMEN*",
                    helpText: "Study Description (0008,1030) — wildcards * and ? per PS3.4 C.2.2.2.4",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "include-parent-keys", flag: "--include-parent-keys", displayName: "Include Parent Keys",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Non-baseline: also request parent-level attributes as return keys at SERIES/INSTANCE level (dicom-qr queries at STUDY level, where every requested key is already level-appropriate; accepted for parity with dicom-query)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "Choose a folder… (defaults to ~/Downloads/DICOMStudio)",
                    helpText: "Directory where retrieved files will be saved. Leave empty to use ~/Downloads/DICOMStudio.",
                    defaultValue: ""
                ),
                CLIParameterDefinition(
                    id: "hierarchical", flag: "--hierarchical", displayName: "Hierarchical Output",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Organize C-GET output hierarchically (<output>/<Study Instance UID>/); C-MOVE output is stored by the move destination"
                ),
                CLIParameterDefinition(
                    id: "validate", flag: "--validate", displayName: "Validate Files",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Validate retrieved files",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "parallel", flag: "--parallel", displayName: "Parallel Operations",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Maximum concurrent retrievals: up to N studies are retrieved at once, each on its own association; per-study lines are printed in study order (default: 1)",
                    isAdvanced: true,
                    defaultValue: "1", minValue: 1, maxValue: 8
                ),
                // Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ, PS3.7 2026a Tables 9.3-9 /
                // 9.3-6 (QRPriorityOption → DIMSEPriority → RetrieveConfiguration.priority).
                CLIParameterDefinition(
                    id: "priority", flag: "--priority", displayName: "Priority",
                    parameterType: .enumPicker, placeholder: "medium",
                    helpText: "Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ: low (0002H), medium (0000H), high (0001H) — PS3.7 Tables 9.3-9 / 9.3-6 (default: medium)",
                    isAdvanced: true,
                    defaultValue: "medium",
                    allowedValues: ["low", "medium", "high"]
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["10", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "transfer-syntax", flag: "--transfer-syntax", displayName: "Transfer Syntax",
                    parameterType: .enumPicker, placeholder: "Any (negotiate)",
                    helpText: "Requested transfer syntax for retrieved files — negotiated during association setup. Accepts any name/UID the shared parser understands; canonical tokens: \(TransferSyntax.negotiableImageTokens.joined(separator: ", ")).",
                    // Single source of truth: DICOMCore's TransferSyntax.negotiableImageTokens —
                    // the same UID-level list the dicom-retrieve/dicom-qr CLIs derive their
                    // --transfer-syntax help from. Every token parses via TransferSyntax.parse
                    // (the SAME parser the CLI uses), so the picker never drifts from the CLI.
                    allowedValues: [""] + TransferSyntax.negotiableImageTokens
                ),
                CLIParameterDefinition(
                    id: "save-state", flag: "--save-state", displayName: "Save State File",
                    parameterType: .outputPath, placeholder: "query.state",
                    helpText: "Save the query/retrieval state to a JSON file — resumable later with `dicom-qr resume --state <file>` (shared format, so an app-saved state resumes in the terminal)",
                    isAdvanced: true
                ),
            ]
        case "dicom-mwl":
            return [
                // `query` is the dicom-mwl CLI's only subcommand (PS3.4 Annex K, C-FIND).
                // `create` is a Studio-only operation (HL7 ORM^O01 over MLLP or the archive's
                // REST API — no DIMSE service creates a worklist item); its fields are
                // isInternal and the preview is rendered commented out (P-STUDIO-MWL-CREATE).
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "query",
                    helpText: "Modality Worklist operation: query scheduled procedures (C-FIND, the dicom-mwl CLI) or create a new worklist item (in-app only: HL7 ORM^O01 or REST — dicom-mwl has no create subcommand)",
                    isRequired: true,
                    defaultValue: "query",
                    allowedValues: ["query", "create"]
                ),
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "Worklist SCP hostname or IP address (optionally host:port) (PS3.4 Annex K)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "MODALITY",
                    helpText: "Local AE title identifying this modality (up to 16 characters)",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote Worklist SCP Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                // ----- Query parameters (C-FIND) -----
                CLIParameterDefinition(
                    id: "date-from", flag: "--date", displayName: "Date",
                    parameterType: .textField, placeholder: "today / YYYYMMDD / YYYYMMDD-YYYYMMDD",
                    helpText: "Scheduled Procedure Step Start Date (0040,0002) filter: YYYYMMDD, 'today', 'tomorrow', or a DICOM date range (YYYYMMDD-YYYYMMDD, YYYYMMDD-, -YYYYMMDD; PS3.4 C.2.2.2.5.1). A leading-hyphen range needs the equals form: --date=-YYYYMMDD",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "time-from", flag: "--time", displayName: "Time",
                    parameterType: .textField, placeholder: "HHMMSS / HHMMSS-HHMMSS",
                    helpText: "Scheduled Procedure Step Start Time (0040,0003) filter: HHMMSS (or HH / HHMM / HHMMSS.FFFFFF, PS3.5 Table 6.2-1 TM), or a DICOM time range (HHMMSS-HHMMSS, HHMMSS-, -HHMMSS; PS3.4 C.2.2.2.5.2). Combined with --date as one continuous interval when both are ranges (PS3.4 Table K.6-1, remark under (0040,0003)). A leading-hyphen range needs the equals form: --time=-HHMMSS",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "station", flag: "--station", displayName: "Station AE Title",
                    parameterType: .textField, placeholder: "e.g. CT1",
                    helpText: "Scheduled Station AE Title (0040,0001) filter (PS3.4 Table K.6-1: Single Value Matching)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "patient", flag: "--patient", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN or DOE*",
                    helpText: "Patient's Name (0010,0010) filter (supports wildcards: *)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID (0010,0020) filter",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: ModalityOptionValidator.helpText("filter"),
                    allowedValues: optionalModalityAllowedValues,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                // Scheduled Procedure Step Status (0040,0020) Defined Terms, PS3.3 2026a Table
                // C.4-10 (C.4.10): SCHEDULED, ARRIVED, READY, STARTED, DEPARTED. IN PROGRESS /
                // COMPLETED / DISCONTINUED are Performed Procedure Step Status values (Table
                // C.4-14) and never appear in a worklist — the picker no longer offers them.
                CLIParameterDefinition(
                    id: "sps-status", flag: "--sps-status", displayName: "SPS Status",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: "Scheduled Procedure Step Status (0040,0020) filter. Defined Terms per PS3.3 Table C.4-10: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED (another value is sent as given, with a warning)",
                    allowedValues: ["", "SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "query-accession-number", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession Number (0008,0050) filter",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                CLIParameterDefinition(
                    // `query-` prefixed, like `query-accession-number`: the create form
                    // has its own Performing Physician field (`--physician`, internal),
                    // and a shared id would make the two forms read each other's value
                    // — paramValue() keys on the id alone.
                    id: "query-performing-physician", flag: "--performing-physician", displayName: "Performing Physician",
                    parameterType: .textField, placeholder: "e.g. SMITH^JOHN or SMITH*",
                    helpText: "Scheduled Performing Physician's Name (0040,0006) filter (supports wildcards: *)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                // Specific Character Set (0008,0005) of the Identifier (PS3.4 Table K.6-1a;
                // PS3.5 6.1.2 / Table 6.1-1 Defined Terms); by default the narrowest set is chosen.
                CLIParameterDefinition(
                    id: "specific-character-set", flag: "--specific-character-set", displayName: "Specific Character Set",
                    parameterType: .textField, placeholder: "e.g. ISO_IR 100 or ISO_IR 192",
                    helpText: "Force the Specific Character Set (0008,0005) of the query, e.g. ISO_IR 100 or ISO_IR 192. By default the narrowest set that represents every text key is chosen (none for pure ASCII)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
                ),
                // ----- Create parameters (DICOMStudio-internal, no CLI equivalent) -----
                // Note: `dicom-mwl` CLI only supports the `query` subcommand.
                // MWL item creation is performed by DICOMStudio via HL7 ORM^O01
                // or REST API — these parameters drive the internal execution
                // but are excluded from the command preview (`isInternal: true`).
                CLIParameterDefinition(
                    id: "create-method", flag: "", displayName: "Create Method",
                    parameterType: .enumPicker, placeholder: "hl7",
                    helpText: "How to create the worklist item. HL7 (recommended): sends an ORM^O01 order message via MLLP — automatically creates the patient and worklist. REST: posts DICOM JSON to the server's REST API (requires the patient to exist first).",
                    isInternal: true,
                    defaultValue: "hl7",
                    allowedValues: ["hl7", "rest"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "hl7-port", flag: "--hl7-port", displayName: "HL7 Port",
                    parameterType: .integerField, placeholder: "2575",
                    helpText: "HL7 MLLP listener port on the server (default: 2575 for dcm4chee-arc)",
                    isInternal: true,
                    defaultValue: "2575", minValue: 1, maxValue: 65535,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN",
                    helpText: "Patient's Name (0010,0010) — required for worklist creation",
                    isRequired: true,
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID (0010,0020) — required for worklist creation",
                    isRequired: true,
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "patient-dob", flag: "--patient-dob", displayName: "Patient Birth Date",
                    parameterType: .textField, placeholder: "YYYYMMDD",
                    helpText: "Patient's Birth Date (0010,0030) in YYYYMMDD format",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "patient-sex", flag: "--patient-sex", displayName: "Patient Sex",
                    parameterType: .enumPicker, placeholder: "Unknown",
                    helpText: "Patient's Sex (0010,0040)",
                    isInternal: true,
                    allowedValues: ["", "M", "F", "O"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "accession-number", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession Number (0008,0050) — links worklist item to the imaging order",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "referring-physician", flag: "--referring-physician", displayName: "Referring Physician",
                    parameterType: .textField, placeholder: "e.g. SMITH^JANE",
                    helpText: "Referring Physician's Name (0008,0090)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "procedure-id", flag: "--procedure-id", displayName: "Requested Procedure ID",
                    parameterType: .textField, placeholder: "e.g. PROC001",
                    helpText: "Requested Procedure ID (0040,1001)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "procedure-desc", flag: "--procedure-desc", displayName: "Procedure Description",
                    parameterType: .textField, placeholder: "e.g. CT Head Without Contrast",
                    helpText: "Requested Procedure Description (0032,1060)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "create-modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "CT",
                    helpText: "Scheduled modality for the procedure step (0008,0060)",
                    isInternal: true,
                    defaultValue: "CT",
                    allowedValues: modalityAllowedValues,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "scheduled-station", flag: "--scheduled-station", displayName: "Scheduled Station AET",
                    parameterType: .textField, placeholder: "e.g. CT1",
                    helpText: "Scheduled Station AE Title (0040,0001) — the modality that will perform the procedure",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "station-name", flag: "--station-name", displayName: "Station Name",
                    parameterType: .textField, placeholder: "e.g. CT_SCANNER_1",
                    helpText: "Scheduled Station Name (0040,0010)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "scheduled-date", flag: "--scheduled-date", displayName: "Scheduled Date",
                    parameterType: .textField, placeholder: "YYYYMMDD or today",
                    helpText: "Scheduled Procedure Step Start Date (0040,0002) — defaults to today",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "scheduled-time", flag: "--scheduled-time", displayName: "Scheduled Time",
                    parameterType: .textField, placeholder: "HHMMSS e.g. 143000",
                    helpText: "Scheduled Procedure Step Start Time (0040,0003)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "sps-id", flag: "--sps-id", displayName: "Procedure Step ID",
                    parameterType: .textField, placeholder: "e.g. SPS001",
                    helpText: "Scheduled Procedure Step ID (0040,0009) — defaults to SPS001",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "sps-desc", flag: "--sps-desc", displayName: "Step Description",
                    parameterType: .textField, placeholder: "e.g. CT Head Scan",
                    helpText: "Scheduled Procedure Step Description (0040,0007)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "performing-physician", flag: "--physician", displayName: "Performing Physician",
                    parameterType: .textField, placeholder: "e.g. JONES^ALICE",
                    helpText: "Scheduled Performing Physician's Name (0040,0006)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "rest-base-url", flag: "--rest-url", displayName: "REST Base URL",
                    parameterType: .textField, placeholder: "e.g. http://host:8080/dcm4chee-arc",
                    helpText: "REST base URL for MWL item creation. MWL creation uses the server's REST API (not DIMSE). Default: http://<host>:8080/dcm4chee-arc",
                    isAdvanced: true,
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["rest"])
                ),
                CLIParameterDefinition(
                    id: "sending-application", flag: "--sending-app", displayName: "Sending Application",
                    parameterType: .textField, placeholder: "DICOMSTUDIO",
                    helpText: "HL7 MSH-3 Sending Application name (default: DICOMSTUDIO)",
                    isAdvanced: true,
                    isInternal: true,
                    defaultValue: "DICOMSTUDIO",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])
                ),
                CLIParameterDefinition(
                    id: "sending-facility", flag: "--sending-facility", displayName: "Sending Facility",
                    parameterType: .textField, placeholder: "IMAGING",
                    helpText: "HL7 MSH-4 Sending Facility name (default: IMAGING)",
                    isAdvanced: true,
                    isInternal: true,
                    defaultValue: "IMAGING",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])
                ),
                CLIParameterDefinition(
                    id: "receiving-application", flag: "--receiving-app", displayName: "Receiving Application",
                    parameterType: .textField, placeholder: "DCM4CHEE",
                    helpText: "HL7 MSH-5 Receiving Application name (default: DCM4CHEE)",
                    isAdvanced: true,
                    isInternal: true,
                    defaultValue: "DCM4CHEE",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])
                ),
                CLIParameterDefinition(
                    id: "receiving-facility", flag: "--receiving-facility", displayName: "Receiving Facility",
                    parameterType: .textField, placeholder: "HOSPITAL",
                    helpText: "HL7 MSH-6 Receiving Facility name (default: HOSPITAL)",
                    isAdvanced: true,
                    isInternal: true,
                    defaultValue: "HOSPITAL",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])
                ),
                // ----- Common parameters -----
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["5", "10", "15", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "json", flag: "--json", displayName: "JSON Output",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Output as JSON. Keys are PS3.6 keywords (e.g. ScheduledProcedureStepStartDate, ReferencedStudySequence); the abbreviated keys SPSStartDate, SPSStartTime, SPSStatus, SPSID, SPSDescription, SPSLocation, ScheduledPerformingPhysician, RequestedProcedureCode, ScheduledProtocolCodes, ReferencedStudySOPInstanceUID are still written but deprecated"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output"
                ),
            ]
        case "dicom-mpps":
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "create",
                    helpText: "MPPS operation: create a new procedure step (N-CREATE) or update an existing one (N-SET)",
                    isRequired: true,
                    defaultValue: "create",
                    allowedValues: ["create", "update"]
                ),
                CLIParameterDefinition(
                    id: "host", flag: "--host", displayName: "Host",
                    parameterType: .textField, placeholder: "hostname or IP address",
                    helpText: "MPPS SCP hostname or IP address (optionally host:port) (PS3.4 Annex F)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "port", flag: "--port", displayName: "Port",
                    parameterType: .integerField, placeholder: "11112",
                    helpText: "PACS server port (default: 11112)",
                    defaultValue: "11112", minValue: 1, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "MODALITY",
                    helpText: "Local AE title identifying the modality sending MPPS notifications",
                    isRequired: true,
                    defaultValue: "DICOMSTUDIO"
                ),
                CLIParameterDefinition(
                    id: "called-aet", flag: "--called-aet", displayName: "Called AE Title",
                    parameterType: .textField, placeholder: "ANY-SCP",
                    helpText: "Remote MPPS SCP Application Entity title",
                    defaultValue: "ANY-SCP"
                ),
                // ----- N-CREATE parameters (PS3.4 Table F.7.2-1) -----
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN",
                    helpText: "Patient's Name (0010,0010) — included in the N-CREATE dataset sent to the PACS",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID (0010,0020) — included in the N-CREATE dataset sent to the PACS",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID (0020,000D) — required for N-CREATE; for update (N-SET) it identifies the referenced study (with --series-uid) for the Referenced SOP Sequence",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create", "update"])
                ),
                CLIParameterDefinition(
                    id: "sps-id", flag: "--sps-id", displayName: "Scheduled Procedure Step ID",
                    parameterType: .textField, placeholder: "e.g. SPS001",
                    helpText: "Scheduled Procedure Step ID (0040,0009) from the MWL item — links this MPPS to the worklist entry so the server transitions the MWL status from SCHEDULED to IN PROGRESS",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "accession-number", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession Number (0008,0050) — links the MPPS to the imaging order and helps the server match the MWL item",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                // Modality (0008,0060) is Type 1 in the N-CREATE (PS3.4 2026a Table F.7.2-1 row
                // 105); the CLI refuses a create without it, so the picker offers no blank.
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "e.g. CT",
                    helpText: ModalityOptionValidator.helpText("value") + " Type 1 in the MPPS N-CREATE (PS3.4 Table F.7.2-1)",
                    isRequired: true,
                    allowedValues: modalityAllowedValues,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "patient-birth-date", flag: "--patient-birth-date", displayName: "Patient Birth Date",
                    parameterType: .textField, placeholder: "YYYYMMDD",
                    helpText: "Patient's Birth Date (0010,0030) as YYYYMMDD (VR DA, PS3.5 Table 6.2-1)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "patient-sex", flag: "--patient-sex", displayName: "Patient Sex",
                    parameterType: .enumPicker, placeholder: "Unspecified",
                    helpText: "Patient's Sex (0010,0040) Enumerated Values M, F or O (PS3.3 Table C.2-3)",
                    allowedValues: ["", "M", "F", "O"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "study-id", flag: "--study-id", displayName: "Study ID",
                    parameterType: .textField, placeholder: "e.g. 1",
                    helpText: "Study ID (0020,0010) — Type 2",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "station-name", flag: "--station-name", displayName: "Performed Station Name",
                    parameterType: .textField, placeholder: "e.g. CT_SCANNER_1",
                    helpText: "Performed Station Name (0040,0242) — Type 2",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "performed-location", flag: "--performed-location", displayName: "Performed Location",
                    parameterType: .textField, placeholder: "e.g. Radiology Room 2",
                    helpText: "Performed Location (0040,0243) — Type 2",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "procedure-step-id", flag: "--procedure-step-id", displayName: "Performed Procedure Step ID",
                    parameterType: .textField, placeholder: "e.g. PPS1 (default: 1)",
                    helpText: "Performed Procedure Step ID (0040,0253) — Type 1. Distinct from the Requested Procedure ID; previously the two were conflated",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "procedure-step-description", flag: "--procedure-step-description", displayName: "Performed Procedure Step Description",
                    parameterType: .textField, placeholder: "e.g. CT Chest with contrast",
                    helpText: "Performed Procedure Step Description (0040,0254) — Type 2",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "create-performing-physician", flag: "--performing-physician", displayName: "Performing Physician",
                    parameterType: .textField, placeholder: "e.g. SMITH^JOHN",
                    helpText: "Performing Physician's Name (0008,1050), DICOM PN format — carried in the Performed Series items, not at the data set root (PS3.4 Table F.7.2-1)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "requested-procedure-id", flag: "--requested-procedure-id", displayName: "Requested Procedure ID",
                    parameterType: .textField, placeholder: "e.g. RP1",
                    helpText: "Requested Procedure ID (0040,1001) from the MWL item — sent inside the Scheduled Step Attributes Sequence",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "requested-procedure-description", flag: "--requested-procedure-description", displayName: "Requested Procedure Description",
                    parameterType: .textField, placeholder: "e.g. CT Head Without Contrast",
                    helpText: "Requested Procedure Description (0032,1060) from the MWL item — Type 2 in the Scheduled Step Attributes Sequence",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "sps-description", flag: "--sps-description", displayName: "Scheduled Procedure Step Description",
                    parameterType: .textField, placeholder: "e.g. CT Chest",
                    helpText: "Scheduled Procedure Step Description (0040,0007) from the MWL item",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "referenced-study-uid", flag: "--referenced-study-uid", displayName: "Referenced Study UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Referenced Study SOP Instance UID (0008,1155) from the MWL item's Referenced Study Sequence",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                // ----- N-SET parameters -----
                CLIParameterDefinition(
                    id: "mpps-uid", flag: "--mpps-uid", displayName: "MPPS Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "MPPS SOP Instance UID from a previous create — required for update (N-SET)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                // An N-CREATE always starts the performed procedure step IN PROGRESS, so the
                // create operation offers only that status; the final COMPLETED / DISCONTINUED
                // transitions belong to the update (N-SET) operation (status-update below).
                // Both map to --status but only one is ever visible (and emitted) per operation.
                CLIParameterDefinition(
                    id: "status", flag: "--status", displayName: "Status",
                    parameterType: .enumPicker, placeholder: "IN PROGRESS",
                    helpText: "Performed Procedure Step Status (0040,0252) — an N-CREATE always starts the step IN PROGRESS",
                    defaultValue: "IN PROGRESS",
                    allowedValues: ["IN PROGRESS"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "status-update", flag: "--status", displayName: "Status",
                    parameterType: .enumPicker, placeholder: "COMPLETED",
                    helpText: "Final Performed Procedure Step Status (0040,0252) for the N-SET update — COMPLETED or DISCONTINUED",
                    defaultValue: "COMPLETED",
                    allowedValues: ["COMPLETED", "DISCONTINUED"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series-uid", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Series Instance UID of the acquired images — used in N-SET for Performed Series Sequence (0008,1115)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "image-uid", flag: "--image-uid", displayName: "Image SOP Instance UIDs",
                    parameterType: .textField, placeholder: "UID1; UID2",
                    helpText: "SOP Instance UIDs of acquired images — used in N-SET for the Referenced SOP Sequence (one --image-uid per value). Separate with “ ; ”.",
                    isRepeatable: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "sop-class-uid", flag: "--sop-class-uid", displayName: "Referenced SOP Class UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.10008.5.1.4.1.1.2 (CT)",
                    helpText: "SOP Class UID (0008,1150) of the referenced images, e.g. 1.2.840.10008.5.1.4.1.1.2 for CT. Without it the Secondary Capture class is sent, which is wrong for anything but SC",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "protocol-name", flag: "--protocol-name", displayName: "Protocol Name",
                    parameterType: .textField, placeholder: "UNSPECIFIED",
                    helpText: "Protocol Name (0018,1030) — Type 1 in every Performed Series item; dcm4chee/DCMTK reject a COMPLETED step without it (default: UNSPECIFIED)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "series-description", flag: "--series-description", displayName: "Series Description",
                    parameterType: .textField, placeholder: "e.g. Axial 1mm",
                    helpText: "Series Description (0008,103E) for the performed series",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "operator-name", flag: "--operator-name", displayName: "Operators' Name",
                    parameterType: .textField, placeholder: "e.g. JONES^MARY",
                    helpText: "Operators' Name (0008,1070), DICOM PN format — Type 2 in the Performed Series items",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "update-performing-physician", flag: "--performing-physician", displayName: "Performing Physician",
                    parameterType: .textField, placeholder: "e.g. SMITH^JOHN",
                    helpText: "Performing Physician's Name (0008,1050), DICOM PN format — Type 2 in the Performed Series items",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                // The placeholder and examples are real PS3.16 2026a CID 9301 pairs (Table D-1):
                // 110513 "Discontinued for unspecified reason", 110500 "Doctor canceled procedure",
                // 110501 "Equipment failure", 110507 "Patient did not arrive" (D85, D88).
                CLIParameterDefinition(
                    id: "discontinuation-reason", flag: "--discontinuation-reason", displayName: "Discontinuation Reason",
                    parameterType: .textField, placeholder: "110513|DCM|Discontinued for unspecified reason",
                    helpText: "Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281) as CODE|SCHEME|MEANING, only with --status DISCONTINUED. Codes normally come from PS3.16 CID 9300 'Procedure Discontinuation Reason' (which includes CID 9301) with scheme DCM, e.g. \"110513|DCM|Discontinued for unspecified reason\", \"110500|DCM|Doctor canceled procedure\", \"110501|DCM|Equipment failure\", \"110507|DCM|Patient did not arrive\"",
                    visibleWhenAll: [
                        CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"]),
                        CLIParameterVisibilityCondition(parameterId: "status-update", values: ["DISCONTINUED"])
                    ]
                ),
                CLIParameterDefinition(
                    id: "legacy-nset-scheduled-attributes", flag: "--legacy-nset-scheduled-attributes",
                    displayName: "Legacy N-SET Scheduled Attributes",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Also send the Scheduled Step Attributes Sequence (0040,0270) in the N-SET. PS3.4 Table F.7.2-1 forbids it; enable only for an SCP known to require it (e.g. some Orthanc builds)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "specific-character-set", flag: "--specific-character-set", displayName: "Specific Character Set",
                    parameterType: .textField, placeholder: "e.g. ISO_IR 100 or ISO_IR 192",
                    helpText: "Force the Specific Character Set (0008,0005). By default the narrowest set that represents every text value is chosen",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .enumPicker, placeholder: "60",
                    helpText: "Connection timeout in seconds",
                    defaultValue: "60",
                    allowedValues: ["5", "10", "15", "30", "60", "120", "300"]
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show detailed connection and operation information"
                ),
            ]
        case "dicom-qido":
            return [
                CLIParameterDefinition(
                    id: "url", flag: "", displayName: "Base URL",
                    parameterType: .textField, placeholder: "e.g. https://pacs.hospital.com/dicom-web",
                    helpText: "DICOMweb server base URL (PS3.18 §6.5)",
                    isRequired: true
                ),
                // The Search resource levels of PS3.18 2026a Tables 10.6.1-1 / 10.6.1-5 (the
                // CLI's QueryLevel: study, series, instance).
                CLIParameterDefinition(
                    id: "level", flag: "--level", displayName: "Query Level",
                    parameterType: .enumPicker, placeholder: "study",
                    helpText: "Query level: study, series, instance (default: study)",
                    defaultValue: "study",
                    allowedValues: ["study", "series", "instance"]
                ),
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN or DOE*",
                    helpText: "Patient name (wildcards * and ? supported)"
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient ID"
                ),
                CLIParameterDefinition(
                    id: "study-date", flag: "--study-date", displayName: "Study Date",
                    parameterType: .textField, placeholder: "e.g. 20260101 or 20260101-20260310",
                    helpText: "Study date or range (YYYYMMDD or YYYYMMDD-YYYYMMDD)"
                ),
                // Modalities In Study (0008,0061) at study / instance level, Modality (0008,0060)
                // at series level (PS3.18 Table 10.6.1-5), validated by the shared
                // ModalityOptionValidator as the CLI does (PS3.3 C.7.3.1.1.1).
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: ModalityOptionValidator.helpText("filter"),
                    allowedValues: optionalModalityAllowedValues
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID to filter results (0020,000D)"
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Series Instance UID to filter results (0020,000E)"
                ),
                CLIParameterDefinition(
                    id: "accession", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession number filter (0008,0050)"
                ),
                CLIParameterDefinition(
                    id: "study-description", flag: "--study-description", displayName: "Study Description",
                    parameterType: .textField, placeholder: "e.g. Chest CT or CHEST*",
                    helpText: "Study description filter — supports wildcards (0008,1030)",
                    isAdvanced: true
                ),
                // Series-level matching keys of PS3.18 Table 10.6.1-5. They only match at
                // the series level, so — exactly like the CLI, which warns and ignores them
                // elsewhere — the fields appear only when Query Level is `series`.
                CLIParameterDefinition(
                    id: "pps-start-date", flag: "--pps-start-date", displayName: "PPS Start Date",
                    parameterType: .textField, placeholder: "e.g. 20260101 or 20260101-20260310",
                    helpText: "Performed Procedure Step Start Date (0040,0244) — YYYYMMDD or a range",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "level", values: ["series"])
                ),
                CLIParameterDefinition(
                    id: "pps-start-time", flag: "--pps-start-time", displayName: "PPS Start Time",
                    parameterType: .textField, placeholder: "e.g. 101500 or 100000-180000",
                    helpText: "Performed Procedure Step Start Time (0040,0245) — HHMMSS or a range",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "level", values: ["series"])
                ),
                CLIParameterDefinition(
                    id: "qido-sps-id", flag: "--sps-id", displayName: "Scheduled Procedure Step ID",
                    parameterType: .textField, placeholder: "e.g. SPS001",
                    helpText: "Scheduled Procedure Step ID inside Request Attributes Sequence (0040,0275.0040,0009)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "level", values: ["series"])
                ),
                CLIParameterDefinition(
                    id: "qido-requested-procedure-id", flag: "--requested-procedure-id", displayName: "Requested Procedure ID",
                    parameterType: .textField, placeholder: "e.g. RP1",
                    helpText: "Requested Procedure ID inside Request Attributes Sequence (0040,0275.0040,1001)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "level", values: ["series"])
                ),
                // limit / offset are the unsigned paging parameters of PS3.18 Table 8.3.4-1 /
                // 8.3.4.4 (the CLI refuses a negative value); fuzzymatching=true is 8.3.4.2.
                CLIParameterDefinition(
                    id: "limit", flag: "--limit", displayName: "Result Limit",
                    parameterType: .integerField, placeholder: "100",
                    helpText: "Maximum number of results (default: 100)",
                    defaultValue: "100", minValue: 0, maxValue: 10000
                ),
                CLIParameterDefinition(
                    id: "offset", flag: "--offset", displayName: "Offset",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Offset for pagination (default: 0)",
                    isAdvanced: true, defaultValue: "0", minValue: 0, maxValue: 100000
                ),
                CLIParameterDefinition(
                    id: "fuzzy-matching", flag: "--fuzzy-matching", displayName: "Fuzzy Matching",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Ask for fuzzy matching of person names (PS3.18 8.3.4.2: fuzzymatching=true)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "auth", flag: "--auth", displayName: "Authentication",
                    parameterType: .enumPicker, placeholder: "none",
                    helpText: "Authentication method for the DICOMweb server",
                    isInternal: true,
                    defaultValue: "none",
                    allowedValues: ["none", "basic", "bearer"]
                ),
                // #45: the CLI's `--token` is Bearer-only, so the flag is emitted
                // (and the field shown) ONLY when auth=bearer. Basic auth runs
                // in-app through the internal username/password fields below —
                // it has no CLI-representable form.
                CLIParameterDefinition(
                    id: "token", flag: "--token", displayName: "Bearer Token",
                    parameterType: .secureField, placeholder: "Bearer token",
                    helpText: "OAuth2 bearer token for authentication",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["bearer"])
                ),
                CLIParameterDefinition(
                    id: "username", flag: "--username", displayName: "Username",
                    parameterType: .textField, placeholder: "e.g. admin",
                    helpText: "Username for basic authentication",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "password", flag: "", displayName: "Password",
                    parameterType: .secureField, placeholder: "Password",
                    helpText: "Password for basic authentication (in-app only — the dicom-wado CLI has no basic-auth flags)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                // dicom-json is the PS3.18 2026a F.2 DICOM JSON Model the origin server returned
                // (P-QUERY-JSON); json / csv are keyword-keyed tool summaries (QIDOResultFormatter).
                CLIParameterDefinition(
                    id: "output-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "table",
                    helpText: "Output format: table, json, csv, dicom-json (default: table). dicom-json is the PS3.18 F.2 DICOM JSON Model; json is a tool summary (keyword keys)",
                    defaultValue: "table",
                    allowedValues: ["table", "json", "csv", "dicom-json"]
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output"
                ),
                // (No timeout field: the dicom-wado `query` subcommand has no
                // --timeout option, and the executor never read one — removed to
                // keep the app surface truthful to the CLI.)
            ]
        case "dicom-wado":
            return [
                CLIParameterDefinition(
                    id: "wado-protocol", flag: "", displayName: "Protocol",
                    parameterType: .enumPicker, placeholder: "wado-rs",
                    helpText: "WADO-RS (modern RESTful) or WADO-URI (legacy query-parameter)",
                    isInternal: true,
                    defaultValue: "wado-rs",
                    allowedValues: ["wado-rs", "wado-uri"],
                    cliMapping: ["wado-uri": "--uri"]
                ),
                CLIParameterDefinition(
                    id: "url", flag: "", displayName: "Base URL",
                    parameterType: .textField, placeholder: "e.g. https://pacs.hospital.com/dicom-web",
                    helpText: "DICOMweb server base URL (PS3.18 §6.5)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID to retrieve (0020,000D)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Series Instance UID (0020,000E). Required for WADO-URI and series/instance retrieval."
                ),
                CLIParameterDefinition(
                    id: "instance-uid", flag: "--instance", displayName: "SOP Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "SOP Instance UID (0008,0018). Required for WADO-URI and instance/rendered retrieval."
                ),
                CLIParameterDefinition(
                    id: "frames", flag: "--frames", displayName: "Frame Numbers",
                    parameterType: .textField, placeholder: "e.g. 1,2,3",
                    helpText: "Frame numbers to retrieve (comma-separated, e.g., 1,2,3). WADO-RS: {frameList} (PS3.18 Table 10.4.1.6-1); WADO-URI: frameNumber names a single frame (9.5.1.2.1). Requires --series and --instance.",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "metadata", flag: "--metadata", displayName: "Metadata Only",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Retrieve only metadata (not pixel data)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-rs"])
                ),
                CLIParameterDefinition(
                    id: "rendered", flag: "--rendered", displayName: "Rendered Image",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Retrieve rendered image instead of DICOM. Requires --series and --instance.",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-rs"])
                ),
                CLIParameterDefinition(
                    id: "thumbnail", flag: "--thumbnail", displayName: "Thumbnail",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Retrieve thumbnail images",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-rs"])
                ),
                // ----- WADO-URI query parameters (PS3.18 2026a Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1) -----
                // Shown only with the WADO-URI protocol, like the CLI's validate() which refuses
                // them without --uri. contentType (9.1.2.2.1): application/dicom or a Rendered
                // Media Type of Table 8.7.4-1 — the shared WADOURIClient.MediaType.allowed list
                // the CLI maps through too; an empty value is the WADO-URI default (application/dicom).
                CLIParameterDefinition(
                    id: "content-type", flag: "--content-type", displayName: "Content Type",
                    parameterType: .enumPicker, placeholder: "application/dicom",
                    helpText: "Content type for WADO-URI: application/dicom (default), or a Rendered Media Type: image/jpeg, image/gif, image/png, image/jp2, image/jph, image/jxl, video/mpeg, video/mp4, video/H265, text/html, text/plain, text/xml, text/rtf, application/pdf (PS3.18 9.1.2.2.1, Table 8.7.4-1)",
                    allowedValues: [""] + WADOURIClient.MediaType.allowed.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "transfer-syntax", flag: "--transfer-syntax", displayName: "Transfer Syntax",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.10008.1.2.1",
                    helpText: "WADO-URI transferSyntax: Transfer Syntax UID for an application/dicom retrieve (PS3.18 9.4.1.2.3)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "anonymize", flag: "--anonymize", displayName: "Anonymize",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "WADO-URI anonymize=yes: ask the server to remove Individually Identifiable Information (PS3.18 9.4.1.2.1)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "charset", flag: "--charset", displayName: "Charset",
                    parameterType: .textField, placeholder: "e.g. UTF-8",
                    helpText: "WADO-URI charset: comma-separated character sets of the response, e.g. UTF-8 (PS3.18 9.1.2.2.2)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "annotation", flag: "--annotation", displayName: "Annotation",
                    parameterType: .textField, placeholder: "patient,technique",
                    helpText: "WADO-URI annotation (application/dicom) / imageAnnotation (rendered): patient, technique, or both comma-separated (PS3.18 9.4.1.2.2, Table 9.5.1-1)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "rows", flag: "--rows", displayName: "Rows",
                    parameterType: .integerField, placeholder: "e.g. 512",
                    helpText: "WADO-URI rows: pixel rows of the rendered image, a positive integer (PS3.18 9.5.1.2.4.1)",
                    isAdvanced: true, minValue: 1,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "columns", flag: "--columns", displayName: "Columns",
                    parameterType: .integerField, placeholder: "e.g. 512",
                    helpText: "WADO-URI columns: pixel columns of the rendered image, a positive integer (PS3.18 9.5.1.2.4.2)",
                    isAdvanced: true, minValue: 1,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "image-quality", flag: "--image-quality", displayName: "Image Quality",
                    parameterType: .integerField, placeholder: "1-100",
                    helpText: "WADO-URI imageQuality of a rendered image, 1-100 (PS3.18 9.5.1.2.3, 8.3.5.1.2)",
                    isAdvanced: true, minValue: 1, maxValue: 100,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "region", flag: "--region", displayName: "Region",
                    parameterType: .textField, placeholder: "xmin,ymin,xmax,ymax",
                    helpText: "WADO-URI region: xmin,ymin,xmax,ymax in normalized 0.0-1.0 image coordinates (PS3.18 9.5.1.2.5)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "window-center", flag: "--window-center", displayName: "Window Center",
                    parameterType: .textField, placeholder: "e.g. 40",
                    helpText: "WADO-URI windowCenter of a rendered image; needs --window-width (PS3.18 9.5.1.2.6.1)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "window-width", flag: "--window-width", displayName: "Window Width",
                    parameterType: .textField, placeholder: "e.g. 400",
                    helpText: "WADO-URI windowWidth of a rendered image; needs --window-center (PS3.18 9.5.1.2.6.2)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "presentation-uid", flag: "--presentation-uid", displayName: "Presentation State UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "WADO-URI presentationUID: Presentation State SOP Instance UID used to render; needs --presentation-series-uid (PS3.18 9.5.1.2.7.2)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "presentation-series-uid", flag: "--presentation-series-uid", displayName: "Presentation Series UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "WADO-URI presentationSeriesUID: Series of that Presentation State; needs --presentation-uid (PS3.18 9.5.1.2.7.1)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-uri"])
                ),
                CLIParameterDefinition(
                    id: "output", flag: "-o", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "e.g. ~/Downloads/studies",
                    helpText: "Output directory for retrieved files"
                ),
                // `-f, --format` of `retrieve` is the METADATA representation (PS3.18 Table 8.7.3-3:
                // DICOM JSON, Annex F / PS3.19 Native DICOM Model XML) — json | xml, default json,
                // exactly the CLI's MetadataFormat. Not the table/json/csv/dicom-json result
                // rendering of the query / ups subcommands.
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Metadata Format",
                    parameterType: .enumPicker, placeholder: "json",
                    helpText: "Output format for metadata: json, xml (default: json)",
                    defaultValue: "json",
                    allowedValues: ["json", "xml"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "wado-protocol", values: ["wado-rs"])
                ),
                CLIParameterDefinition(
                    id: "auth", flag: "--auth", displayName: "Authentication",
                    parameterType: .enumPicker, placeholder: "none",
                    helpText: "Authentication method for the DICOMweb server",
                    isInternal: true,
                    defaultValue: "none",
                    allowedValues: ["none", "basic", "bearer"]
                ),
                // #45: the CLI's `--token` is Bearer-only, so the flag is emitted
                // (and the field shown) ONLY when auth=bearer. Basic auth runs
                // in-app through the internal username/password fields below —
                // it has no CLI-representable form.
                CLIParameterDefinition(
                    id: "token", flag: "--token", displayName: "Bearer Token",
                    parameterType: .secureField, placeholder: "Bearer token",
                    helpText: "OAuth2 bearer token for authentication",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["bearer"])
                ),
                CLIParameterDefinition(
                    id: "username", flag: "--username", displayName: "Username",
                    parameterType: .textField, placeholder: "e.g. admin",
                    helpText: "Username for basic authentication",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "password", flag: "", displayName: "Password",
                    parameterType: .secureField, placeholder: "Password",
                    helpText: "Password for basic authentication (in-app only — the dicom-wado CLI has no basic-auth flags)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "timeout", flag: "--timeout", displayName: "Timeout (s)",
                    parameterType: .integerField, placeholder: "60",
                    helpText: "Connection timeout in seconds (default: 60)",
                    isAdvanced: true,
                    defaultValue: "60", minValue: 1, maxValue: 600
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including progress"
                ),
            ]
        case "dicom-stow":
            return [
                CLIParameterDefinition(
                    id: "url", flag: "", displayName: "Base URL",
                    parameterType: .textField, placeholder: "e.g. https://pacs.hospital.com/dicom-web",
                    helpText: "DICOMweb server base URL (PS3.18 §6.5)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "files", flag: "", displayName: "DICOM Files",
                    parameterType: .filePath, placeholder: "e.g. a.dcm; b.dcm or a directory",
                    helpText: "DICOM files or directories to upload via STOW-RS (PS3.18 §10.5). Separate with “ ; ”.",
                    isRequired: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study", displayName: "Target Study UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID for targeted storage (0020,000D)"
                ),
                CLIParameterDefinition(
                    id: "input", flag: "--input", displayName: "Input File List",
                    parameterType: .filePath, placeholder: "e.g. files.txt",
                    helpText: "File containing list of DICOM files to upload (one per line)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "batch", flag: "--batch", displayName: "Batch Size",
                    parameterType: .integerField, placeholder: "10",
                    helpText: "Number of files to upload per batch (default: 10)",
                    defaultValue: "10", minValue: 1, maxValue: 100
                ),
                CLIParameterDefinition(
                    id: "continue-on-error", flag: "--continue-on-error", displayName: "Continue on Error",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Continue on errors instead of stopping"
                ),
                CLIParameterDefinition(
                    id: "auth", flag: "--auth", displayName: "Authentication",
                    parameterType: .enumPicker, placeholder: "none",
                    helpText: "Authentication method for the DICOMweb server",
                    isInternal: true,
                    defaultValue: "none",
                    allowedValues: ["none", "basic", "bearer"]
                ),
                // #45: the CLI's `--token` is Bearer-only, so the flag is emitted
                // (and the field shown) ONLY when auth=bearer. Basic auth runs
                // in-app through the internal username/password fields below —
                // it has no CLI-representable form.
                CLIParameterDefinition(
                    id: "token", flag: "--token", displayName: "Bearer Token",
                    parameterType: .secureField, placeholder: "Bearer token",
                    helpText: "OAuth2 bearer token for authentication",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["bearer"])
                ),
                CLIParameterDefinition(
                    id: "username", flag: "--username", displayName: "Username",
                    parameterType: .textField, placeholder: "e.g. admin",
                    helpText: "Username for basic authentication",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "password", flag: "", displayName: "Password",
                    parameterType: .secureField, placeholder: "Password",
                    helpText: "Password for basic authentication (in-app only — the dicom-wado CLI has no basic-auth flags)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output including progress"
                ),
            ]
        case "dicom-ups":
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .enumPicker, placeholder: "search",
                    helpText: "UPS-RS operation: search workitems, get details, create workitem (from options or a JSON file), change state, or subscribe to / unsubscribe from events",
                    isRequired: true, isInternal: true,
                    defaultValue: "search",
                    allowedValues: ["search", "get", "create-workitem", "create-json", "change-state", "subscribe", "unsubscribe"],
                    // Each operation that maps to a bare CLI flag is emitted here, keyed off the
                    // selected operation, so picking the tab auto-adds the flag to the command
                    // (buildCommand applies the operation's defaultValue; a separate booleanToggle
                    // would NOT be emitted unless the user manually checked it). "get"/"change-state"
                    // carry their UID via --get/--update value flags instead, so they are not mapped.
                    cliMapping: [
                        "search": "--search",
                        "create-workitem": "--create-workitem",
                        "subscribe": "--subscribe",
                        "unsubscribe": "--unsubscribe",
                    ]
                ),

                CLIParameterDefinition(
                    id: "url", flag: "", displayName: "Base URL",
                    parameterType: .textField, placeholder: "e.g. https://pacs.hospital.com/dicom-web",
                    helpText: "DICOMweb server base URL (PS3.18 §6.5)",
                    isRequired: true
                ),
                // --search is emitted automatically via the operation cliMapping above
                // when the "search" tab is selected (no manual toggle needed).
                // --get <uid> (shown when operation=get)
                CLIParameterDefinition(
                    id: "get-uid", flag: "--get", displayName: "Get Workitem UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Get specific worklist item by UID",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["get"])
                ),
                // --create <json-file> (shown when operation=create-json)
                CLIParameterDefinition(
                    id: "create-json-file", flag: "--create", displayName: "Workitem JSON File",
                    parameterType: .filePath, placeholder: "workitem.json",
                    helpText: "Create a worklist item from a DICOM-JSON file (the CLI's --create <file> form)",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-json"])
                ),
                // --create-workitem is emitted automatically via the operation cliMapping
                // above when the "create-workitem" tab is selected (no manual toggle needed).
                // --change-state <uid> (shown when operation=change-state): Change Workitem State,
                // PS3.18 2026a 11.7 (P-WADO-UPS-UPDATE). --update is the CLI's deprecated alias;
                // the executor prints the CLI's deprecation note for it and refuses both at once.
                CLIParameterDefinition(
                    id: "update-uid", flag: "--change-state", displayName: "Workitem UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Change Workitem State (PS3.18 11.7) of the workitem with this UID; use with --state",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["change-state"])
                ),
                CLIParameterDefinition(
                    id: "update-uid-deprecated", flag: "--update", displayName: "Workitem UID (deprecated --update)",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Deprecated alias of --change-state (it performs Change Workitem State, PS3.18 11.7, not Update Workitem, 11.6)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["change-state"])
                ),
                // Create-specific parameters
                CLIParameterDefinition(
                    id: "workitem-uid", flag: "--workitem-uid", displayName: "Workitem UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619... (auto-generated if empty)",
                    helpText: "UPS Workitem SOP Instance UID — auto-generated for create if omitted",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem", "subscribe", "unsubscribe"])
                ),
                CLIParameterDefinition(
                    id: "subscribe-aet", flag: "--aet", displayName: "AE Title",
                    parameterType: .textField, placeholder: "e.g. DICOM_STUDIO",
                    helpText: "Local Application Entity Title for subscribe/unsubscribe",
                    isRequired: true,
                    defaultValue: "DICOM_STUDIO",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["subscribe", "unsubscribe"])
                ),
                // --workitem-uid also visible for change-state (used in command preview)
                // Note: change-state uses --update <uid> from update-uid parameter, not --workitem-uid
                CLIParameterDefinition(
                    id: "create-label", flag: "--label", displayName: "Procedure Step Label",
                    parameterType: .textField, placeholder: "e.g. CT Scan Chest",
                    helpText: "Human-readable label for the procedure step (0074,1204)",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. Doe^Jane",
                    helpText: "Patient name in DICOM format Last^First (0010,0010)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. PAT001",
                    helpText: "Patient identifier (0010,0020)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-birth-date", flag: "--patient-birth-date", displayName: "Patient Birth Date",
                    parameterType: .textField, placeholder: "e.g. 19800115",
                    helpText: "Patient birth date in YYYYMMDD format (0010,0030)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-patient-sex", flag: "--patient-sex", displayName: "Patient Sex",
                    parameterType: .enumPicker, placeholder: "Unspecified",
                    helpText: "Patient's Sex (0010,0040): M, F, O (PS3.3 Table C.7-1)",
                    isAdvanced: true,
                    allowedValues: ["", "M", "F", "O"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                // Scheduled Procedure Step Priority (0074,1200) Enumerated Values, PS3.3 2026a
                // Table C.30.2-1: HIGH, MEDIUM, LOW. The CLI still accepts STAT (sent as HIGH).
                CLIParameterDefinition(
                    id: "create-priority", flag: "--priority", displayName: "Priority",
                    parameterType: .enumPicker, placeholder: "MEDIUM",
                    helpText: "Scheduled Procedure Step Priority (0074,1200): HIGH, MEDIUM, LOW (PS3.3 Table C.30.2-1; default: MEDIUM). STAT is accepted and sent as HIGH",
                    defaultValue: "MEDIUM",
                    allowedValues: ["HIGH", "MEDIUM", "LOW"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-scheduled-start", flag: "--scheduled-start", displayName: "Scheduled Start",
                    parameterType: .textField, placeholder: "e.g. 2026-03-20T14:00:00",
                    helpText: "Scheduled procedure step start date/time in ISO 8601 format",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-expected-completion", flag: "--expected-completion", displayName: "Expected Completion",
                    parameterType: .textField, placeholder: "e.g. 2026-03-20T15:00:00",
                    helpText: "Expected completion date/time in ISO 8601 format",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.840.113619...",
                    helpText: "Study Instance UID for the workitem",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-accession", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "e.g. ACC12345",
                    helpText: "Accession number (0008,0050)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-referring-physician", flag: "--referring-physician", displayName: "Referring Physician",
                    parameterType: .textField, placeholder: "e.g. Smith^John",
                    helpText: "Referring physician name (0008,0090)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-procedure-id", flag: "--procedure-id", displayName: "Procedure ID",
                    parameterType: .textField, placeholder: "e.g. RP001",
                    helpText: "Requested procedure ID (0040,1001)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-step-id", flag: "--step-id", displayName: "Step ID",
                    parameterType: .textField, placeholder: "e.g. SPS001",
                    helpText: "Scheduled procedure step ID (0040,0009)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-worklist-label", flag: "--worklist-label", displayName: "Worklist Label",
                    parameterType: .textField, placeholder: "e.g. WL_CT",
                    helpText: "Worklist label (0074,1202)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-station-name", flag: "--station-name", displayName: "Station Name",
                    parameterType: .textField, placeholder: "e.g. CT_SCANNER_1",
                    helpText: "Scheduled station name for the procedure",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-performer", flag: "--performer-name", displayName: "Performer Name",
                    parameterType: .textField, placeholder: "e.g. Tech^Mary",
                    helpText: "Scheduled human performer name",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-performer-organization", flag: "--performer-organization", displayName: "Performer Organization",
                    parameterType: .textField, placeholder: "e.g. Radiology Dept",
                    helpText: "Scheduled human performer organization",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-comments", flag: "--comments", displayName: "Comments",
                    parameterType: .textField, placeholder: "e.g. Patient prepped for contrast",
                    helpText: "Comments on the scheduled procedure step (0040,0400)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                CLIParameterDefinition(
                    id: "create-admission-id", flag: "--admission-id", displayName: "Admission ID",
                    parameterType: .textField, placeholder: "e.g. ADM001",
                    helpText: "Admission ID (0038,0010)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
                ),
                // Change-state parameters. Procedure Step State (0074,1000) spelled as PS3.3
                // 2026a Table C.30.1-1 does; a Change State request may carry only IN PROGRESS,
                // COMPLETED or CANCELED (PS3.18 11.7.1.4) — SCHEDULED is refused by the CLI
                // (PS3.4 Table CC.1.1-2, C303H; P-WADO-UPS-STATE) and is not offered.
                CLIParameterDefinition(
                    id: "state", flag: "--state", displayName: "Target State",
                    parameterType: .enumPicker, placeholder: "IN PROGRESS",
                    helpText: "New Procedure Step State for --change-state: IN PROGRESS, COMPLETED, CANCELED (PS3.18 11.7.1.4); IN_PROGRESS is accepted for IN PROGRESS",
                    defaultValue: "IN PROGRESS",
                    allowedValues: ["IN PROGRESS", "COMPLETED", "CANCELED"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["change-state"])
                ),
                CLIParameterDefinition(
                    id: "change-state-aet", flag: "--aet", displayName: "Requesting AE",
                    parameterType: .textField, placeholder: "e.g. DCM4CHEE",
                    helpText: "Requesting AE Title — required by some servers (e.g. dcm4chee-arc) as the last path segment",
                    isRequired: true,
                    defaultValue: "DCM4CHEE",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["change-state"])
                ),
                CLIParameterDefinition(
                    id: "transaction-uid", flag: "--transaction-uid", displayName: "Transaction UID",
                    parameterType: .textField, placeholder: "e.g. 1.2.826.0.1.3680043...",
                    helpText: "Transaction UID (0008,1195) for state changes (required for COMPLETED/CANCELED; auto-generated for IN PROGRESS, PS3.18 11.7.1.4)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["change-state"])
                ),
                // Search-specific parameters: the four Procedure Step State (0074,1000)
                // Enumerated Values of PS3.3 Table C.30.1-1 as matching key.
                CLIParameterDefinition(
                    id: "filter-state", flag: "--filter-state", displayName: "State Filter",
                    parameterType: .enumPicker, placeholder: "Any",
                    helpText: "Filter by Procedure Step State (0074,1000): SCHEDULED, IN PROGRESS, COMPLETED, CANCELED (PS3.3 Table C.30.1-1); IN_PROGRESS is accepted",
                    allowedValues: ["", "SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["search"])
                ),
                CLIParameterDefinition(
                    id: "scheduled-station", flag: "--scheduled-station", displayName: "Scheduled Station",
                    parameterType: .textField, placeholder: "e.g. CT_SCANNER_1",
                    helpText: "Filter by Scheduled Station AE",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["search"])
                ),
                // ----- DICOMweb Auth Parameters -----
                CLIParameterDefinition(
                    id: "auth", flag: "--auth", displayName: "Authentication",
                    parameterType: .enumPicker, placeholder: "none",
                    helpText: "Authentication method for the DICOMweb server",
                    isInternal: true,
                    defaultValue: "none",
                    allowedValues: ["none", "basic", "bearer"]
                ),
                // #45: the CLI's `--token` is Bearer-only, so the flag is emitted
                // (and the field shown) ONLY when auth=bearer. Basic auth runs
                // in-app through the internal username/password fields below —
                // it has no CLI-representable form.
                CLIParameterDefinition(
                    id: "token", flag: "--token", displayName: "Bearer Token",
                    parameterType: .secureField, placeholder: "Bearer token",
                    helpText: "OAuth2 bearer token for authentication",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["bearer"])
                ),
                CLIParameterDefinition(
                    id: "username", flag: "--username", displayName: "Username",
                    parameterType: .textField, placeholder: "e.g. admin",
                    helpText: "Username for basic authentication",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                CLIParameterDefinition(
                    id: "password", flag: "", displayName: "Password",
                    parameterType: .secureField, placeholder: "Password",
                    helpText: "Password for basic authentication (in-app only — the dicom-wado CLI has no basic-auth flags)",
                    isInternal: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "auth", values: ["basic"])
                ),
                // dicom-json is the PS3.18 2026a F.2 DICOM JSON Model each workitem came as
                // (P-QUERY-JSON); json / csv are camelCase tool summaries (UPSResultFormatter).
                CLIParameterDefinition(
                    id: "output-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "table",
                    helpText: "Output format: table, json, csv, dicom-json (default: table). dicom-json is the PS3.18 F.2 DICOM JSON Model; json is a tool summary (camelCase keys)",
                    defaultValue: "table",
                    allowedValues: ["table", "json", "csv", "dicom-json"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["search", "get"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose output"
                ),
            ]
        case "dicom-convert":
            // Help texts are dicom-convert's (Sources/dicom-convert/DICOMConvert.swift). The
            // --transfer-syntax picker is the shared DICOMConverter catalog's CamelCase tokens
            // (DICOMConverter.cliTokens: the CLI's --help listing, incl. the …Reversible names of
            // P-CONVERT-TS-KEYWORDS); every other spelling the CLI accepts (kebab alias, UID, PS3.6
            // Table A-1 keyword) is canonicalised to its token when typed (WorkshopConvertPicker).
            // Frames are selected by Frame number from 1 (--frame-number, PS3.3 Table 10-3); --frame is
            // the deprecated 0-based index (P-CONVERT-FRAME).
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File/Directory",
                    parameterType: .filePath, placeholder: "Path to DICOM file or directory",
                    helpText: "Path to DICOM file or directory",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Path",
                    parameterType: .outputPath, placeholder: "Output file or directory path",
                    helpText: "Output file or directory path",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "dicom",
                    helpText: "Output format for image export: png, jpeg, tiff, dicom (default: dicom)",
                    defaultValue: "dicom",
                    allowedValues: ["dicom", "png", "jpeg", "tiff"]
                ),
                CLIParameterDefinition(
                    id: "transfer-syntax", flag: "--transfer-syntax", displayName: "Transfer Syntax",
                    parameterType: .enumPicker, placeholder: "Target transfer syntax",
                    helpText: DICOMConverter.transferSyntaxOptionHelpWithKeywords,
                    allowedValues: [""] + DICOMConverter.cliTokens,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["dicom"])
                ),
                CLIParameterDefinition(
                    id: "quality", flag: "--quality", displayName: "JPEG Quality",
                    parameterType: .integerField, placeholder: "90",
                    helpText: "JPEG quality (1-100, default: 90)",
                    defaultValue: "90", minValue: 1, maxValue: 100,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["jpeg"])
                ),
                CLIParameterDefinition(
                    id: "window-center", flag: "--window-center", displayName: "Window Center",
                    parameterType: .textField, placeholder: "e.g. 40",
                    helpText: "Window center value (Window Center (0028,1050))",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["png", "jpeg", "tiff"])
                ),
                CLIParameterDefinition(
                    id: "window-width", flag: "--window-width", displayName: "Window Width",
                    parameterType: .textField, placeholder: "e.g. 400",
                    helpText: "Window width value (Window Width (0028,1051), at least 1)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["png", "jpeg", "tiff"])
                ),
                CLIParameterDefinition(
                    id: "apply-window", flag: "--apply-window", displayName: "Apply Window/Level",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Apply window/level during export",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["png", "jpeg", "tiff"])
                ),
                CLIParameterDefinition(
                    id: "frame-number", flag: "--frame-number", displayName: "Frame Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Frame to export, numbered from 1 (PS3.3 Table 10-3: the first Frame is Frame number 1; default 1)",
                    minValue: 1, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["png", "jpeg", "tiff"])
                ),
                CLIParameterDefinition(
                    id: "frame", flag: "--frame", displayName: "Frame (deprecated)",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "deprecated: 0-based index; use --frame-number",
                    isAdvanced: true,
                    minValue: 0, maxValue: 99998,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "format", values: ["png", "jpeg", "tiff"])
                ),
                CLIParameterDefinition(
                    id: "strip-private", flag: "--strip-private", displayName: "Strip Private Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Strip private tags during conversion",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Process directories recursively",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "validate", flag: "--validate", displayName: "Validate Output",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Validate output after conversion",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force Parse",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Force parsing of files without DICM prefix",
                    isAdvanced: true
                ),
            ]
        case "dicom-validate":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File/Directory",
                    parameterType: .filePath, placeholder: "Path to DICOM file or directory",
                    helpText: "DICOM file or directory to validate",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "level", flag: "--level", displayName: "Validation Level",
                    parameterType: .enumPicker, placeholder: "3",
                    helpText: "Validation level (1-5): 1=File Meta Information (PS3.10 Table 7.1-1), 2=VR and VM against PS3.6 Table 6-1, value length, character repertoire and DA/TM/UI/AS/DS/IS value forms (PS3.5 Table 6.2-1, 6.2.1, 9.1), 3=IOD Type 1/1C/2/2C (PS3.3), 4=Best practices, 5=J2K codestream",
                    defaultValue: "3",
                    allowedValues: ["1", "2", "3", "4", "5"]
                ),
                CLIParameterDefinition(
                    id: "iod", flag: "--iod", displayName: "IOD Override",
                    parameterType: .textField, placeholder: "e.g. CTImageStorage or 1.2.840.10008.5.1.4.1.1.2",
                    helpText: "IOD to validate against: SOP Class keyword or UID of PS3.6 Table A-1 (e.g. CTImageStorage, MRImageStorage, ComputedRadiographyImageStorage, UltrasoundImageStorage, SecondaryCaptureImageStorage, GrayscaleSoftcopyPresentationStateStorage, PseudoColorSoftcopyPresentationStateStorage, an SR or Key Object Selection keyword); short names CT, MR, CR, US, SC, GSPS, SR, KOS also accepted; default: from SOP Class UID (0008,0016)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "detailed", flag: "--detailed", displayName: "Detailed",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show per-issue detail (tag, message, severity) in the report"
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Process all DICOM files in a directory and its sub-directories"
                ),
                CLIParameterDefinition(
                    id: "strict", flag: "--strict", displayName: "Strict Mode",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Exit with code 2 when warnings (not just errors) are found"
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "text",
                    helpText: "Output format for the validation report",
                    defaultValue: "text",
                    allowedValues: ["text", "json"]
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Save Report To",
                    parameterType: .outputPath, placeholder: "Optional output file path",
                    helpText: "Write the validation report to a file instead of (or in addition to) the console",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force Parse",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Attempt to parse files that lack the standard DICM preamble",
                    isAdvanced: true
                ),
            ]
        case "dicom-anon":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File/Directory",
                    parameterType: .filePath, placeholder: "Path to DICOM file or directory",
                    helpText: "DICOM file or directory to anonymize",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Path",
                    parameterType: .outputPath, placeholder: "Output file or directory path",
                    helpText: "Destination file or directory for anonymized output"
                ),
                CLIParameterDefinition(
                    id: "profile", flag: "--profile", displayName: "Profile",
                    parameterType: .enumPicker, placeholder: "legacy-basic",
                    helpText: "Fixed attribute lists, deprecated in dicom-anon and not PS3.15 Annex E: legacy-basic removes or replaces 14 direct identifiers; legacy-clinical-trial also removes dates; legacy-research removes Patient's Name, ID and Birth Date only. The CLI default ps315 (PS3.15 Basic Application Level Confidentiality Profile, Table E.1-1) is not yet offered here",
                    defaultValue: "legacy-basic",
                    allowedValues: ["legacy-basic", "legacy-clinical-trial", "legacy-research"]
                ),
                // PS3.15 2026a Annex E Options (E.3; the 12 Option columns of Table E.1-1, codes of
                // PS3.16 CID 7050) and the pixel-cleaning options, as dicom-anon declares them
                // (help texts are the CLI's, checked by diff_studio_g1). They act only on
                // --profile ps315, which the picker does not offer yet (P-STUDIO-ANON-PS315): the
                // executor refuses a set flag with the CLI's "apply only to --profile ps315" text.
                CLIParameterDefinition(
                    id: "retain-dates", flag: "--retain-dates", displayName: "Retain Dates (deprecated)",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Deprecated: use --retain-full-dates or --retain-modified-dates. PS3.15 Retain Longitudinal Temporal Information With Full Dates Option; with --shift-dates, ... With Modified Dates Option (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-full-dates", flag: "--retain-full-dates", displayName: "Retain Full Dates",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Longitudinal Temporal Information With Full Dates Option: dates and times kept (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-modified-dates", flag: "--retain-modified-dates", displayName: "Retain Modified Dates",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Longitudinal Temporal Information With Modified Dates Option: dates shifted by --shift-dates, which it requires; times kept (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-characteristics", flag: "--retain-characteristics", displayName: "Retain Patient Characteristics",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Patient Characteristics Option (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-device", flag: "--retain-device", displayName: "Retain Device Identity",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Device Identity Option (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-institution", flag: "--retain-institution", displayName: "Retain Institution Identity",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Institution Identity Option (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-uids", flag: "--retain-uids", displayName: "Retain UIDs",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain UIDs Option: UIDs kept instead of replaced (U) (--profile ps315)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "clean-descriptors", flag: "--clean-descriptors", displayName: "Clean Descriptors",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Clean Descriptors Option (--profile ps315): descriptor attributes are kept with the names, identifiers and dates the profile removes elsewhere taken out of their text (E.3.5); review free text before release",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "retain-safe-private", flag: "--retain-safe-private", displayName: "Retain Safe Private",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Retain Safe Private Option (--profile ps315): keep the private attributes PS3.15 Table E.3.10-1 lists for their Private Creator, or that the file declares safe in Private Data Element Characteristics Sequence (0008,0300); other private attributes are removed (E.3.10)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "clean-graphics", flag: "--clean-graphics", displayName: "Clean Graphics",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Clean Graphics Option (--profile ps315): keep Graphic Annotation Sequence (0070,0001) with the names, identifiers and dates the profile removes taken out of its text (E.3.3); overlays are still removed",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "clean-structured-content", flag: "--clean-structured-content", displayName: "Clean Structured Content",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Clean Structured Content Option (--profile ps315): keep Content Sequence (0040,A730) values (without it, Basic D: every Text Value and numeric value is a dummy), Acquisition Context Sequence and Specimen Preparation Sequence; each Content Item gets the action PS3.15 Table E.3.4-1 gives its Concept Name (removed, dummy, kept or cleaned) and the text kept is cleaned (E.3.4)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "clean-recognizable-visual-features", flag: "--clean-recognizable-visual-features", displayName: "Clean Recognizable Visual Features",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15 Clean Recognizable Visual Features Option (--profile ps315): blank the --redact-region areas (required; not detected automatically) on every frame, set Recognizable Visual Features (0028,0302) = NO and record code 113102 (E.3.2)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "clean-pixel-data", flag: "--clean-pixel-data", displayName: "Clean Pixel Data",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "PS3.15: Clean Pixel Data — blank burned-in identifiers out of the image itself. Chooses the region automatically (declared clinical region, else device template) and REFUSES rather than guessing when it cannot. Records code 113101 and sets Burned In Annotation = NO only when pixels were actually blanked.",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "redact-region", flag: "--redact-region", displayName: "Redact Region(s)",
                    parameterType: .textField, placeholder: "e.g. 0,0,200,50; 10,400,300,40",
                    helpText: "Region to blank as x,y,width,height (repeatable). Implies --clean-pixel-data and overrides automatic region selection; with --clean-recognizable-visual-features the regions are the recognizable features to blank, and imply nothing else. Separate regions with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "redact-fill", flag: "--redact-fill", displayName: "Redact Fill Value",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Fill value for blanked pixels (default: 0 = black)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "shift-dates", flag: "--shift-dates", displayName: "Shift Dates (days)",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Number of days to shift dates (preserves intervals). With --profile ps315 this is the Modified Dates Option and needs --retain-modified-dates",
                    isAdvanced: true,
                    minValue: -36500, maxValue: 36500
                ),
                CLIParameterDefinition(
                    id: "regenerate-uids", flag: "--regenerate-uids", displayName: "Regenerate UIDs",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Regenerate Study, Series and SOP Instance UIDs (legacy-* profiles). --profile ps315 always replaces UIDs (Table E.1-1 action U) unless --retain-uids",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "remove", flag: "--remove", displayName: "Remove Tag(s)",
                    parameterType: .textField, placeholder: "e.g. 0010,0040; PatientName",
                    helpText: "Tags to remove (format: 0010,0010 or a PS3.6 keyword). Separate with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "replace", flag: "--replace", displayName: "Replace Tag(s)",
                    parameterType: .textField, placeholder: "e.g. 0010,0010=ANON; 0010,0020=ID001",
                    helpText: "Tags to replace (format: 0010,0010=VALUE or KEYWORD=VALUE). Separate pairs with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "keep", flag: "--keep", displayName: "Keep Tag(s)",
                    parameterType: .textField, placeholder: "e.g. 0008,0060; Modality",
                    helpText: "Tags to keep (preserve from anonymization; legacy-* profiles only). Separate with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Process directories recursively"
                ),
                CLIParameterDefinition(
                    id: "dry-run", flag: "--dry-run", displayName: "Dry Run",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Preview changes without modifying files"
                ),
                CLIParameterDefinition(
                    id: "backup", flag: "--backup", displayName: "Backup Originals",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Create backup of original files",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "audit-log", flag: "--audit-log", displayName: "Audit Log Path",
                    parameterType: .outputPath, placeholder: "Optional audit log file path",
                    helpText: "Path to audit log file",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force Parse",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Force parsing of files without DICM prefix",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "allow-burned-in-phi", flag: "--allow-burned-in-phi", displayName: "Allow Burned-in PHI",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Proceed even when the pixels may still carry PHI (Burned In Annotation = YES, or overlay planes present) (--profile ps315). Without this, such files are refused unwritten, because without --clean-pixel-data only the data set is de-identified.",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output"
                ),
            ]
        case "dicom-info":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File",
                    parameterType: .filePath, placeholder: "Path to DICOM file",
                    helpText: "DICOM file to inspect",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "text",
                    helpText: "Output format: text (default), json, or csv",
                    defaultValue: "text",
                    allowedValues: ["text", "json", "csv"]
                ),
                CLIParameterDefinition(
                    id: "tag", flag: "--tag", displayName: "Filter Tag(s)",
                    parameterType: .textField, placeholder: "e.g. Patient's Name; 0008,0060",
                    helpText: "Show only these tags (name or number). Separate with “ ; ”. Default: all tags.",
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "show-private", flag: "--show-private", displayName: "Show Private Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Include odd-group private tags in the output"
                ),
                CLIParameterDefinition(
                    id: "statistics", flag: "--statistics", displayName: "File Statistics",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show file-level statistics (transfer syntax, modality, SOP class)"
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force Parse",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Attempt to parse files that lack the standard DICM preamble",
                    isAdvanced: true
                ),
            ]
        case "dicom-dump":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File",
                    parameterType: .filePath, placeholder: "Path to DICOM file",
                    helpText: "DICOM file to hex-dump",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "tag", flag: "--tag", displayName: "Dump Tag",
                    parameterType: .textField, placeholder: "e.g. 7FE0,0010 or PixelData",
                    helpText: "Dump only the value bytes of the specified tag (format: 0010,0010 or PS3.6 keyword, e.g. PatientName)"
                ),
                CLIParameterDefinition(
                    id: "offset", flag: "--offset", displayName: "Start Offset",
                    parameterType: .textField, placeholder: "e.g. 0x1000 or 4096",
                    helpText: "Start byte offset into the file (hex or decimal)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "length", flag: "--length", displayName: "Length (bytes)",
                    parameterType: .integerField, placeholder: "256",
                    helpText: "Number of bytes to dump from the start offset",
                    isAdvanced: true,
                    minValue: 1, maxValue: 10_000_000
                ),
                CLIParameterDefinition(
                    id: "bytes-per-line", flag: "--bytes-per-line", displayName: "Bytes / Line",
                    parameterType: .enumPicker, placeholder: "16",
                    helpText: "Number of hex bytes shown per output line",
                    isAdvanced: true,
                    defaultValue: "16",
                    allowedValues: ["8", "16", "32"]
                ),
                CLIParameterDefinition(
                    id: "highlight", flag: "--highlight", displayName: "Highlight Tag",
                    parameterType: .textField, placeholder: "e.g. 0010,0010 or PatientName",
                    helpText: "Highlight the rows of the specified tag (format: 0010,0010 or PS3.6 keyword)",
                    isAdvanced: true
                ),
                // Default off, as dicom-dump's `--no-color` (the Workshop form mirrors the
                // CLI surface). The in-app console cannot render ANSI colour, so the
                // executor strips the escape sequences from what it shows; the pasted
                // command and the Compare-CLI diff (which strips ANSI on both sides) are
                // unaffected either way.
                CLIParameterDefinition(
                    id: "no-color", flag: "--no-color", displayName: "No Color",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Disable color output (the in-app console never shows ANSI colour; this flag only changes the pasted command and the CLI's terminal output)",
                    defaultValue: "false"
                ),
                CLIParameterDefinition(
                    id: "annotate", flag: "--annotate", displayName: "Annotate Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Append tag name annotations at tag-boundary rows"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show VR and length details alongside each tag boundary"
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force Parse",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Attempt to parse files that lack the standard DICM preamble",
                    isAdvanced: true
                ),
            ]
        case "dicom-tags":
            return [
                // Not `isRequired`: dicom-tags takes no <input> with --list-modalities; the
                // executor refuses a missing input otherwise with the CLI's own message.
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File",
                    parameterType: .filePath, placeholder: "Path to DICOM file",
                    helpText: "Input DICOM file path (omit with --list-modalities)"
                ),
                CLIParameterDefinition(
                    id: "list-modalities", flag: "--list-modalities", displayName: "List Modalities",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Print every DICOM Modality (0008,0060) defined term (PS3.3 C.7.3.1.1.1) and exit; no input file is read"
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output File",
                    parameterType: .outputPath, placeholder: "Output DICOM file path (overwrites input if omitted)",
                    helpText: "Write modified DICOM to this path instead of overwriting the input file"
                ),
                CLIParameterDefinition(
                    id: "set", flag: "--set", displayName: "Set Tag(s)",
                    parameterType: .textField, placeholder: "e.g. PatientName=DOE^JOHN; 0008,0090=DR.SMITH",
                    helpText: "Keyword=Value or GGGG,EEEE=Value (keyword in PS3.6 case). Writes the PS3.6 dictionary VR and refuses a value outside the PS3.5 Table 6.2-1 limits of that VR (length, characters, numeric range); US/SS/UL/SL/FL/FD are decimal numbers, values separated by a backslash; group 0002 cannot be edited (PS3.10 7.1). Separate with “ ; ”.",
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "delete", flag: "--delete", displayName: "Delete Tag(s)",
                    parameterType: .textField, placeholder: "e.g. PatientBirthDate; 0010,0020",
                    helpText: "Tags to remove (name or GGGG,EEEE). Separate with “ ; ”.",
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "delete-private", flag: "--delete-private", displayName: "Delete Private Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Remove all private tags (odd-group elements)"
                ),
                CLIParameterDefinition(
                    id: "copy-from", flag: "--copy-from", displayName: "Copy From File",
                    parameterType: .filePath, placeholder: "Source DICOM file path",
                    helpText: "Copy tags from this DICOM file into the input file",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "tags", flag: "--tags", displayName: "Tags to Copy",
                    parameterType: .textField, placeholder: "e.g. PatientName,PatientID",
                    helpText: "Comma-separated list of tags to copy from --copy-from file (default: all)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show each tag operation as it is applied"
                ),
                CLIParameterDefinition(
                    id: "dry-run", flag: "--dry-run", displayName: "Dry Run",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Preview all changes without writing any files"
                ),
            ]
        case "dicom-diff":
            return [
                CLIParameterDefinition(
                    id: "file1", flag: "", displayName: "File 1",
                    parameterType: .filePath, placeholder: "First DICOM file to compare",
                    helpText: "First DICOM file (reference)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "file2", flag: "", displayName: "File 2",
                    parameterType: .filePath, placeholder: "Second DICOM file to compare",
                    helpText: "Second DICOM file (target)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "text",
                    helpText: "Output format: text (default), json, or summary",
                    defaultValue: "text",
                    allowedValues: ["text", "json", "summary"]
                ),
                CLIParameterDefinition(
                    id: "ignore-tag", flag: "--ignore-tag", displayName: "Ignore Tag(s)",
                    parameterType: .textField, placeholder: "e.g. SOPInstanceUID; (0008,0012)",
                    helpText: "Tags to skip: (gggg,eeee), gggg,eeee, ggggeeee or a PS3.6 keyword. Separate with “ ; ”. Exit status: 0 identical, 1 different, 2 a file is missing or cannot be read as DICOM.",
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "ignore-private", flag: "--ignore-private", displayName: "Ignore Private Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Ignore private data elements (odd group number, PS3.5 7.1), also inside sequence items"
                ),
                CLIParameterDefinition(
                    id: "compare-pixels", flag: "--compare-pixels", displayName: "Compare Pixels",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Compare Pixel Data (7FE0,0010) sample by sample (decoded; PS3.5 8.1.1) instead of as one element"
                ),
                CLIParameterDefinition(
                    id: "tolerance", flag: "--tolerance", displayName: "Pixel Tolerance",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Largest Pixel Sample Value difference (PS3.5 8.1.1) in Pixel Data (7FE0,0010) still treated as identical (default: 0)",
                    isAdvanced: true,
                    defaultValue: "0", minValue: 0, maxValue: 65535
                ),
                CLIParameterDefinition(
                    id: "quick", flag: "--quick", displayName: "Quick Mode",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Metadata-only comparison; skips pixel data even if --compare-pixels is set"
                ),
                CLIParameterDefinition(
                    id: "show-identical", flag: "--show-identical", displayName: "Show Identical Tags",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "List tags whose values are identical across both files",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output with detailed tag information"
                ),
            ]
        case "dicom-split":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File",
                    parameterType: .filePath, placeholder: "Path to multi-frame DICOM file",
                    helpText: "Multi-frame DICOM file (or directory with --recursive) to split into per-frame files",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "Output directory",
                    helpText: "Directory to write the split frames into"
                ),
                // P-SPLIT-1: frames are selected by Frame number from 1 (PS3.3 C.7.6.16.1.2
                // "Frames are implicitly numbered starting from 1"); the 0-based --frames is
                // deprecated (D154) and the executor prints SplitConsole.framesDeprecatedLine.
                CLIParameterDefinition(
                    id: "frame-numbers", flag: "--frame-numbers", displayName: "Frame Numbers",
                    parameterType: .textField, placeholder: "e.g. 1,3,5-10",
                    helpText: "Frames to extract by Frame number, numbered from 1 (PS3.3 C.7.6.16.1.2), e.g. '1,3,5-10' (default: all)"
                ),
                CLIParameterDefinition(
                    id: "frames", flag: "--frames", displayName: "Frames (deprecated)",
                    parameterType: .textField, placeholder: "e.g. 0-4,7,9",
                    helpText: "deprecated: 0-based index; use --frame-numbers",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "dicom",
                    helpText: "Output format for each extracted frame",
                    defaultValue: "dicom", allowedValues: ["dicom", "png", "jpeg", "tiff"]
                ),
                CLIParameterDefinition(
                    id: "apply-window", flag: "--apply-window", displayName: "Apply Window",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Apply window center/width when rendering to image formats"
                ),
                CLIParameterDefinition(
                    id: "window-center", flag: "--window-center", displayName: "Window Center",
                    parameterType: .textField, placeholder: "e.g. 40",
                    helpText: "Window center used for image rendering", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "window-width", flag: "--window-width", displayName: "Window Width",
                    parameterType: .textField, placeholder: "e.g. 400",
                    helpText: "Window width used for image rendering", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "pattern", flag: "--pattern", displayName: "Filename Pattern",
                    parameterType: .textField, placeholder: "e.g. frame_{number:04d}_{modality}.dcm",
                    helpText: "Output filename pattern ({number}, {number:04d}, {instance}, {stack}, {modality}, {series})", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "target", flag: "--target", displayName: "Target SOP Class",
                    parameterType: .enumPicker, placeholder: "auto",
                    helpText: "auto: classic single-frame class when one exists (Enhanced CT → CT Image); same: keep the source class; classic: require a classic counterpart",
                    defaultValue: "auto", allowedValues: SplitTargetPolicy.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "pixel-handling", flag: "--pixel-handling", displayName: "Compressed Pixels",
                    parameterType: .enumPicker, placeholder: "preserve",
                    helpText: "preserve: keep the transfer syntax frame by frame; decode: write native Explicit VR LE",
                    defaultValue: "preserve", allowedValues: MultiframePixelHandling.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "private-groups", flag: "--private-groups", displayName: "Private Functional Groups",
                    parameterType: .enumPicker, placeholder: "flatten",
                    helpText: "What to do with vendor functional groups", isAdvanced: true,
                    defaultValue: "flatten", allowedValues: PrivateFunctionalGroupPolicy.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "instance-number", flag: "--instance-number", displayName: "Instance Numbering",
                    parameterType: .enumPicker, placeholder: "frame",
                    helpText: "frame: 1-based frame number; instack: In-Stack Position Number; original: unchanged", isAdvanced: true,
                    defaultValue: "frame", allowedValues: SplitInstanceNumbering.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "split-by", flag: "--split-by", displayName: "Split Series By",
                    parameterType: .enumPicker, placeholder: "none",
                    helpText: "Write one series per stack or temporal position", isAdvanced: true,
                    defaultValue: "none", allowedValues: SplitSeriesGrouping.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "new-series", flag: "--new-series", displayName: "New Series UID",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Mint a new Series Instance UID for the extracted frames", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "frames-per", flag: "--frames-per", displayName: "Frames per Part",
                    parameterType: .textField, placeholder: "e.g. 25",
                    helpText: "Write concatenation parts of N frames (SOP class kept; the only legal split for Segmentation / Parametric Map)", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "random-uids", flag: "--random-uids", displayName: "Random UIDs",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Generate random SOP/Series UIDs instead of deriving them from the source", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Recurse into directories"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output"
                ),
            ]
        case "dicom-merge":
            return [
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File(s)",
                    parameterType: .filePath, placeholder: "e.g. a.dcm; b.dcm or a directory",
                    helpText: "Input DICOM files or directories to merge. Separate with “ ; ” (use --recursive for directories).",
                    isRequired: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output File",
                    parameterType: .outputPath, placeholder: "Merged output DICOM path",
                    helpText: "Path to write the merged multi-frame DICOM"
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Merge Format",
                    parameterType: .enumPicker, placeholder: "standard",
                    helpText: "Merged object format (auto picks Legacy Converted / US / SC multi-frame from the source SOP class)",
                    defaultValue: "standard",
                    allowedValues: MergeFormat.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "pixel-handling", flag: "--pixel-handling", displayName: "Compressed Pixels",
                    parameterType: .enumPicker, placeholder: "preserve",
                    helpText: "preserve: keep the transfer syntax (one fragment per frame); decode: write native Explicit VR LE",
                    defaultValue: "preserve", allowedValues: MultiframePixelHandling.allCases.map { $0.rawValue }
                ),
                CLIParameterDefinition(
                    id: "make-stacks", flag: "--make-stacks", displayName: "Make Stacks",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Assign Stack ID (0020,9056) per Image Orientation (Patient) (0020,0037)", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "temporal-position", flag: "--temporal-position", displayName: "Temporal Positions",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Derive Temporal Position Index (0020,9128) from Trigger Time (0018,1060), Temporal Position Identifier (0020,0100) or Acquisition Time (0008,0032)", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "new-series", flag: "--new-series", displayName: "New Series UID",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Mint a new Series Instance UID (0020,000E) for the merged object", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "allow-any-source", flag: "--allow-any-source", displayName: "Allow Any Source",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Skip the source SOP Class check for Enhanced / Legacy Converted targets", isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "level", flag: "--level", displayName: "Merge Level",
                    parameterType: .enumPicker, placeholder: "file",
                    helpText: "Merge level: file (all inputs into one object), series (one per Series Instance UID), study (per Study Instance UID, then series) (default: file)",
                    defaultValue: "file", allowedValues: ["file", "series", "study"]
                ),
                // The picker is the shared MergeSortCriteria enum (dicom-merge's accepted
                // values), not a string list that can drift from it.
                CLIParameterDefinition(
                    id: "sort-by", flag: "--sort-by", displayName: "Sort By",
                    parameterType: .enumPicker, placeholder: "InstanceNumber",
                    helpText: "Sort frames by a PS3.6 keyword: InstanceNumber (0020,0013), ImagePositionPatient (0020,0032; distance along the slice normal), AcquisitionTime (0008,0032), or none (default: InstanceNumber)",
                    defaultValue: MergeSortCriteria.instanceNumber.rawValue,
                    allowedValues: ([.instanceNumber, .imagePositionPatient, .acquisitionTime, .none] as [MergeSortCriteria]).map(\.rawValue)
                ),
                CLIParameterDefinition(
                    id: "order", flag: "--order", displayName: "Sort Order",
                    parameterType: .enumPicker, placeholder: "ascending",
                    helpText: "Sort order",
                    defaultValue: "ascending", allowedValues: ["ascending", "descending"]
                ),
                CLIParameterDefinition(
                    id: "validate", flag: "--validate", displayName: "Validate",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Also require equal Study / Series Instance UID, Modality and Frame of Reference UID across inputs"
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Recurse into directories"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output"
                ),
            ]
        case "dicom-archive":
            return [
                CLIParameterDefinition(
                    id: "subcommand", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "list",
                    helpText: "Archive operation to perform",
                    defaultValue: "list",
                    allowedValues: ["init", "import", "query", "list", "export", "check", "stats"]
                ),
                CLIParameterDefinition(
                    id: "archive", flag: "--archive", displayName: "Archive Path",
                    parameterType: .filePath, placeholder: "Path to archive directory",
                    helpText: "Archive directory to operate on",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "subcommand",
                        values: ["import", "query", "list", "export", "check", "stats"])
                ),
                CLIParameterDefinition(
                    id: "path", flag: "--path", displayName: "New Archive Path",
                    parameterType: .outputPath, placeholder: "Directory to create the archive at",
                    helpText: "Location for the new archive",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["init"])
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Force",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Overwrite an existing archive",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["init"])
                ),
                CLIParameterDefinition(
                    id: "files", flag: "", displayName: "Files to Import",
                    parameterType: .filePath, placeholder: "e.g. path1; path2",
                    helpText: "Files/directories to import into the archive. Separate with “ ; ”.",
                    isRepeatable: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["import"])
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Recurse into directories when importing",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["import"])
                ),
                CLIParameterDefinition(
                    id: "skip-duplicates", flag: "--skip-duplicates", displayName: "Skip Duplicates",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Skip duplicate SOP Instance UIDs (0008,0018) without error",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["import"])
                ),
                // Query keys match like a DICOM C-FIND (PS3.4 C.2.2.2): the help texts are the
                // CLI's, so the Workshop and the terminal describe one matching behaviour.
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "e.g. DOE^JOHN or DOE*",
                    helpText: "Filter by Patient's Name (0010,0010); * and ? wild cards (PS3.4 C.2.2.2.4), case-insensitive",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "e.g. 12345",
                    helpText: "query: filter by Patient ID (0010,0020); * and ? wild cards, case-sensitive (PS3.4 C.2.2.2.4). export: exact match, no wild cards",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query", "export"])
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study UID",
                    parameterType: .textField, placeholder: "Study Instance UID",
                    helpText: "Filter / export by Study Instance UID (0020,000D); one UID or a backslash-separated list (PS3.4 C.2.2.2.2)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query", "export"])
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series-uid", displayName: "Series UID",
                    parameterType: .textField, placeholder: "Series Instance UID",
                    helpText: "Export by Series Instance UID (0020,000E); one UID or a backslash-separated list (PS3.4 C.2.2.2.2)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["export"])
                ),
                // Modality (0008,0060) is a Defined Term (PS3.3 C.7.3.1.1.1): an unknown code warns and
                // is sent as-is; --strict-modality rejects it. One shared validator across the tools.
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .textField, placeholder: "e.g. CT",
                    helpText: ModalityOptionValidator.helpText("filter")
                        + " A study matches when any of its series has it (Modalities in Study (0008,0061)).",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "study-date", flag: "--study-date", displayName: "Study Date",
                    parameterType: .textField, placeholder: "YYYYMMDD or YYYYMMDD-YYYYMMDD",
                    helpText: "Filter by Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD, YYYYMMDD- (PS3.4 C.2.2.2.5.1)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query"])
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Export Output",
                    parameterType: .outputPath, placeholder: "Export destination directory",
                    helpText: "Directory to export selected instances into",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["export"])
                ),
                CLIParameterDefinition(
                    id: "flatten", flag: "--flatten", displayName: "Flatten",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Flatten output to <SOP Instance UID>.dcm (no Patient ID / Study / Series subdirectories)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["export"])
                ),
                CLIParameterDefinition(
                    id: "show-instances", flag: "--show-instances", displayName: "Show Instances",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Include instance-level entries in the listing",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["list"])
                ),
                CLIParameterDefinition(
                    id: "verify-files", flag: "--verify-files", displayName: "Verify Files",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verify DICOM file readability",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["check"])
                ),
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "tree",
                    // No fixed default: the CLI default is per-subcommand (list→tree,
                    // query→table, stats→text). executeDicomArchive applies the right default
                    // when empty; a hardcoded "table" here forced list to render as a table.
                    helpText: "Output format. query: table, json, text (JSON adds ModalitiesInStudy, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances (PS3.6 keywords); modality, seriesCount, imageCount are deprecated); list: tree, table, json; stats: text, json",
                    defaultValue: "", allowedValues: ["table", "tree", "text", "json"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["query", "list", "stats"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["import", "export", "check"])
                ),
            ]
case "dicom-json":
    return [
        CLIParameterDefinition(
            id: "inputPath", flag: "", displayName: "Input File",
            parameterType: .filePath, placeholder: "Path to DICOM or JSON file",
            helpText: "Input file (DICOM or JSON). With --reverse this is a JSON file converted back to DICOM.",
            isRequired: true
        ),
        CLIParameterDefinition(
            id: "output", flag: "--output", displayName: "Output File",
            parameterType: .outputPath, placeholder: "Choose a location… (e.g. ExportedFile.json)",
            helpText: "Output file path. Defaults to the input name with .json (or .dcm when --reverse).",
            isRequired: false,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "reverse", flag: "--reverse", displayName: "Reverse (JSON -> DICOM)",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Convert from JSON back to a DICOM Part-10 file instead of DICOM -> JSON."
        ),
        // (--format and --stream were removed from the dicom-json CLI: both were
        // declared-but-never-read no-ops — the encoder always emits the DICOMweb
        // PS3.18 JSON model and no streaming path exists.)
        CLIParameterDefinition(
            id: "pretty", flag: "--pretty", displayName: "Pretty Print",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Pretty-print the JSON output with indentation.",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        // P-JSON-NO-SORT-KEYS (approved 2026-10-01): deprecated in the CLI; the executor
        // prints the same stderr note when it is used.
        CLIParameterDefinition(
            id: "no-sort-keys", flag: "--no-sort-keys", displayName: "Do Not Sort Keys (deprecated)",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Deprecated: don't order attribute objects by tag (the output then breaks the PS3.18 F.2.2 ascending order; will be removed)",
            isAdvanced: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        // PS3.18 F.2.5: an empty attribute "shall be preserved" as {"vr": ...}, so the
        // CLI default is on and `--no-include-empty` drops them (D114).
        CLIParameterDefinition(
            id: "include-empty", flag: "--include-empty", displayName: "Include Empty Values",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Keep attributes with an empty Value Field as {\"vr\": ...} (PS3.18 F.2.5). On by default; off emits --no-include-empty.",
            isAdvanced: true,
            negatedFlag: "--no-include-empty",
            defaultValue: "true",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        CLIParameterDefinition(
            id: "metadata-only", flag: "--metadata-only", displayName: "Metadata Only",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Metadata only (PS3.18 10.4.1.1.2): leave out every OB/OD/OF/OL/OV/OW/UN value at any depth (Pixel Data, Float Pixel Data, Encapsulated Document, Waveform, Overlay, LUTs); with --bulk-data-url each becomes a BulkDataURI instead",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        CLIParameterDefinition(
            id: "inline-threshold", flag: "--inline-threshold", displayName: "Inline Binary Threshold (bytes)",
            parameterType: .integerField, placeholder: "1024",
            helpText: "With --bulk-data-url: OB/OD/OF/OL/OV/OW/UN values longer than this many bytes become a BulkDataURI (0: all of them); without it every such value is InlineBinary (PS3.18 F.2.6, F.2.7)",
            isAdvanced: true,
            defaultValue: "1024", minValue: 0, maxValue: 1073741824,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        CLIParameterDefinition(
            id: "bulk-data-url", flag: "--bulk-data-url", displayName: "Bulk Data Base URL",
            parameterType: .textField, placeholder: "https://example.org/bulk",
            helpText: "Base URL for BulkDataURI values (PS3.18 F.2.6); the URI is <url>/<GGGGEEEE>, inside sequence items <url>/<SQ tag>/<item n>/<GGGGEEEE>",
            isAdvanced: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        CLIParameterDefinition(
            id: "filter-tag", flag: "--filter-tag", displayName: "Filter Tags",
            parameterType: .arrayField, placeholder: "e.g. PatientName; 0010,0010; 00100020",
            helpText: "Keep only these attributes: PS3.6 keyword, GGGG,EEEE or GGGGEEEE. Separate with “ ; ”.",
            isAdvanced: true,
            isRepeatable: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
        ),
        CLIParameterDefinition(
            id: "verbose", flag: "--verbose", displayName: "Verbose",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Print detailed progress and timing information."
        ),
    ]
        case "dicom-xml":
            return [
                CLIParameterDefinition(
                    id: "input", flag: "", displayName: "Input File",
                    parameterType: .filePath, placeholder: "Path to DICOM or XML file",
                    helpText: "Input file (DICOM when converting to XML, XML when --reverse is set)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output File",
                    parameterType: .outputPath, placeholder: "Choose a location… (e.g. ExportedFile.xml)",
                    helpText: "Output file path. Defaults to the input name with .xml (or .dcm when --reverse).",
                    defaultValue: ""
                ),
                CLIParameterDefinition(
                    id: "reverse", flag: "--reverse", displayName: "Reverse (XML → DICOM)",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Convert from XML back to a DICOM file instead of DICOM → XML"
                ),
                CLIParameterDefinition(
                    id: "pretty", flag: "--pretty", displayName: "Pretty Print",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Indent the generated XML for readability",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                // P-XML-NO-KEYWORDS (approved 2026-10-01): deprecated in the CLI; the
                // executor prints the same stderr note when it is used.
                CLIParameterDefinition(
                    id: "no-keywords", flag: "--no-keywords", displayName: "No Keywords (deprecated)",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Deprecated: don't write the keyword attribute (the output then breaks PS3.19 Table A.1.5-2, which requires it for PS3.6 elements; will be removed)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                // PS3.19 Table A.1.5-2: a DicomAttribute for each DICOM Attribute, an empty
                // Value Field has no Value elements; CLI default on, --no-include-empty drops them (D114).
                CLIParameterDefinition(
                    id: "include-empty", flag: "--include-empty", displayName: "Include Empty Values",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Keep attributes with an empty Value Field as a DicomAttribute without Value (PS3.19 Table A.1.5-2). On by default; off emits --no-include-empty.",
                    negatedFlag: "--no-include-empty",
                    defaultValue: "true",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                CLIParameterDefinition(
                    id: "inline-threshold", flag: "--inline-threshold", displayName: "Inline Binary Threshold",
                    parameterType: .integerField, placeholder: "1024",
                    helpText: "With --bulk-data-url: OB/OD/OF/OL/OV/OW/UN values longer than this many bytes become BulkData (0: all of them); without it every such value is InlineBinary (PS3.19 Table A.1.5-2)",
                    isAdvanced: true,
                    defaultValue: "1024", minValue: 0, maxValue: 1_000_000_000,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                CLIParameterDefinition(
                    id: "bulk-data-url", flag: "--bulk-data-url", displayName: "Bulk Data Base URL",
                    parameterType: .textField, placeholder: "https://example.org/bulkdata",
                    helpText: "Base URL for BulkData uri values, <url>/<GGGGEEEE>, inside items <url>/<SQ tag>/<item n>/<GGGGEEEE> (PS3.19 Table A.1.5-2 reserves uri for a WADO-RS Retrieve Metadata response)",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                CLIParameterDefinition(
                    id: "metadata-only", flag: "--metadata-only", displayName: "Metadata Only",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Metadata only (PS3.18 10.4.1.1.2): leave out every OB/OD/OF/OL/OV/OW/UN value at any depth (Pixel Data, Float Pixel Data, Encapsulated Document, Waveform, Overlay, LUTs); with --bulk-data-url each becomes BulkData instead",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                CLIParameterDefinition(
                    id: "filter-tag", flag: "--filter-tag", displayName: "Filter Tag(s)",
                    parameterType: .arrayField, placeholder: "e.g. PatientName; 0010,0010; 00100020",
                    helpText: "Keep only these attributes: PS3.6 keyword, GGGG,EEEE or GGGGEEEE. Separate with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "reverse", values: ["false", ""])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Print timing and element-count diagnostics"
                ),
            ]
case "dicom-uid":
    return [
        // Subcommand selector (positional, ArgumentParser subcommand)
        CLIParameterDefinition(
            id: "subcommand", flag: "", displayName: "Operation",
            parameterType: .subcommand, placeholder: "generate",
            helpText: "UID operation: generate new UIDs, validate UIDs for PS3.5 compliance, look up UIDs in the registry, or regenerate UIDs in a DICOM file",
            isRequired: true,
            defaultValue: "generate",
            allowedValues: ["generate", "validate", "lookup", "regenerate"]
        ),

        // ----- generate -----
        CLIParameterDefinition(
            id: "count", flag: "--count", displayName: "Count",
            parameterType: .integerField, placeholder: "1",
            helpText: "Number of UIDs to generate (1-1000, default: 1)",
            defaultValue: "1", minValue: 1, maxValue: 1000,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["generate"])
        ),
        CLIParameterDefinition(
            id: "type", flag: "--type", displayName: "UID Type",
            parameterType: .enumPicker, placeholder: "generic",
            helpText: "UID type: study, series, instance (alias sop), or generic (default); typed UIDs add arc .1, .2 or .3 under the root",
            defaultValue: "generic",
            allowedValues: ["generic", "study", "series", "instance", "sop"],
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["generate"])
        ),
        CLIParameterDefinition(
            id: "root", flag: "--root", displayName: "UID Root",
            parameterType: .textField, placeholder: UIDGenerator.defaultRoot,
            helpText: "UID root: your organisation's registered root (PS3.5 9.2.2), digits and single dots (9.1); default \(UIDGenerator.defaultRoot)",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["generate", "regenerate"])
        ),
        // PS3.5 B.2 UUID derived UIDs (2.25.<UUID as decimal>); the shared DICOMCore
        // UIDGenerator.uuidDerivedUID builds them.
        CLIParameterDefinition(
            id: "uuid", flag: "--uuid", displayName: "UUID Derived",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Generate UUID derived UIDs, 2.25.<UUID as decimal> (PS3.5 B.2); not combined with --root or --type",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["generate"])
        ),
        CLIParameterDefinition(
            id: "json", flag: "--json", displayName: "JSON Output",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Output as JSON. lookup: uid, name, uidType (PS3.6 Table A-1 UID Type) and type (deprecated: the former tool wording)",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["generate", "validate", "lookup"])
        ),

        // ----- validate -----
        CLIParameterDefinition(
            id: "uids", flag: "", displayName: "UIDs",
            parameterType: .arrayField, placeholder: "1.2.840.10008.1.1; 1.2.3.4",
            helpText: "One or more UIDs to validate. Separate with “ ; ”.",
            isRepeatable: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate"])
        ),
        CLIParameterDefinition(
            id: "file", flag: "--file", displayName: "DICOM File",
            parameterType: .filePath, placeholder: "Choose a location… (e.g. MG/MG_01_MG_Study3_Mammogram_0012-0001.dcm)",
            helpText: "Validate all UID (VR=UI) elements in a DICOM file",
            defaultValue: "",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate"])
        ),
        CLIParameterDefinition(
            id: "check-registry", flag: "--check-registry", displayName: "Check Registry",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Annotate valid UIDs with their DICOM registry name",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate"])
        ),

        // ----- lookup -----
        CLIParameterDefinition(
            id: "lookup-uid", flag: "", displayName: "UID",
            parameterType: .textField, placeholder: "1.2.840.10008.1.2.1",
            helpText: "A single UID to look up in the DICOM registry",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["lookup"])
        ),
        CLIParameterDefinition(
            id: "list-all", flag: "--list-all", displayName: "List All",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "List all known UIDs in the registry",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["lookup"])
        ),
        // One value per PS3.6 Table A-1 UID Type, from the shared engine list the CLI's
        // `lookup --type` accepts (UIDConsole.lookupTypeFilters); "" = no filter.
        CLIParameterDefinition(
            id: "lookup-type", flag: "--type", displayName: "Type Filter",
            parameterType: .enumPicker, placeholder: "Any",
            helpText: "Filter by PS3.6 Table A-1 UID Type: \(UIDConsole.lookupTypeFilters.map(\.value).joined(separator: ", "))",
            allowedValues: [""] + UIDConsole.lookupTypeFilters.map(\.value),
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["lookup"])
        ),
        CLIParameterDefinition(
            id: "search", flag: "--search", displayName: "Search",
            parameterType: .textField, placeholder: "CT",
            helpText: "Search registry UIDs by name or UID keyword",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["lookup"])
        ),

        // ----- regenerate -----
        CLIParameterDefinition(
            id: "inputPath", flag: "", displayName: "Input File(s)",
            parameterType: .filePath, placeholder: "Choose a location… (e.g. CT/CT_01_CT_Study1_0001-0001.dcm)",
            helpText: "Input DICOM file(s) whose instance UIDs will be regenerated. Separate multiple paths with “ ; ” — cross-file UID mapping is maintained across them (like the CLI's variadic <inputs>).",
            isRepeatable: true,
            defaultValue: "",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
        CLIParameterDefinition(
            id: "output", flag: "--output", displayName: "Output File/Directory",
            parameterType: .outputPath, placeholder: "Choose a location… (e.g. CT_New.dcm)",
            helpText: "Output file path (single input) or directory (multiple inputs). Defaults to overwriting the input(s).",
            defaultValue: "",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
        CLIParameterDefinition(
            id: "maintain-relationships", flag: "--maintain-relationships", displayName: "Maintain Relationships",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Maintain UID relationships across files (same old UID maps to same new UID)",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
        CLIParameterDefinition(
            id: "export-map", flag: "--export-map", displayName: "Export Mapping",
            parameterType: .outputPath, placeholder: "Choose a location… (e.g. uid_mapping.json)",
            helpText: "Export the old to new UID mapping to a JSON file",
            defaultValue: "",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
        CLIParameterDefinition(
            id: "dry-run", flag: "--dry-run", displayName: "Dry Run",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Show which UIDs would be regenerated without writing files",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
        CLIParameterDefinition(
            id: "verbose", flag: "--verbose", displayName: "Verbose",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Show each UID that was changed",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["regenerate"])
        ),
    ]
case "dicom-dcmdir":
            return [
                CLIParameterDefinition(
                    id: "subcommand", flag: "", displayName: "Subcommand",
                    parameterType: .subcommand, placeholder: "create",
                    helpText: "DICOMDIR operation: create a DICOMDIR from a folder, validate an existing one, dump its structure, or update (not yet implemented)",
                    isRequired: true,
                    defaultValue: "create",
                    allowedValues: ["create", "validate", "dump", "update"]
                ),

                // ----- create -----
                CLIParameterDefinition(
                    id: "inputDirectory", flag: "", displayName: "Input Directory",
                    parameterType: .filePath, placeholder: "folder containing DICOM files",
                    helpText: "Directory containing DICOM files to index (positional argument)",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output DICOMDIR",
                    parameterType: .outputPath, placeholder: "DICOMDIR",
                    helpText: "Output DICOMDIR path (default: DICOMDIR in input directory)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                // PS3.10 8.1 (0 to 16 characters) and 8.5 (A-Z, 0-9, _): the executor derives the
                // CLI's default and refuses any other value with exit 1 (P-DCMDIR-FSID, D132).
                CLIParameterDefinition(
                    id: "fileSetID", flag: "--file-set-id", displayName: "File-set ID",
                    parameterType: .textField, placeholder: "derived from directory name",
                    helpText: "File-set ID (0004,1130): up to 16 characters A-Z, 0-9, _ (PS3.10 8.1, 8.5); any other value is refused (exit 1); default: the directory name upper-cased, other characters as _, cut to 16",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                // D29: the picker offers only PS3.11 2026a Application Profile identifiers (Tables
                // A.1-1 to N.1-1), from the shared DICOMCore registry the CLI accepts. STD-GEN-DVD and
                // STD-GEN-USB are Annex H / J family headings, not identifiers; a saved preset that
                // still carries one is accepted and the executor prints the CLI's deprecation note.
                CLIParameterDefinition(
                    id: "profile", flag: "--profile", displayName: "Application Profile",
                    parameterType: .enumPicker, placeholder: "STD-GEN-CD",
                    helpText: "PS3.11 Application Profile identifier, e.g. STD-GEN-CD (default), STD-GEN-DVD-JPEG, STD-GEN-DVD-J2K, STD-GEN-USB-JPEG, STD-GEN-USB-J2K, STD-GEN-BD-JPEG (deprecated: STD-GEN-DVD, STD-GEN-USB, STD-GEN-SEC, STD-CTMR-XXXX, STD-US-XXXX are not PS3.11 identifiers; still accepted with a warning)",
                    defaultValue: "STD-GEN-CD",
                    allowedValues: DICOMDIRProfile.allStandard.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Recursively scan subdirectories for DICOM files (default: on)",
                    // The CLI flag is `@Flag(inversion: .prefixedNo)` with a `true`
                    // default — toggling OFF must emit `--no-recursive`.
                    negatedFlag: "--no-recursive",
                    defaultValue: "true",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "strict", flag: "--strict", displayName: "Strict",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Include only valid DICOM files",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "copyTo", flag: "--copy-to", displayName: "Copy To (new File-set)",
                    parameterType: .outputPath, placeholder: "folder for the new File-set",
                    helpText: "Copy the files into a new File-set in this folder under File IDs the tool assigns, DICOM\\PTnnnnnn\\STnnnnnn\\SEnnnnnn\\IMnnnnnn (PS3.10 8.2, 8.5), and write the DICOMDIR there (default output: <folder>/DICOMDIR). Without it, files are indexed in place and a path that is not a PS3.10 File ID (e.g. img1.dcm) is refused",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),
                CLIParameterDefinition(
                    id: "createVerbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output during creation",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["create"])
                ),

                // ----- validate -----
                CLIParameterDefinition(
                    id: "dicomdirPath", flag: "", displayName: "DICOMDIR Path",
                    parameterType: .filePath, placeholder: "path to DICOMDIR",
                    helpText: "Path to the DICOMDIR file (positional argument)",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate", "dump", "update"])
                ),
                CLIParameterDefinition(
                    id: "checkFiles", flag: "--check-files", displayName: "Check Files",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Check that every Referenced File ID (0004,1500) names a file in the File-set (PS3.10 8.6)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate"])
                ),
                CLIParameterDefinition(
                    id: "detailed", flag: "--detailed", displayName: "Detailed",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Detailed validation output (records per Directory Record Type, PS3.3 Table F.4-1)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["validate"])
                ),

                // ----- dump -----
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "tree",
                    helpText: "Output format: tree, json, text",
                    defaultValue: "tree",
                    allowedValues: ["tree", "json", "text"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["dump"])
                ),
                CLIParameterDefinition(
                    id: "dumpVerbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show all attributes for each record",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["dump"])
                ),

                // ----- update -----
                CLIParameterDefinition(
                    id: "add", flag: "--add", displayName: "Add Directory",
                    parameterType: .filePath, placeholder: "directory with new files",
                    helpText: "Directory with new DICOM files to add",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["update"])
                ),
                CLIParameterDefinition(
                    id: "updateVerbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "subcommand", values: ["update"])
                ),
            ]
case "dicom-pdf":
    // Help texts are dicom-pdf's (Sources/dicom-pdf/main.swift). --conversion-type offers the 8 Defined
    // Terms of PS3.3 2026a Table C.8-24 (ConversionType.definedTerms, the same list as the CLI's
    // PDFEncapsulation.conversionTypes; checked by diff_studio_g1), --burned-in-annotation the two
    // values of Table C.24-2; an empty picker value omits the option (the CLI writes WSD / YES).
    return [
        CLIParameterDefinition(
            id: "inputPath",
            flag: "",
            displayName: "Input",
            parameterType: .filePath,
            placeholder: "report.dcm or report.pdf",
            helpText: "Input file or directory (DICOM or document)",
            isRequired: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "output",
            flag: "--output",
            displayName: "Output",
            parameterType: .outputPath,
            placeholder: "Choose a location… (e.g. ExportedFile.pdf)",
            helpText: "Output file or directory path",
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "extract",
            flag: "--extract",
            displayName: "Extract Mode",
            parameterType: .booleanToggle,
            helpText: "Extract mode: Extract document from DICOM",
            defaultValue: "false"
        ),
        CLIParameterDefinition(
            id: "patient-name",
            flag: "--patient-name",
            displayName: "Patient's Name",
            parameterType: .textField,
            placeholder: "DOE^JOHN",
            helpText: "Patient's Name (for encapsulation mode)",
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "patient-id",
            flag: "--patient-id",
            displayName: "Patient ID",
            parameterType: .textField,
            placeholder: "12345",
            helpText: "Patient ID (for encapsulation mode)",
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "title",
            flag: "--title",
            displayName: "Document Title",
            parameterType: .textField,
            placeholder: "Radiology Report",
            helpText: "Document Title (0042,0010) (for encapsulation mode)",
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "study-uid",
            flag: "--study-uid",
            displayName: "Study Instance UID",
            parameterType: .textField,
            placeholder: "1.2.3.4.5 (auto if blank)",
            helpText: "Study Instance UID (auto-generated if not provided)",
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "series-uid",
            flag: "--series-uid",
            displayName: "Series Instance UID",
            parameterType: .textField,
            placeholder: "1.2.3.4.5.6 (auto if blank)",
            helpText: "Series Instance UID (auto-generated if not provided)",
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "modality",
            flag: "--modality",
            displayName: "Modality",
            parameterType: .textField,
            placeholder: "DOC (M3D for 3D models)",
            helpText: ModalityOptionValidator.helpText("to write (default: DOC; STL/OBJ/MTL require M3D, PS3.3 A.85.x.4.3)"),
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "strict-modality",
            flag: "--strict-modality",
            displayName: "Strict Modality",
            parameterType: .booleanToggle,
            helpText: "Reject a --modality value that is not a current DICOM Defined Term",
            isAdvanced: true,
            defaultValue: "false"
        ),
        CLIParameterDefinition(
            id: "series-description",
            flag: "--series-description",
            displayName: "Series Description",
            parameterType: .textField,
            placeholder: "Encapsulated PDF",
            helpText: "Series Description",
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "series-number",
            flag: "--series-number",
            displayName: "Series Number",
            parameterType: .integerField,
            placeholder: "1",
            helpText: "Series Number",
            isAdvanced: true,
            defaultValue: "",
            minValue: 0,
            maxValue: 999999
        ),
        CLIParameterDefinition(
            id: "instance-number",
            flag: "--instance-number",
            displayName: "Instance Number",
            parameterType: .integerField,
            placeholder: "1",
            helpText: "Instance Number",
            isAdvanced: true,
            defaultValue: "",
            minValue: 0,
            maxValue: 999999
        ),
        CLIParameterDefinition(
            id: "conversion-type",
            flag: "--conversion-type",
            displayName: "Conversion Type",
            parameterType: .enumPicker,
            placeholder: "WSD",
            helpText: "Conversion Type (0008,0064) for PDF and CDA, a PS3.3 Table C.8-24 Defined Term: DV, DI, DF, WSD, SD, SI, DRW, SYN (default: WSD)",
            isAdvanced: true,
            defaultValue: "",
            allowedValues: [""] + ConversionType.definedTerms
        ),
        CLIParameterDefinition(
            id: "burned-in-annotation",
            flag: "--burned-in-annotation",
            displayName: "Burned In Annotation",
            parameterType: .enumPicker,
            placeholder: "YES",
            helpText: "Burned In Annotation (0028,0301): YES or NO, whether the document identifies the patient and the date (default: YES)",
            isAdvanced: true,
            defaultValue: "",
            allowedValues: ["", "YES", "NO"]
        ),
        CLIParameterDefinition(
            id: "hl7-instance-identifier",
            flag: "--hl7-instance-identifier",
            displayName: "HL7 Instance Identifier",
            parameterType: .textField,
            placeholder: "2.16.840.1.113883.19^X1",
            helpText: "HL7 Instance Identifier (0040,E001) of a CDA document, UID or UID^extension (default: read from /ClinicalDocument/id; single file only)",
            isAdvanced: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "recursive",
            flag: "--recursive",
            displayName: "Recursive",
            parameterType: .booleanToggle,
            helpText: "Process directories recursively",
            isAdvanced: true,
            defaultValue: "false"
        ),
        CLIParameterDefinition(
            id: "show-metadata",
            flag: "--show-metadata",
            displayName: "Show Metadata",
            parameterType: .booleanToggle,
            helpText: "Show document metadata (extract mode)",
            isAdvanced: true,
            defaultValue: "false"
        ),
        CLIParameterDefinition(
            id: "verbose",
            flag: "--verbose",
            displayName: "Verbose",
            parameterType: .booleanToggle,
            helpText: "Verbose output",
            isAdvanced: true,
            defaultValue: "false"
        )
    ]
case "dicom-pixedit":
    // Help texts are dicom-pixedit's (Sources/dicom-pixedit/main.swift). --fill-value carries no default
    // so the option is omitted as on the CLI (the engine fills with 0); the executor refuses a value
    // outside the Bits Stored / Pixel Representation range and a window width below 1 with the CLI's
    // texts (P-PIXEDIT-RANGE, PS3.3 2026a C.7.6.3.1 / C.11.2.1.2).
    return [
        CLIParameterDefinition(
            id: "inputPath", flag: "", displayName: "Input File",
            parameterType: .filePath, placeholder: "Path to DICOM file",
            helpText: "Input DICOM file path",
            isRequired: true
        ),
        CLIParameterDefinition(
            id: "output", flag: "--output", displayName: "Output File",
            parameterType: .outputPath, placeholder: "Choose a location… (e.g. ExportedFile.dcm)",
            helpText: "Output DICOM file path",
            isRequired: true,
            defaultValue: ""
        ),
        CLIParameterDefinition(
            id: "mask-region", flag: "--mask-region", displayName: "Mask Region",
            parameterType: .textField, placeholder: "x,y,width,height",
            helpText: "Mask region x,y,width,height (0-based column, row) - sets every sample in it to --fill-value"
        ),
        CLIParameterDefinition(
            id: "fill-value", flag: "--fill-value", displayName: "Fill Value",
            parameterType: .integerField, placeholder: "0",
            helpText: "Stored value for masked samples (default: 0); must lie in the range of Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1), else exit 1",
            minValue: Int(Int32.min), maxValue: Int(UInt32.max)
        ),
        CLIParameterDefinition(
            id: "crop", flag: "--crop", displayName: "Crop Region",
            parameterType: .textField, placeholder: "x,y,width,height",
            helpText: "Crop region x,y,width,height (0-based column, row); Rows/Columns and Image Position (Patient) are updated"
        ),
        CLIParameterDefinition(
            id: "window-center", flag: "--window-center", displayName: "Window Center",
            parameterType: .textField, placeholder: "e.g. 40",
            helpText: "Window Center (0028,1050) for --apply-window, in Modality LUT output units (e.g. HU for CT; PS3.3 C.11.2.1.2)"
        ),
        CLIParameterDefinition(
            id: "window-width", flag: "--window-width", displayName: "Window Width",
            parameterType: .textField, placeholder: "e.g. 400",
            helpText: "Window Width (0028,1051) for --apply-window, in Modality LUT output units; at least 1 (PS3.3 C.11.2.1.2), else exit 1"
        ),
        CLIParameterDefinition(
            id: "apply-window", flag: "--apply-window", displayName: "Apply Window/Level",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Bake the window (PS3.3 C.11.2.1.2 linear function) into the stored pixel values"
        ),
        CLIParameterDefinition(
            id: "invert", flag: "--invert", displayName: "Invert",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Invert stored pixel values across the Bits Stored range"
        ),
        CLIParameterDefinition(
            id: "verbose", flag: "--verbose", displayName: "Verbose",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Show verbose output",
            isAdvanced: true
        ),
    ]
        case "dicom-video":
            // Every option, its help text and its allowed values come from the
            // shared `VideoConsole` in DICOMKit, which the `dicom-video` CLI also
            // declares its `@Option(help:)` strings from — so the form and the
            // CLI's `--help` cannot drift.
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "convert",
                    helpText: "convert: wrap one clip in a Video IOD · probe: report geometry and conformance · extract: recover the bitstream · batch: convert a folder",
                    isRequired: true,
                    defaultValue: "convert",
                    allowedValues: ["convert", "probe", "extract", "batch"]
                ),

                // ----- convert / probe: a single video input -----
                CLIParameterDefinition(
                    id: "input", flag: "", displayName: "Input Video",
                    parameterType: .filePath, placeholder: "clip.mp4",
                    helpText: VideoConsole.Help.input,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "probe"])
                ),

                // ----- extract: a DICOM input -----
                CLIParameterDefinition(
                    id: "dicomInput", flag: "", displayName: "Input DICOM File",
                    parameterType: .filePath, placeholder: "clip.dcm",
                    helpText: VideoConsole.Help.extractInput,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["extract"])
                ),

                // ----- batch: a directory of clips -----
                CLIParameterDefinition(
                    id: "inputDirectory", flag: "", displayName: "Input Directory",
                    parameterType: .filePath, placeholder: "clips/",
                    helpText: VideoConsole.Help.batchInput,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["batch"])
                ),

                // ----- outputs -----
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output DICOM File",
                    parameterType: .outputPath, placeholder: "clip.dcm",
                    helpText: VideoConsole.Help.output,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert"])
                ),
                CLIParameterDefinition(
                    id: "videoOutput", flag: "--output", displayName: "Output Video File",
                    parameterType: .outputPath, placeholder: "clip.mp4",
                    helpText: VideoConsole.Help.extractOutput,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["extract"])
                ),
                CLIParameterDefinition(
                    id: "outputDir", flag: "--output-dir", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "out/",
                    helpText: VideoConsole.Help.batchOutputDir,
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["batch"])
                ),

                // ----- SOP class selection (convert / batch) -----
                CLIParameterDefinition(
                    id: "type", flag: "--type", displayName: "Video Type",
                    parameterType: .enumPicker, placeholder: "endoscopic",
                    helpText: VideoConsole.Help.type
                        + ". Left empty the tool defaults to endoscopic and says so, because a wrong type yields a valid but mislabelled object.",
                    defaultValue: "",
                    allowedValues: [""] + VideoConsole.TypeArgument.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "transferSyntax", flag: "--transfer-syntax", displayName: "Transfer Syntax UID",
                    parameterType: .textField, placeholder: "auto-detected",
                    helpText: VideoOptionConformance.transferSyntaxHelp
                        + ". An explicit UID is still validated: a mislabelled object is worse than a rejected one.",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),

                // ----- convert-only tuning -----
                CLIParameterDefinition(
                    id: "frameRate", flag: "--frame-rate", displayName: "Frame Rate Override",
                    parameterType: .textField, placeholder: "e.g. 30",
                    helpText: VideoConsole.Help.frameRate
                        + ". Use when the bitstream declares no VUI timing.",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert"])
                ),
                CLIParameterDefinition(
                    id: "instanceNumber", flag: "--instance-number", displayName: "Instance Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: VideoConsole.Help.instanceNumber,
                    isAdvanced: true,
                    defaultValue: "1", minValue: 0, maxValue: 999999,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert"])
                ),
                CLIParameterDefinition(
                    id: "seriesNumber", flag: "--series-number", displayName: "Series Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: VideoConsole.Help.seriesNumber,
                    isAdvanced: true,
                    defaultValue: "1", minValue: 0, maxValue: 999999,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert"])
                ),

                // ----- batch-only grouping and traversal -----
                CLIParameterDefinition(
                    id: "seriesMode", flag: "--series-mode", displayName: "Series Mode",
                    parameterType: .enumPicker, placeholder: "single",
                    helpText: VideoConsole.Help.seriesMode
                        + ". single is what IHE Endoscopy requires of clips from one procedure step on one piece of equipment.",
                    defaultValue: "single",
                    allowedValues: VideoConsole.SeriesMode.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["batch"])
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: VideoConsole.Help.recursive,
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["batch"])
                ),
                CLIParameterDefinition(
                    id: "continueOnError", flag: "--continue-on-error", displayName: "Continue On Error",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: VideoConsole.Help.continueOnError
                        + ". Off by default, so a half-populated series is never left behind.",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["batch"])
                ),

                // ----- shared flags -----
                CLIParameterDefinition(
                    id: "dryRun", flag: "--dry-run", displayName: "Dry Run",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: VideoConsole.Help.dryRun,
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "trustInput", flag: "--trust-input", displayName: "Trust Input",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Encapsulate an MPEG-2 Transport Stream without validating it. Transport streams are demultiplexed and validated by default; this skips that, so convert also requires an explicit Transfer Syntax UID.",
                    isAdvanced: true,
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "probe"])
                ),
                CLIParameterDefinition(
                    id: "force", flag: "--force", displayName: "Overwrite Existing",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: VideoConsole.Help.force,
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "extract", "batch"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: VideoConsole.Help.verbose
                        + ". Explains which container was recognised, why a transfer syntax was chosen, where the frame count came from and which UIDs were minted.",
                    defaultValue: "false"
                ),

                // ----- patient / study / series metadata (convert / batch) -----
                CLIParameterDefinition(
                    id: "patientName", flag: "--patient-name", displayName: "Patient Name",
                    parameterType: .textField, placeholder: "Doe^Jane",
                    helpText: VideoConsole.Help.patientName,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "patientID", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "12345",
                    helpText: VideoConsole.Help.patientID,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "patientBirthDate", flag: "--patient-birth-date", displayName: "Patient Birth Date",
                    parameterType: .textField, placeholder: "YYYYMMDD",
                    helpText: VideoOptionConformance.patientBirthDateHelp,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "patientSex", flag: "--patient-sex", displayName: "Patient Sex",
                    parameterType: .enumPicker, placeholder: "",
                    helpText: VideoOptionConformance.patientSexHelp,
                    isAdvanced: true,
                    defaultValue: "",
                    allowedValues: ["", "M", "F", "O"],
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "studyUID", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "auto-generated",
                    helpText: VideoConsole.Help.studyUID,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "seriesUID", flag: "--series-uid", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "auto-generated",
                    helpText: VideoConsole.Help.seriesUID
                        + ". Cannot be combined with Series Mode per-file, which mints a UID per clip.",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "accessionNumber", flag: "--accession-number", displayName: "Accession Number",
                    parameterType: .textField, placeholder: "A12345",
                    helpText: VideoConsole.Help.accessionNumber,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "studyID", flag: "--study-id", displayName: "Study ID",
                    parameterType: .textField, placeholder: "1",
                    helpText: VideoConsole.Help.studyID,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "referringPhysician", flag: "--referring-physician", displayName: "Referring Physician",
                    parameterType: .textField, placeholder: "Smith^Robert",
                    helpText: VideoConsole.Help.referringPhysician,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "seriesDescription", flag: "--series-description", displayName: "Series Description",
                    parameterType: .textField, placeholder: "Endoscopy clip",
                    helpText: VideoConsole.Help.seriesDescription,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .textField, placeholder: "ES / GM / XC",
                    helpText: VideoOptionConformance.modalityHelp,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "strictModality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term",
                    isAdvanced: true,
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "manufacturer", flag: "--manufacturer", displayName: "Manufacturer",
                    parameterType: .textField, placeholder: "Acme Endoscopes",
                    helpText: VideoConsole.Help.manufacturer,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                CLIParameterDefinition(
                    id: "institutionName", flag: "--institution-name", displayName: "Institution Name",
                    parameterType: .textField, placeholder: "General Hospital",
                    helpText: VideoConsole.Help.institutionName,
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
                // PS3.16 2026a CID 3000 Audio Channel Source into PS3.3 Table C.7-13 (003A,0300) /
                // (003A,0208) (D56): one value is the source of every audio track, repeated values are
                // one per track in container order (VideoWorkflow.Metadata.audioChannelSources). The
                // keywords are the CLI's AudioChannelSourceOption (mirrored; checked by diff_studio_g1).
                CLIParameterDefinition(
                    id: "audioChannelSource", flag: "--audio-channel-source", displayName: "Audio Channel Source",
                    parameterType: .textField, placeholder: "voice; operators-narrative",
                    helpText: AudioChannelSourceOption.help + " Separate several sources with “ ; ”.",
                    isAdvanced: true,
                    isRepeatable: true,
                    visibleWhen: CLIParameterVisibilityCondition(
                        parameterId: "operation", values: ["convert", "batch"])
                ),
            ]

        case "dicom-image":
            // Help texts are dicom-image's (Sources/dicom-image/main.swift); the Workshop adds only the
            // " ; " separator note where a field takes several values. --conversion-type offers the 8
            // Defined Terms of PS3.3 2026a Table C.8-24 through the shared ConversionType.definedTerms
            // (checked against the DocBook by diff_studio_g1); empty omits the option (the CLI writes WSD).
            return [
                CLIParameterDefinition(
                    id: "input", flag: "", displayName: "Input Image/Directory",
                    parameterType: .filePath, placeholder: "Path to image file or directory",
                    helpText: "Input image file or directory",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output File/Directory",
                    parameterType: .outputPath, placeholder: "Output file or directory path",
                    helpText: "Output file or directory path",
                    isRequired: false
                ),
                CLIParameterDefinition(
                    id: "patient-name", flag: "--patient-name", displayName: "Patient's Name",
                    parameterType: .textField, placeholder: "DOE^JOHN",
                    helpText: "Patient's Name (0010,0010), PN, e.g. 'DOE^JOHN' (at most 64 characters per component group, no backslash)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "patient-id", flag: "--patient-id", displayName: "Patient ID",
                    parameterType: .textField, placeholder: "12345",
                    helpText: "Patient ID (0010,0020), LO (at most 64 characters, no backslash)",
                    isRequired: true
                ),
                CLIParameterDefinition(
                    id: "study-description", flag: "--study-description", displayName: "Study Description",
                    parameterType: .textField, placeholder: "Clinical Photography",
                    helpText: "Study Description (0008,1030), LO (at most 64 characters, no backslash)"
                ),
                CLIParameterDefinition(
                    id: "series-description", flag: "--series-description", displayName: "Series Description",
                    parameterType: .textField, placeholder: "Clinical Photos",
                    helpText: "Series Description (0008,103E), LO (at most 64 characters, no backslash)"
                ),
                CLIParameterDefinition(
                    id: "study-uid", flag: "--study-uid", displayName: "Study Instance UID",
                    parameterType: .textField, placeholder: "auto-generated",
                    helpText: "Study Instance UID (0020,000D), UI per PS3.5 Section 9 (generated if not provided)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "series-uid", flag: "--series-uid", displayName: "Series Instance UID",
                    parameterType: .textField, placeholder: "auto-generated",
                    helpText: "Series Instance UID (0020,000E), UI per PS3.5 Section 9 (generated if not provided)",
                    isAdvanced: true
                ),
                CLIParameterDefinition(
                    id: "series-number", flag: "--series-number", displayName: "Series Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Series Number (0020,0011), IS (written empty if not provided; Type 2)",
                    isAdvanced: true, minValue: Int(Int32.min), maxValue: Int(Int32.max)
                ),
                CLIParameterDefinition(
                    id: "instance-number", flag: "--instance-number", displayName: "Instance Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Instance Number (0020,0013), IS (default 1; starting value for batch and TIFF pages)",
                    isAdvanced: true, minValue: Int(Int32.min), maxValue: Int(Int32.max)
                ),
                CLIParameterDefinition(
                    id: "modality", flag: "--modality", displayName: "Modality",
                    parameterType: .textField, placeholder: "OT",
                    helpText: ModalityOptionValidator.helpText("to write (default: OT)")
                ),
                CLIParameterDefinition(
                    id: "strict-modality", flag: "--strict-modality", displayName: "Strict Modality",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Reject a --modality value that is not a current DICOM Defined Term"
                ),
                CLIParameterDefinition(
                    id: "conversion-type", flag: "--conversion-type", displayName: "Conversion Type",
                    parameterType: .enumPicker, placeholder: "WSD",
                    helpText: "Conversion Type (0008,0064): DV, DI, DF, WSD, SD, SI, DRW or SYN (PS3.3 Table C.8-24; default: WSD)",
                    isAdvanced: true,
                    defaultValue: "",
                    allowedValues: [""] + ConversionType.definedTerms
                ),
                CLIParameterDefinition(
                    id: "use-exif", flag: "--use-exif", displayName: "Use EXIF Metadata",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Use EXIF metadata: DateTimeOriginal -> Acquisition Date/Time (0008,0022/0032), DPI -> Nominal Scanned Pixel Spacing (0018,2010), description -> Study Description"
                ),
                CLIParameterDefinition(
                    id: "split-pages", flag: "--split-pages", displayName: "Split Multi-page TIFF",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Write each page of a multi-page TIFF as its own Secondary Capture instance"
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive Directory",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Process directories recursively"
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose Output",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Verbose output",
                    isAdvanced: true
                ),
            ]
case "dicom-export":
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "single",
                    helpText: "Export operation: single image, contact sheet, animated GIF, or bulk directory export",
                    isRequired: true,
                    defaultValue: "single",
                    allowedValues: ["single", "contact-sheet", "animate", "bulk"]
                ),
                CLIParameterDefinition(
                    id: "inputPath", flag: "", displayName: "Input File/Directory",
                    parameterType: .filePath, placeholder: "Path to DICOM file(s) or directory",
                    helpText: "DICOM file (single/animate) or directory of DICOM files (contact-sheet/bulk). Contact-sheet accepts several files — separate with “ ; ”.",
                    isRequired: true,
                    isRepeatable: true
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Path",
                    parameterType: .outputPath, placeholder: "Output file or directory path",
                    helpText: "Destination image, GIF, or directory for exported files",
                    isRequired: true
                ),
                // --- single ---
                // The CLI's `single --format` default is jpeg (contact-sheet and bulk default to png).
                CLIParameterDefinition(
                    id: "format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "jpeg",
                    helpText: "Output format: png, jpeg, tiff (default: jpeg)",
                    defaultValue: "jpeg",
                    allowedValues: ExportImageFormat.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single"])
                ),
                CLIParameterDefinition(
                    id: "quality", flag: "--quality", displayName: "JPEG Quality",
                    parameterType: .integerField, placeholder: "90",
                    helpText: "JPEG compression quality (1–100, default: 90)",
                    defaultValue: "90", minValue: 1, maxValue: 100,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single", "contact-sheet", "bulk"])
                ),
                CLIParameterDefinition(
                    id: "embed-metadata", flag: "--embed-metadata", displayName: "Embed Metadata",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Embed DICOM attributes as EXIF/TIFF tags (PS3.6 keywords; bulk embeds PatientName, StudyDate, Modality, StudyDescription, Manufacturer)",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single", "bulk"])
                ),
                CLIParameterDefinition(
                    id: "exif-fields", flag: "--exif-fields", displayName: "EXIF Fields",
                    parameterType: .textField, placeholder: "PatientName,StudyDate,Modality",
                    helpText: "Comma-separated PS3.6 keywords to embed: \(DICOMImageExporter.supportedEXIFFields.joined(separator: ", ")) (default: PatientName,StudyDate,Modality,StudyDescription,Manufacturer). StudyDate (DA) is written as Exif DateTimeOriginal with StudyTime; PatientID, Modality and SeriesDescription go to Exif UserComment as Keyword=value",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single"])
                ),
                // P-EXPORT-1 (D127): frames are selected by Frame number from 1 (PS3.3 Table 10-3
                // "The first Frame shall be denoted as Frame number 1"); the 0-based --frame is
                // deprecated and the executor prints the CLI's stderr note when it is used.
                CLIParameterDefinition(
                    id: "frame-number", flag: "--frame-number", displayName: "Frame Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "Frame to export, numbered from 1 (PS3.3 Table 10-3; default 1)",
                    minValue: 1, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single"])
                ),
                CLIParameterDefinition(
                    id: "frame", flag: "--frame", displayName: "Frame Index (deprecated)",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "deprecated: 0-based index; use --frame-number",
                    isAdvanced: true,
                    minValue: 0, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single"])
                ),
                // --- windowing (single, animate) ---
                CLIParameterDefinition(
                    id: "apply-window", flag: "--apply-window", displayName: "Apply Window/Level",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Use --window-center/--window-width (LINEAR, PS3.3 C.11.2.1.2.1). Without it the file's VOI is applied: Window Center (0028,1050) and Window Width (0028,1051), else VOI LUT Sequence (0028,3010), else the full pixel range",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single", "animate"])
                ),
                // P-EXPORT-3 (D127): on contact-sheet and bulk the flag has no effect (the file's
                // VOI is always applied), so it is deprecated; the executor prints the CLI's note.
                CLIParameterDefinition(
                    id: "apply-window-deprecated", flag: "--apply-window", displayName: "Apply Window (deprecated)",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "deprecated: no effect; the file's VOI (Window Center (0028,1050) and Window Width (0028,1051), else VOI LUT Sequence (0028,3010), else the full pixel range) is always applied",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet", "bulk"])
                ),
                CLIParameterDefinition(
                    id: "window-center", flag: "--window-center", displayName: "Window Center",
                    parameterType: .textField, placeholder: "e.g. 40",
                    helpText: "Window Center (0028,1050) in modality units (after Rescale Slope/Intercept); needs --apply-window and --window-width",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single", "animate"])
                ),
                CLIParameterDefinition(
                    id: "window-width", flag: "--window-width", displayName: "Window Width",
                    parameterType: .textField, placeholder: "e.g. 400",
                    helpText: "Window Width (0028,1051) in modality units, >= 1; needs --apply-window and --window-center",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["single", "animate"])
                ),
                // --- contact-sheet ---
                CLIParameterDefinition(
                    id: "columns", flag: "--columns", displayName: "Columns",
                    parameterType: .integerField, placeholder: "4",
                    helpText: "Number of thumbnail columns",
                    defaultValue: "4", minValue: 1, maxValue: 64,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet"])
                ),
                CLIParameterDefinition(
                    id: "thumbnail-size", flag: "--thumbnail-size", displayName: "Thumbnail Size",
                    parameterType: .integerField, placeholder: "256",
                    helpText: "Thumbnail size in pixels",
                    defaultValue: "256", minValue: 16, maxValue: 2048,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet"])
                ),
                CLIParameterDefinition(
                    id: "spacing", flag: "--spacing", displayName: "Spacing",
                    parameterType: .integerField, placeholder: "4",
                    helpText: "Spacing between thumbnails in pixels",
                    defaultValue: "4", minValue: 0, maxValue: 256,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet"])
                ),
                CLIParameterDefinition(
                    id: "labels", flag: "--labels", displayName: "Filename Labels",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Add filename labels below thumbnails",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet"])
                ),
                CLIParameterDefinition(
                    id: "sheet-format", flag: "--format", displayName: "Sheet Format",
                    parameterType: .enumPicker, placeholder: "png",
                    helpText: "Output format: png, jpeg (default: png; tiff is also accepted)",
                    defaultValue: "png",
                    allowedValues: ExportImageFormat.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["contact-sheet"])
                ),
                // --- animate ---
                // No fixed default (D127): as the CLI, the rate comes from the file's Cine Module
                // (PS3.3 Table C.7-13) — Recommended Display Frame Rate (0008,2144), else Cine Rate
                // (0018,0040), else 1000 / Frame Time (0018,1063) — and only then 10.
                CLIParameterDefinition(
                    id: "fps", flag: "--fps", displayName: "Frames Per Second",
                    parameterType: .textField, placeholder: "file's frame rate",
                    helpText: "Frames per second. Default: the file's Recommended Display Frame Rate (0008,2144), else Cine Rate (0018,0040), else 1000 / Frame Time (0018,1063) (msec), else 10",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                CLIParameterDefinition(
                    id: "loop-count", flag: "--loop-count", displayName: "Loop Count",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "Number of loops (0 = infinite)",
                    defaultValue: "0", minValue: 0, maxValue: 65535,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                // P-EXPORT-1 (D127): Frame numbers from 1 (PS3.3 Table 10-3); the 0-based
                // --start-frame / --end-frame are deprecated (the executor prints the CLI's notes
                // and refuses mixing the two kinds, exit 1).
                CLIParameterDefinition(
                    id: "start-frame-number", flag: "--start-frame-number", displayName: "Start Frame Number",
                    parameterType: .integerField, placeholder: "1",
                    helpText: "First frame, Frame number from 1 (PS3.3 Table 10-3; default 1)",
                    minValue: 1, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                CLIParameterDefinition(
                    id: "end-frame-number", flag: "--end-frame-number", displayName: "End Frame Number",
                    parameterType: .integerField, placeholder: "last frame",
                    helpText: "Last frame, Frame number from 1, inclusive (default: the last frame)",
                    minValue: 1, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                CLIParameterDefinition(
                    id: "start-frame", flag: "--start-frame", displayName: "Start Frame Index (deprecated)",
                    parameterType: .integerField, placeholder: "0",
                    helpText: "deprecated: 0-based index; use --start-frame-number",
                    isAdvanced: true,
                    minValue: 0, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                CLIParameterDefinition(
                    id: "end-frame", flag: "--end-frame", displayName: "End Frame Index (deprecated)",
                    parameterType: .integerField, placeholder: "last frame",
                    helpText: "deprecated: 0-based index; use --end-frame-number",
                    isAdvanced: true,
                    minValue: 0, maxValue: 99999,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                CLIParameterDefinition(
                    id: "scale", flag: "--scale", displayName: "Scale Factor",
                    parameterType: .textField, placeholder: "1.0",
                    helpText: "Scale factor (0.1–2.0)",
                    defaultValue: "1.0",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["animate"])
                ),
                // --- bulk ---
                CLIParameterDefinition(
                    id: "bulk-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "png",
                    helpText: "Output format: png, jpeg, tiff (default: png)",
                    defaultValue: "png",
                    allowedValues: ExportImageFormat.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["bulk"])
                ),
                CLIParameterDefinition(
                    id: "organize-by", flag: "--organize-by", displayName: "Organize By",
                    parameterType: .enumPicker, placeholder: "flat",
                    // P-EXPORT-2 (D127): the patient folder is Patient ID (0010,0020) [+ @Issuer of
                    // Patient ID (0010,0021)], the Patient level unique key (PS3.4 Table C.6-1).
                    helpText: "Folders: flat; patient = Patient ID (0010,0020), plus @Issuer of Patient ID (0010,0021) when present (PS3.3 Table C.7-1; before 2026-10-01 Patient's Name); study = patient + Study Instance UID (0020,000D); series = study + Series Instance UID (0020,000E)",
                    defaultValue: "flat",
                    allowedValues: OrganizationScheme.allCases.map(\.rawValue),
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["bulk"])
                ),
                CLIParameterDefinition(
                    id: "recursive", flag: "--recursive", displayName: "Recursive",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Process subdirectories recursively",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["bulk"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Print per-file progress",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["bulk"])
                ),
            ]
case "dicom-compress":
    // Single source of truth: derive the codec list straight from DICOMKit's
    // CompressionManager (which is itself driven by DICOMCore's TransferSyntax
    // catalog + the registered CodecRegistry encoders). This guarantees the app
    // picker always lists exactly the transfer syntaxes the shared compression
    // engine — and the `dicom-compress` CLI — can actually produce, covering all
    // four JPEG Swift libraries (JLISwift, J2KSwift, JLSwift/JPEG-LS, JXLSwift)
    // plus RLE and the uncompressed targets. Never hand-maintain this list again.
    //
    // ONE entry per producible transfer syntax — the canonical name only. The CLI
    // aliases (jxl/jpeg-xl-lossless, j2k, jls, …) all still resolve via
    // CompressionManager.transferSyntax(for:), but listing them in the picker just
    // duplicates the same target (e.g. 4 JPEG-XL look-alikes), so they're dropped
    // here to keep the dropdown = the 18 actual transfer syntaxes.
    let compressCodecValues = CompressionManager.supportedCodecs().map { $0.name }
    return [
        CLIParameterDefinition(
            id: "operation", flag: "", displayName: "Operation",
            parameterType: .subcommand, placeholder: "info",
            helpText: "info: show compression details · compress: encode to a codec · decompress: decode to uncompressed · batch: process a directory · backends: list hardware backends",
            isRequired: true,
            defaultValue: "info",
            allowedValues: ["info", "compress", "decompress", "batch", "backends"]
        ),

        // ----- info / compress / decompress: single input file -----
        CLIParameterDefinition(
            id: "input", flag: "", displayName: "Input File",
            parameterType: .filePath, placeholder: "input.dcm",
            helpText: "Input DICOM file path",
            isRequired: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["info", "compress", "decompress"])
        ),
        CLIParameterDefinition(
            id: "json", flag: "--json", displayName: "JSON Output",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Output as JSON",
            defaultValue: "false",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["info", "backends"])
        ),

        // ----- batch: input directory -----
        CLIParameterDefinition(
            id: "inputDir", flag: "", displayName: "Input Directory",
            parameterType: .filePath, placeholder: "input_dir/",
            helpText: "Input directory path",
            isRequired: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["batch"])
        ),

        // ----- output (compress / decompress = file, batch = directory) -----
        CLIParameterDefinition(
            id: "output", flag: "--output", displayName: "Output File",
            parameterType: .outputPath, placeholder: "output.dcm",
            helpText: "Output DICOM file path",
            isRequired: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress", "decompress"])
        ),
        CLIParameterDefinition(
            id: "outputDir", flag: "--output", displayName: "Output Directory",
            parameterType: .outputPath, placeholder: "output_dir/",
            helpText: "Output directory path",
            isRequired: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["batch"])
        ),

        // ----- codec (compress; optional for batch) -----
        CLIParameterDefinition(
            id: "codec", flag: "--codec", displayName: "Codec",
            parameterType: .enumPicker, placeholder: "jpeg-lossless",
            helpText: "Target codec (e.g., jpeg-lossless, jpeg2000, rle)",
            isRequired: true,
            defaultValue: "jpeg-lossless",
            allowedValues: compressCodecValues,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress"])
        ),
        CLIParameterDefinition(
            id: "batchCodec", flag: "--codec", displayName: "Codec",
            parameterType: .enumPicker, placeholder: "jpeg-lossless",
            helpText: "Target codec for compression (e.g., jpeg-lossless, jpeg2000)",
            defaultValue: "",
            allowedValues: [""] + compressCodecValues,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["batch"])
        ),

        // ----- JPEG engine (compress → jpeg baseline only; app-only, no CLI flag) -----
        //
        // JPEG Baseline is the ONE transfer syntax this library can encode two ways:
        // the pure-Swift JLICodec (the registry default for all four JPEG syntaxes) or
        // Apple's ImageIO NativeJPEGCodec. ImageIO ships no SOF1/SOF3 encoder, so JPEG
        // Extended / Lossless / Lossless SV1 have no second engine and never show this
        // picker — they keep encoding through JLICodec exactly as before.
        //
        // `isInternal` because this exists purely to benchmark the two Baseline encoders
        // inside DICOMStudio: the `dicom-compress` CLI has no matching flag, so the
        // picker must stay out of the copy-pasteable command preview.
        CLIParameterDefinition(
            id: "jpegCodec", flag: "", displayName: "JPEG Engine",
            parameterType: .enumPicker, placeholder: JPEGCodecEngine.jli.rawValue,
            helpText: "Encoder for JPEG Baseline: jli (pure-Swift JLICodec) or native (Apple ImageIO). "
                + "In-app performance comparison only — not a dicom-compress CLI option.",
            isInternal: true,
            defaultValue: JPEGCodecEngine.jli.rawValue,
            allowedValues: JPEGCodecEngine.allCases.map { $0.rawValue },
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress"]),
            visibleWhenAll: [
                CLIParameterVisibilityCondition(
                    parameterId: "codec",
                    values: CompressionManager.supportedCodecs()
                        .filter { $0.syntax.uid == CodecRegistry.jpegEngineSelectableUID }
                        .map { $0.name })
            ]
        ),

        // ----- quality (compress / batch lossy) -----
        CLIParameterDefinition(
            id: "quality", flag: "--quality", displayName: "Quality",
            parameterType: .textField, placeholder: "high / 0.0-1.0",
            helpText: "Quality: maximum, high, medium, low, or a value 0.0-1.0",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress", "batch"])
        ),

        // ----- syntax (decompress / batch decompress) -----
        // Only the native targets of dicom-compress' NativeTargetSyntax (PS3.5 2026a A.1, A.2, A.5 and
        // the retired A.3 Explicit VR Big Endian, D206): explicit-le, implicit-le, deflate, explicit-be
        // (P-COMPRESS-SYNTAX; DICOMKit CompressionConsole.NativeTargetSyntax, D267, as dicom-compress).
        CLIParameterDefinition(
            id: "syntax", flag: "--syntax", displayName: "Target Syntax",
            parameterType: .enumPicker, placeholder: "explicit-le",
            helpText: "Native target syntax for decompression: explicit-le (default), implicit-le, deflate, explicit-be (retired)",
            defaultValue: "explicit-le",
            allowedValues: CompressionConsole.NativeTargetSyntax.accepted.map(\.name),
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["decompress", "batch"])
        ),

        // ----- batch flags -----
        CLIParameterDefinition(
            id: "decompress", flag: "--decompress", displayName: "Decompress",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Decompress files instead of compressing",
            defaultValue: "false",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["batch"])
        ),
        CLIParameterDefinition(
            id: "recursive", flag: "--recursive", displayName: "Recursive",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Process subdirectories recursively",
            defaultValue: "false",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["batch"])
        ),

        // ----- compress backend -----
        CLIParameterDefinition(
            id: "backend", flag: "--backend", displayName: "Backend",
            parameterType: .enumPicker, placeholder: "auto",
            helpText: "Hardware backend: auto (default), metal, accelerate, scalar",
            defaultValue: "auto",
            allowedValues: ["auto", "metal", "accelerate", "scalar"],
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress"])
        ),

        // ----- verbose (compress / decompress / batch) -----
        CLIParameterDefinition(
            id: "verbose", flag: "--verbose", displayName: "Verbose",
            parameterType: .booleanToggle, placeholder: "",
            helpText: "Show verbose output",
            defaultValue: "false",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compress", "decompress", "batch"])
        ),
    ]
case "dicom-study":
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "organize",
                    helpText: "Study operation: organize files into study/series folders, summarize metadata, check completeness, compute statistics, or compare two studies",
                    isRequired: true,
                    defaultValue: "organize",
                    allowedValues: ["organize", "summary", "check", "stats", "compare"]
                ),

                // ----- organize -----
                CLIParameterDefinition(
                    id: "input", flag: "", displayName: "Input Directory",
                    parameterType: .filePath, placeholder: "Choose a folder… (e.g. CT)",
                    helpText: "Input directory containing DICOM files",
                    isRequired: true,
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["organize"])
                ),
                CLIParameterDefinition(
                    id: "output", flag: "--output", displayName: "Output Directory",
                    parameterType: .outputPath, placeholder: "Choose a folder… (e.g. dicom-study)",
                    helpText: "Output directory for organized files",
                    isRequired: true,
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["organize"])
                ),
                CLIParameterDefinition(
                    id: "pattern", flag: "--pattern", displayName: "Naming Pattern",
                    parameterType: .enumPicker, placeholder: "descriptive",
                    helpText: "Folder naming: 'descriptive' = <Patient's Name>_<Study Description>_<last 8 characters of Study Instance UID>/<Series Number>_<Modality>_<Series Description>/<n>.dcm; 'uid' = <Study Instance UID>/<Series Instance UID>/<n>.dcm (default: descriptive)",
                    defaultValue: "descriptive",
                    allowedValues: ["descriptive", "uid"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["organize"])
                ),
                CLIParameterDefinition(
                    id: "copy", flag: "--copy", displayName: "Copy Files",
                    parameterType: .booleanToggle, placeholder: "false",
                    // Off by default as in dicom-study (organize MOVES the files unless --copy).
                    helpText: "Copy files instead of moving them",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["organize"])
                ),

                // ----- summary -----
                CLIParameterDefinition(
                    id: "path", flag: "", displayName: "Study Path",
                    parameterType: .filePath, placeholder: "Choose a folder… (e.g. CT)",
                    helpText: "Study directory or single DICOM file",
                    isRequired: true,
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["summary", "check", "stats"])
                ),
                CLIParameterDefinition(
                    id: "summary-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "table",
                    helpText: "Output format: 'table', 'json', or 'csv' (default: table). CSV adds the PS3.6 keyword columns StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances; StudyUID, SeriesCount, InstanceCount are deprecated",
                    defaultValue: "table",
                    allowedValues: ["table", "json", "csv"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["summary"])
                ),

                // ----- check -----
                CLIParameterDefinition(
                    id: "expected-series", flag: "--expected-series", displayName: "Expected Series",
                    parameterType: .integerField, placeholder: "5",
                    helpText: "Expected number of series in the study (Number of Study Related Series (0020,1206), PS3.4 Table C.6-2)",
                    minValue: 0, maxValue: 100000,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["check"])
                ),
                CLIParameterDefinition(
                    id: "expected-instances", flag: "--expected-instances", displayName: "Expected Instances/Series",
                    parameterType: .integerField, placeholder: "120",
                    helpText: "Expected number of instances in each series (Number of Series Related Instances (0020,1209), PS3.4 Table C.6-3)",
                    minValue: 0, maxValue: 100000,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["check"])
                ),
                CLIParameterDefinition(
                    id: "report", flag: "--report", displayName: "Report File",
                    parameterType: .outputPath, placeholder: "Choose a location… (e.g. dicom-study/report/StudyReport.txt)",
                    helpText: "Output report file path (one detected issue per line; a gap in Instance Number (0020,0013) is a heuristic, PS3.3 Table C.7-9)",
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["check"])
                ),

                // ----- stats -----
                CLIParameterDefinition(
                    id: "detailed", flag: "--detailed", displayName: "Detailed",
                    parameterType: .booleanToggle, placeholder: "false",
                    helpText: "Show detailed per-series statistics",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["stats"])
                ),
                CLIParameterDefinition(
                    id: "stats-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "text",
                    helpText: "Output format: 'text' or 'json' (default: text). JSON adds PS3.6 keyword keys (StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances); the former keys are deprecated",
                    defaultValue: "text",
                    allowedValues: ["text", "json"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["stats"])
                ),

                // ----- compare -----
                CLIParameterDefinition(
                    id: "path1", flag: "", displayName: "Study 1",
                    parameterType: .filePath, placeholder: "Choose a folder… (e.g. CT)",
                    helpText: "First study directory",
                    isRequired: true,
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compare"])
                ),
                CLIParameterDefinition(
                    id: "path2", flag: "", displayName: "Study 2",
                    parameterType: .filePath, placeholder: "Choose a folder… (e.g. MR)",
                    helpText: "Second study directory",
                    isRequired: true,
                    defaultValue: "",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compare"])
                ),
                CLIParameterDefinition(
                    id: "compare-format", flag: "--format", displayName: "Output Format",
                    parameterType: .enumPicker, placeholder: "text",
                    helpText: "Output format: 'text' or 'json' (default: text). JSON adds PS3.6 keyword keys (StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances); the former keys are deprecated",
                    defaultValue: "text",
                    allowedValues: ["text", "json"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["compare"])
                ),

                // ----- shared verbose (organize/summary/check/compare) -----
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "false",
                    helpText: "Show verbose output",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["organize", "summary", "check", "compare"])
                )
            ]
case "dicom-script":
            return [
                CLIParameterDefinition(
                    id: "operation", flag: "", displayName: "Operation",
                    parameterType: .subcommand, placeholder: "run",
                    helpText: "run: execute a workflow script; validate: check a script for errors; template: generate a starter script",
                    isRequired: true,
                    defaultValue: "run",
                    allowedValues: ["run", "validate", "template"]
                ),
                // ----- run / validate: script file -----
                CLIParameterDefinition(
                    id: "scriptPath", flag: "", displayName: "Script File",
                    parameterType: .filePath, placeholder: "workflow.dcmscript",
                    helpText: "Path to the DICOM Script Language (.dcmscript) file to execute or validate",
                    isRequired: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run", "validate"])
                ),
                // ----- run: variables -----
                CLIParameterDefinition(
                    id: "variables", flag: "--variables", displayName: "Variables",
                    parameterType: .arrayField, placeholder: "KEY=VALUE; KEY2=VALUE2",
                    helpText: "Variable substitutions in KEY=VALUE format (e.g. PATIENT_ID=12345). Separate with “ ; ”.",
                    isRepeatable: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run"])
                ),
                CLIParameterDefinition(
                    id: "parallel", flag: "--parallel", displayName: "Parallel Execution",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Enable parallel execution where possible",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run"])
                ),
                CLIParameterDefinition(
                    id: "verbose", flag: "--verbose", displayName: "Verbose",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Show verbose execution output",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run", "validate"])
                ),
                CLIParameterDefinition(
                    id: "dryRun", flag: "--dry-run", displayName: "Dry Run",
                    parameterType: .booleanToggle, placeholder: "",
                    helpText: "Dry run — show what would be executed without running any commands",
                    defaultValue: "false",
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run"])
                ),
                CLIParameterDefinition(
                    id: "log", flag: "--log", displayName: "Log File",
                    parameterType: .outputPath, placeholder: "run.log",
                    helpText: "Optional log file path for execution output",
                    isAdvanced: true,
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["run"])
                ),
                // ----- template: name -----
                CLIParameterDefinition(
                    id: "templateName", flag: "", displayName: "Template",
                    parameterType: .enumPicker, placeholder: "workflow",
                    helpText: "Starter template to generate",
                    isRequired: true,
                    defaultValue: "workflow",
                    allowedValues: ["workflow", "pipeline", "query", "archive", "anonymize"],
                    visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["template"])
                ),
            ]
        default:
            return []
        }
    }

    // MARK: - Input/output paths (CLI Workshop)
    //
    // Path fields start EMPTY — the user picks a file or folder with the field's
    // Browse button (2026-08-03). Nothing is pre-filled any more.
    //
    // History: these fields used to be seeded with one developer's absolute paths
    // (`/Users/raster/Desktop/DICOM_Input|DICOM_Output`), backed by
    // `com.apple.security.temporary-exception.files.absolute-path.read-write`
    // entitlements. The App Sandbox is now enabled and those exceptions are gone, so a
    // pre-filled path could not be read anyway: a sandboxed app reaches a file only
    // once the USER selects it, which is what grants the security-scoped access the
    // Workshop stores in `securityScopedURLs`. Do not reintroduce seeded paths — an
    // empty field plus Browse is both the correct sandbox flow and correct for any
    // user on any machine.

    /// Public catalog accessor. Path fields are intentionally left empty; every other
    /// parameter keeps whatever `defaultValue` its raw definition declares.
    public static func parameterDefinitions(for toolID: String) -> [CLIParameterDefinition] {
        rawParameterDefinitions(for: toolID)
    }
}

// MARK: - 16.3 Command Builder Helpers

/// Helpers for building CLI command strings from parameters.
public enum CommandBuilderHelpers: Sendable {

    /// Builds a CLI command string from tool name and parameter values.
    public static func buildCommand(
        toolName: String,
        subcommand: String? = nil,
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition]
    ) -> String {
        var parts: [String] = [toolName]
        if let sub = subcommand, !sub.isEmpty {
            parts.append(sub)
        }

        // Some DIMSE tools use a positional host:port argument:
        //   dicom-echo <host:port> --aet ...
        //   dicom-query <host:port> --aet ...
        //   dicom-send <host:port> --aet ... <files>
        //   dicom-retrieve <host:port> --aet ...
        //   dicom-qr <host:port> --aet ...
        //   dicom-mwl <host:port> --aet ...
        //   dicom-mpps <host:port> --aet ...
        // Keep host/port fields in the UI for convenience, but suppress their flag
        // form in the command preview — combine them into a single positional token instead.
        let usesPositionalEndpoint = toolName == "dicom-echo" || toolName == "dicom-query"
            || toolName == "dicom-send" || toolName == "dicom-retrieve"
            || toolName == "dicom-qr" || toolName == "dicom-mwl"
            || toolName == "dicom-mpps"
        var skipParameterIDs: Set<String> = []
        if usesPositionalEndpoint {
            let hostValue = parameterValues.first(where: { $0.parameterID == "host" })?.stringValue ?? ""
            let portValueRaw = parameterValues.first(where: { $0.parameterID == "port" })?.stringValue ?? ""
            let defaultPort = parameterDefinitions.first(where: { $0.id == "port" })?.defaultValue ?? ""
            let effectivePort = portValueRaw.isEmpty ? defaultPort : portValueRaw

            if !hostValue.isEmpty {
                let endpoint: String
                if hostValue.contains(":") || effectivePort.isEmpty {
                    endpoint = hostValue
                } else {
                    endpoint = "\(hostValue):\(effectivePort)"
                }
                parts.append(shellEscape(endpoint))
            }

            skipParameterIDs = ["host", "port"]
        }

        // Collect mapped tokens from internal parameters (e.g. --subscribe, --uri)
        // and defer them until after the first positional argument (URL) so the
        // command reads: `tool subcommand <url> --flag ...` not `tool subcommand --flag <url> ...`
        var deferredMappedTokens: [String] = []
        var positionalSeen = false

        // Iterate in definition order so the command preview matches the canonical parameter order
        for def in parameterDefinitions {
            if skipParameterIDs.contains(def.id) {
                continue
            }
            // Internal parameters with a cliMapping emit mapped CLI tokens
            if def.isInternal {
                if !def.cliMapping.isEmpty {
                    let value = parameterValues.first(where: { $0.parameterID == def.id })?.stringValue ?? ""
                    let effective = value.isEmpty ? def.defaultValue : value
                    if let mapped = def.cliMapping[effective], !mapped.isEmpty {
                        if positionalSeen {
                            parts.append(mapped)
                        } else {
                            deferredMappedTokens.append(mapped)
                        }
                    }
                }
                continue
            }
            // Skip parameters whose visibility conditions are not met
            guard isVisible(def, parameterValues: parameterValues,
                            parameterDefinitions: parameterDefinitions) else { continue }
            guard let value = parameterValues.first(where: { $0.parameterID == def.id }) else { continue }
            guard !value.stringValue.isEmpty else { continue }
            switch def.parameterType {
            case .booleanToggle:
                if value.stringValue == "true" {
                    parts.append(def.flag)
                } else if value.stringValue == "false", let negated = def.negatedFlag, !negated.isEmpty {
                    // Inverted CLI flag (`@Flag(inversion: .prefixedNo)`, default
                    // true): toggling OFF must emit the negated token (e.g.
                    // `--no-recursive`) — omitting it would make the pasted
                    // command silently re-enable the disabled behavior.
                    parts.append(negated)
                }
            case .flagPicker:
                // Flag pickers emit "--<value>" (e.g. "--auto") instead of "--flag value".
                // A cliMapping entry overrides the literal token when the in-app state
                // executes as a different CLI mode (e.g. dicom-qr's "interactive" state
                // cannot prompt in-app — it retrieves all matches, so it previews as
                // the truthful --auto).
                if let mapped = def.cliMapping[value.stringValue], !mapped.isEmpty {
                    parts.append(mapped)
                } else {
                    parts.append("--\(value.stringValue)")
                }
            case .filePath, .outputPath:
                if def.flag.isEmpty {
                    // Positional argument(s). A repeatable definition models a
                    // variadic positional list (`@Argument var x: [String]`) —
                    // emit one escaped token per semicolon-separated item so the
                    // pasted command carries every path, not one joined token.
                    let tokens = def.isRepeatable
                        ? splitMultiValue(value.stringValue).map { shellEscape($0) }
                        : [shellEscape(value.stringValue)]
                    parts.append(contentsOf: tokens)
                    // Flush deferred internal tokens after positional arg (URL)
                    if !positionalSeen && !tokens.isEmpty {
                        positionalSeen = true
                        parts.append(contentsOf: deferredMappedTokens)
                        deferredMappedTokens.removeAll()
                    }
                } else {
                    parts.append(def.flag)
                    parts.append(shellEscape(value.stringValue))
                }
            case .subcommand:
                // Subcommands are positional — insert right after the tool name (index 1)
                if !value.stringValue.isEmpty {
                    parts.insert(value.stringValue, at: 1)
                }
            default:
                if def.flag.isEmpty {
                    // Positional argument(s) — same variadic expansion as the
                    // .filePath/.outputPath branch above (e.g. `dicom-uid
                    // validate <uid> <uid> …`).
                    let tokens = def.isRepeatable
                        ? splitMultiValue(value.stringValue).map { shellEscape($0) }
                        : [shellEscape(value.stringValue)]
                    parts.append(contentsOf: tokens)
                    // Flush deferred internal tokens after positional arg (URL)
                    if !positionalSeen && !tokens.isEmpty {
                        positionalSeen = true
                        parts.append(contentsOf: deferredMappedTokens)
                        deferredMappedTokens.removeAll()
                    }
                } else if def.isRepeatable {
                    // Repeatable CLI option: the real CLI declares this as an
                    // array and consumes one value per flag occurrence. The UI
                    // collects several values in one semicolon-separated field;
                    // expand it into `--flag A --flag B` so the previewed command
                    // behaves identically when pasted into a terminal — and
                    // matches the in-app executor, which splits the same way.
                    for item in splitMultiValue(value.stringValue) {
                        parts.append(def.flag)
                        parts.append(shellEscape(item))
                    }
                } else {
                    parts.append(def.flag)
                    parts.append(shellEscape(value.stringValue))
                }
            }
        }
        // Append any remaining deferred tokens (if no positional arg was seen)
        parts.append(contentsOf: deferredMappedTokens)
        return parts.joined(separator: " ")
    }

    /// The delimiter that separates multiple values in a repeatable-option UI
    /// field. A **semicolon** is used rather than a comma because DICOM values
    /// already contain commas and spaces: a tag *number* is written `GGGG,EEEE`
    /// (the comma is part of the value) and a tag *name* contains spaces and
    /// apostrophes (e.g. `Patient's Name`). A semicolon appears in none of those,
    /// so each value can be typed verbatim without being mis-split.
    public static let multiValueSeparator: Character = ";"

    /// Splits a semicolon-separated multi-value UI field into individual values,
    /// trimming surrounding whitespace and dropping empties.
    ///
    /// Shared by `buildCommand()` (to emit one repeated flag per value) and by
    /// the in-app executor (to parse the same field), so the command preview and
    /// the in-app result always agree with the real CLI's repeated-flag contract.
    ///
    /// Examples:
    /// - `"Patient's Name; 0008,0060"`          -> `["Patient's Name", "0008,0060"]`
    /// - `"SOPInstanceUID; 0008,0012"`          -> `["SOPInstanceUID", "0008,0012"]`
    /// - `"Name=DOE^JOHN; 0008,0090=DR.SMITH"`  -> `["Name=DOE^JOHN", "0008,0090=DR.SMITH"]`
    public static func splitMultiValue(_ raw: String) -> [String] {
        raw.split(separator: multiValueSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Shell-escapes a file path.
    public static func shellEscape(_ path: String) -> String {
        if path.contains(" ") || path.contains("'") || path.contains("\"") {
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return path
    }

    /// Evaluates one visibility condition against the current values, falling back to
    /// the referenced parameter's default when the user has not set it yet.
    public static func satisfies(
        _ condition: CLIParameterVisibilityCondition,
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition]
    ) -> Bool {
        let currentValue = parameterValues.first(where: { $0.parameterID == condition.parameterId })?.stringValue ?? ""
        let effectiveValue = currentValue.isEmpty
            ? parameterDefinitions.first(where: { $0.id == condition.parameterId })?.defaultValue ?? ""
            : currentValue
        return condition.values.contains(effectiveValue)
    }

    /// Whether `def` is currently visible: its ``CLIParameterDefinition/visibleWhen`` and
    /// every ``CLIParameterDefinition/visibleWhenAll`` condition must hold.
    ///
    /// Command-preview, required-field validation, and the ViewModel's form rendering all
    /// route through this one predicate — a hidden parameter must never emit a CLI flag
    /// nor block the Run button, and three hand-rolled copies of the rule would drift.
    ///
    /// Visibility is **transitive**: a condition on a parameter that is itself hidden cannot
    /// hold. ``satisfies`` falls back to the referenced parameter's `defaultValue` when the
    /// user has not set it, so a hidden controller still reports its default and would
    /// otherwise leak its dependents into unrelated forms — e.g. dicom-mwl's `create-method`
    /// (visible only for `operation == create`, default `hl7`) made the HL7 Port and the
    /// MSH-3…MSH-6 fields appear under the `query` form, which speaks DIMSE and has no HL7
    /// leg at all. Requiring the controller to be visible too keeps a chained condition
    /// anchored to the branch that introduced it.
    public static func isVisible(
        _ def: CLIParameterDefinition,
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition]
    ) -> Bool {
        isVisible(def, parameterValues: parameterValues,
                  parameterDefinitions: parameterDefinitions, visiting: [])
    }

    /// Transitive visibility check. `visiting` carries the ids already being resolved on the
    /// current chain so a malformed spec with a circular dependency terminates (treating the
    /// cycle as satisfied) instead of recursing until the stack overflows.
    private static func isVisible(
        _ def: CLIParameterDefinition,
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition],
        visiting: Set<String>
    ) -> Bool {
        guard !visiting.contains(def.id) else { return true }
        let chain = visiting.union([def.id])

        let holds: (CLIParameterVisibilityCondition) -> Bool = { condition in
            guard satisfies(condition, parameterValues: parameterValues,
                            parameterDefinitions: parameterDefinitions) else { return false }
            // The referenced parameter must itself be reachable in the current form.
            guard let controller = parameterDefinitions.first(where: { $0.id == condition.parameterId })
            else { return true }
            return isVisible(controller, parameterValues: parameterValues,
                             parameterDefinitions: parameterDefinitions, visiting: chain)
        }

        if let condition = def.visibleWhen, !holds(condition) { return false }
        return def.visibleWhenAll.allSatisfy(holds)
    }

    /// Validates that all required parameters have values.
    public static func validateRequired(
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition]
    ) -> Bool {
        let requiredDefs = parameterDefinitions.filter { $0.isRequired }
        for def in requiredDefs {
            // Skip required parameters that are conditionally hidden
            guard isVisible(def, parameterValues: parameterValues,
                            parameterDefinitions: parameterDefinitions) else { continue }
            guard let val = parameterValues.first(where: { $0.parameterID == def.id }) else { return false }
            if val.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        }
        return true
    }

    /// Returns the list of missing required parameter display names.
    public static func missingRequiredParameters(
        parameterValues: [CLIParameterValue],
        parameterDefinitions: [CLIParameterDefinition]
    ) -> [String] {
        let requiredDefs = parameterDefinitions.filter { $0.isRequired }
        var missing: [String] = []
        for def in requiredDefs {
            let val = parameterValues.first(where: { $0.parameterID == def.id })
            if val == nil || val!.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                missing.append(def.displayName)
            }
        }
        return missing
    }

    /// Tokenizes a command string for syntax highlighting.
    public static func tokenize(_ command: String) -> [CLISyntaxToken] {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true)
        var tokens: [CLISyntaxToken] = []
        for (index, part) in parts.enumerated() {
            let text = String(part)
            let tokenType: CLISyntaxTokenType
            if index == 0 {
                tokenType = .toolName
            } else if text.hasPrefix("--") || text.hasPrefix("-") {
                tokenType = .flag
            } else if text.contains("/") || text.contains(".dcm") || text.contains(".dicom") {
                tokenType = .path
            } else {
                tokenType = .value
            }
            tokens.append(CLISyntaxToken(text: text, tokenType: tokenType))
        }
        return tokens
    }
}

// MARK: - 16.4 File Drop Helpers

/// Helpers for file drop zone logic.
public enum FileDropHelpers: Sendable {

    /// Validates whether a filename has a DICOM-compatible extension.
    public static func isDICOMFile(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return lower.hasSuffix(".dcm") || lower.hasSuffix(".dicom") || lower.hasSuffix(".dic") || !lower.contains(".")
    }

    /// Formats a file size in bytes to a human-readable string.
    public static func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }

    /// Returns a brief summary for a list of files.
    public static func fileSummary(_ files: [CLIFileEntry]) -> String {
        switch files.count {
        case 0:  return "No files selected"
        case 1:  return files[0].filename
        default: return "\(files.count) files selected"
        }
    }
}

// MARK: - 16.5 Console Helpers

/// Helpers for CLI console display and PHI redaction.
public enum ConsoleHelpers: Sendable {

    /// Maximum number of commands to retain in history.
    public static let maxHistoryCount: Int = 50

    /// Redacts potential PHI from a command string.
    public static func redactPHI(_ command: String) -> String {
        var result = command
        // Redact patterns that look like patient names (--patient-name "...")
        let namePattern = #"(--patient[_-]?name\s+)("[^"]*"|'[^']*'|\S+)"#
        if let regex = try? NSRegularExpression(pattern: namePattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1<redacted>"
            )
        }
        // Redact patient IDs
        let idPattern = #"(--patient[_-]?id\s+)("[^"]*"|'[^']*'|\S+)"#
        if let regex = try? NSRegularExpression(pattern: idPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1<redacted>"
            )
        }
        // Redact OAuth2 tokens
        let tokenPattern = #"(--token\s+|--oauth[_-]?token\s+)("[^"]*"|'[^']*'|\S+)"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1<redacted>"
            )
        }
        return result
    }

    /// Formats a timestamp for display in command history.
    public static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    /// Trims history to the maximum count, removing oldest entries.
    public static func trimHistory(_ history: [CLICommandHistoryEntry]) -> [CLICommandHistoryEntry] {
        if history.count <= maxHistoryCount { return history }
        return Array(history.suffix(maxHistoryCount))
    }
}

// MARK: - 16.8 Educational Helpers

/// Helpers for educational features like glossary and example presets.
public enum EducationalHelpers: Sendable {

    /// Returns sample DICOM glossary entries.
    public static func defaultGlossaryEntries() -> [CLIGlossaryEntry] {
        [
            CLIGlossaryEntry(term: "AE Title", definition: "Application Entity Title — a unique identifier (up to 16 characters) for a DICOM application on the network.", standardReference: "PS3.8"),
            CLIGlossaryEntry(term: "SOP Class", definition: "Service-Object Pair Class — defines the type of DICOM object and the services that can operate on it.", standardReference: "PS3.4"),
            CLIGlossaryEntry(term: "Transfer Syntax", definition: "Defines how DICOM data is encoded, including byte order, VR encoding, and pixel data compression.", standardReference: "PS3.5"),
            CLIGlossaryEntry(term: "IOD", definition: "Information Object Definition — a data model specifying the attributes of a real-world object (e.g., CT Image).", standardReference: "PS3.3"),
            CLIGlossaryEntry(term: "DICOMDIR", definition: "A directory file that indexes the contents of DICOM media (e.g., CD/DVD).", standardReference: "PS3.10"),
            CLIGlossaryEntry(term: "C-ECHO", definition: "DICOM verification service — tests network connectivity between two DICOM nodes.", standardReference: "PS3.7"),
            CLIGlossaryEntry(term: "C-FIND", definition: "DICOM query service — searches for studies, series, or images on a remote PACS.", standardReference: "PS3.4"),
            CLIGlossaryEntry(term: "C-STORE", definition: "DICOM storage service — sends DICOM objects to a remote storage SCP.", standardReference: "PS3.4"),
            CLIGlossaryEntry(term: "C-MOVE", definition: "DICOM retrieval service — instructs a PACS to send objects to a specified destination.", standardReference: "PS3.4"),
            CLIGlossaryEntry(term: "C-GET", definition: "DICOM retrieval service — retrieves objects directly over the existing association.", standardReference: "PS3.4"),
            CLIGlossaryEntry(term: "VR", definition: "Value Representation — the data type of a DICOM attribute (e.g., DA for Date, PN for Person Name).", standardReference: "PS3.5"),
            CLIGlossaryEntry(term: "UID", definition: "Unique Identifier — a globally unique string identifying DICOM objects, classes, and transfer syntaxes.", standardReference: "PS3.5"),
            CLIGlossaryEntry(term: "WADO-RS", definition: "Web Access to DICOM Objects using RESTful Services — retrieve DICOM data over HTTP.", standardReference: "PS3.18"),
            CLIGlossaryEntry(term: "QIDO-RS", definition: "Query based on ID for DICOM Objects using RESTful Services — search for DICOM data over HTTP.", standardReference: "PS3.18"),
            CLIGlossaryEntry(term: "STOW-RS", definition: "Store Over the Web using RESTful Services — upload DICOM data over HTTP.", standardReference: "PS3.18"),
        ]
    }

    /// Filters glossary entries by a search query.
    public static func filterGlossary(_ entries: [CLIGlossaryEntry], query: String) -> [CLIGlossaryEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter {
            $0.term.lowercased().contains(lower) ||
            $0.definition.lowercased().contains(lower)
        }
    }

    /// Returns example command presets for a given tool.
    public static func examplePresets(for toolID: String) -> [CLIExamplePreset] {
        switch toolID {
        case "dicom-info":
            return [
                CLIExamplePreset(toolID: toolID, title: "Basic File Info",
                                 presetDescription: "Display metadata in text format",
                                 commandString: "dicom-info scan.dcm"),
                CLIExamplePreset(toolID: toolID, title: "JSON Output with Statistics",
                                 presetDescription: "Output metadata as JSON with file statistics",
                                 commandString: "dicom-info --format json --statistics scan.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Filter Specific Tags",
                                 presetDescription: "Show only PatientName and StudyDate",
                                 commandString: "dicom-info --tag PatientName --tag StudyDate scan.dcm"),
                CLIExamplePreset(toolID: toolID, title: "CSV Export",
                                 presetDescription: "Export all tags (including private) as CSV",
                                 commandString: "dicom-info --format csv --show-private scan.dcm"),
            ]
        case "dicom-dump":
            return [
                CLIExamplePreset(toolID: toolID, title: "Full Hex Dump",
                                 presetDescription: "Dump entire file with tag annotations",
                                 commandString: "dicom-dump file.dcm --annotate"),
                CLIExamplePreset(toolID: toolID, title: "Dump Specific Tag",
                                 presetDescription: "Dump only the pixel data element bytes",
                                 commandString: "dicom-dump file.dcm --tag 7FE0,0010"),
                CLIExamplePreset(toolID: toolID, title: "Dump with Offset & Length",
                                 presetDescription: "Dump 256 bytes starting at offset 0x1000",
                                 commandString: "dicom-dump file.dcm --offset 0x1000 --length 256"),
                CLIExamplePreset(toolID: toolID, title: "Verbose Annotated Dump",
                                 presetDescription: "Full dump with VR and length details",
                                 commandString: "dicom-dump file.dcm --annotate --verbose"),
            ]
        case "dicom-tags":
            return [
                CLIExamplePreset(toolID: toolID, title: "Set Patient Name",
                                 presetDescription: "Modify PatientName tag and save to new file",
                                 commandString: "dicom-tags file.dcm --set PatientName=DOE^JOHN --output modified.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Delete Tags",
                                 presetDescription: "Remove PatientBirthDate and AccessionNumber",
                                 commandString: "dicom-tags file.dcm --delete PatientBirthDate --delete AccessionNumber"),
                CLIExamplePreset(toolID: toolID, title: "Delete Private Tags",
                                 presetDescription: "Strip all private (odd-group) tags",
                                 commandString: "dicom-tags file.dcm --delete-private --output clean.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Dry Run Preview",
                                 presetDescription: "Preview changes without writing files",
                                 commandString: "dicom-tags file.dcm --set StudyDescription=Research --delete AccessionNumber --dry-run"),
            ]
        case "dicom-diff":
            return [
                CLIExamplePreset(toolID: toolID, title: "Basic Comparison",
                                 presetDescription: "Compare metadata of two DICOM files",
                                 commandString: "dicom-diff file1.dcm file2.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Compare with Pixels",
                                 presetDescription: "Compare both metadata and pixel data",
                                 commandString: "dicom-diff --compare-pixels --tolerance 5 original.dcm processed.dcm"),
                CLIExamplePreset(toolID: toolID, title: "JSON Output",
                                 presetDescription: "Output differences as JSON, ignoring instance UIDs",
                                 commandString: "dicom-diff --ignore-tag SOPInstanceUID --format json file1.dcm file2.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Quick Summary",
                                 presetDescription: "Fast metadata-only summary comparison",
                                 commandString: "dicom-diff --quick --format summary file1.dcm file2.dcm"),
            ]
        case "dicom-echo":
            return [
                CLIExamplePreset(toolID: toolID, title: "Basic Echo Test",
                                 presetDescription: "Test connectivity to a PACS server",
                                 commandString: "dicom-echo pacs.example.com:11112 --aet STUDIO --called-aet PACS"),
                CLIExamplePreset(toolID: toolID, title: "Echo with Stats",
                                 presetDescription: "Send 10 echoes and show round-trip statistics",
                                 commandString: "dicom-echo pacs.example.com:11112 --aet STUDIO --count 10 --stats"),
            ]
        case "dicom-anon":
            return [
                CLIExamplePreset(toolID: toolID, title: "Legacy Basic Anonymization",
                                 presetDescription: "Anonymize with the legacy basic attribute list (not the PS3.15 Basic Profile, which is dicom-anon's default ps315)",
                                 commandString: "dicom-anon --profile legacy-basic --output /output/ scan.dcm"),
                CLIExamplePreset(toolID: toolID, title: "Dry Run Preview",
                                 presetDescription: "Preview anonymization changes without writing files",
                                 commandString: "dicom-anon --profile legacy-basic --dry-run scan.dcm"),
            ]
        case "dicom-convert":
            return [
                CLIExamplePreset(toolID: toolID, title: "Convert to Explicit VR Little Endian",
                                 presetDescription: "Re-encode a DICOM file with Explicit VR Little Endian transfer syntax",
                                 commandString: "dicom-convert scan.dcm --output converted.dcm --format dicom --transfer-syntax ExplicitVRLittleEndian"),
                CLIExamplePreset(toolID: toolID, title: "Export as PNG with Windowing",
                                 presetDescription: "Export pixel data as PNG with custom window/level for CT",
                                 commandString: "dicom-convert ct.dcm --output ct.png --format png --apply-window --window-center 40 --window-width 400"),
                CLIExamplePreset(toolID: toolID, title: "Export as JPEG (High Quality)",
                                 presetDescription: "Export pixel data as high-quality JPEG image",
                                 commandString: "dicom-convert xray.dcm --output xray.jpg --format jpeg --quality 95"),
                CLIExamplePreset(toolID: toolID, title: "Batch Convert Directory",
                                 presetDescription: "Recursively convert all files in a directory to Implicit VR",
                                 commandString: "dicom-convert input/ --output output/ --format dicom --transfer-syntax ImplicitVRLittleEndian --recursive"),
            ]
        case "dicom-query":
            return [
                CLIExamplePreset(toolID: toolID, title: "Query Studies by Modality",
                                 presetDescription: "Find all CT studies on the PACS",
                                 commandString: "dicom-query pacs.example.com:11112 --aet STUDIO --modality CT"),
                CLIExamplePreset(toolID: toolID, title: "Query by Patient Name",
                                 presetDescription: "Search for studies by patient name with wildcards",
                                 commandString: "dicom-query pacs.example.com:11112 --aet STUDIO --patient-name \"SMITH*\" --format json"),
            ]
        default:
            return []
        }
    }

    /// Returns the total number of glossary entries.
    public static var defaultGlossaryCount: Int { defaultGlossaryEntries().count }

    // MARK: - DICOM Tag Formatting

    /// Formats a raw 8-character tag string into (GGGG,EEEE) format.
    public static func formatTag(_ tag: String) -> String {
        guard tag.count == 8 else { return tag }
        let group = tag.prefix(4)
        let element = tag.suffix(4)
        return "\(group),\(element)"
    }

    /// Lookup table for common DICOM tag names used in UPS.
    private static let tagNames: [String: String] = [
        "00080016": "SOP Class UID",
        "00080018": "SOP Instance UID",
        "00080050": "Accession Number",
        "00080090": "Referring Physician",
        "00080100": "Code Value",
        "00080102": "Coding Scheme Designator",
        "00080104": "Code Meaning",
        "00081110": "Referenced Study Sequence",
        "00081150": "Referenced SOP Class UID",
        "00081155": "Referenced SOP Instance UID",
        "00081195": "Transaction UID",
        "00100010": "Patient's Name",
        "00100020": "Patient ID",
        "00100030": "Patient's Birth Date",
        "00100040": "Patient's Sex",
        "0020000D": "Study Instance UID",
        "0020000E": "Series Instance UID",
        "00321060": "Requested Procedure Description",
        "00400009": "Scheduled Procedure Step ID",
        "00400400": "Comments on Scheduled Procedure Step",
        "0040A370": "Referenced Request Sequence",
        "00401001": "Requested Procedure ID",
        "00404005": "Scheduled Procedure Step Start DateTime",
        "00404010": "Scheduled Procedure Step Modification DateTime",
        "00404011": "Expected Completion DateTime",
        "00404018": "Scheduled Workitem Code Sequence",
        "00404021": "Input Information Sequence",
        "00404025": "Scheduled Station Name Code Sequence",
        "00404026": "Scheduled Station Class Code Sequence",
        "00404027": "Scheduled Station Geographic Location Code Sequence",
        "00404033": "Output Information Sequence",
        "00404034": "Scheduled Human Performers Sequence",
        "00404035": "Actual Human Performers Sequence",
        "00404009": "Human Performer Code Sequence",
        "00404036": "Human Performer's Organization",
        "00404037": "Human Performer's Name",
        "00404041": "Input Readiness State",
        "00404052": "Procedure Step Cancellation DateTime",
        "00741000": "Procedure Step State",
        "00741002": "Procedure Step Progress Information Sequence",
        "0074100A": "Contact URI",
        "0074100C": "Contact Display Name",
        "00741004": "Procedure Step Progress",
        "00741006": "Procedure Step Progress Description",
        "00741200": "Scheduled Procedure Step Priority",
        "00741202": "Worklist Label",
        "00741204": "Procedure Step Label",
        "00741210": "Scheduled Processing Parameters Sequence",
        "0074100E": "Procedure Step Discontinuation Reason Code Sequence",
        "00741236": "Requesting AE",
        "00741238": "Reason for Cancellation",
    ]

    /// Returns a human-readable name for a DICOM tag, or the raw tag if unknown.
    public static func dicomTagName(for tag: String) -> String {
        return tagNames[tag.uppercased()] ?? tag
    }
}

// MARK: - dicom-convert --transfer-syntax picker spelling

/// The Workshop picker's spelling of a dicom-convert `--transfer-syntax` value. Resolution, the
/// PS3.6 2026a Table A-1 keywords and the option help are DICOMKit's (`DICOMConverter
/// .resolveTargetEncoding`, `.additionalTableA1Keywords`, `.transferSyntaxOptionHelpWithKeywords`,
/// D268), the same calls dicom-convert makes; this only maps a typed value onto a picker entry.
enum WorkshopConvertPicker {

    /// The picker's spelling (the catalog's CamelCase cliToken) of any accepted `--transfer-syntax`
    /// token — a kebab alias (`jpeg2000-lossless`), a UID or a Table A-1 keyword — so a value saved
    /// or typed in another spelling shows as the picker's entry. Unknown tokens are returned as
    /// given (the executor then prints the CLI's refusal). A reassigned keyword
    /// (`JPEG2000Lossless`) is kept as typed, so the executor still prints the CLI's note for it.
    static func canonicalToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        if DICOMConverter.cliTokens.contains(trimmed) { return trimmed }
        if TransferSyntax.reassignedTableA1Keywords.contains(where: { $0.keyword.lowercased() == trimmed.lowercased() }) {
            return trimmed
        }
        guard let encoding = DICOMConverter.resolveTargetEncoding(trimmed),
              let target = DICOMConverter.targets.first(where: { $0.encoding == encoding }) else { return raw }
        return target.cliToken
    }
}

