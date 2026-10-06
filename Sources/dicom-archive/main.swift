// NEMA-verified: 2026a, checked 2026-10-01 — option help names the PS3.6 2026a Table 6-1 attributes each key matches (Patient's Name (0010,0010), Patient ID (0010,0020), Study Instance UID (0020,000D), Series Instance UID (0020,000E), Study Date (0008,0020), Modality (0008,0060), Modalities in Study (0008,0061), SOP Instance UID (0008,0018); all match) and the PS3.4 2026a C.2.2.2 matching the shared DICOMKit ArchiveStore performs (Wild Card C.2.2.2.4 case-sensitive except PN, List of UID C.2.2.2.2, DA Range C.2.2.2.5.1); a Study Date that is neither a DA value nor a DA range is warned
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

// The archive index model, helpers, and every operation now live in the DICOMKit
// library (Sources/DICOMKit/Archive/ArchiveStore.swift) so the CLI and DICOMStudio
// run the exact same code. This CLI is a thin adapter: parse argv, call the shared
// ArchiveStore operation, and print the rendered output.

// Run a shared ArchiveStore operation and print its output, re-raising the
// library's `ArchiveError` as ArgumentParser's `ValidationError` so the CLI's
// error message, usage hint, and exit code match its pre-extraction behavior.
private func runArchive(_ body: () throws -> String) throws {
    do {
        print(try body(), terminator: "")
    } catch let error as ArchiveError {
        throw ValidationError(error.errorDescription ?? "\(error)")
    }
}

// MARK: - Main Command

struct DICOMArchive: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-archive",
        abstract: "Local DICOM file archive manager",
        discussion: """
            Manage a local archive of DICOM files with a JSON-based metadata index.
            Files are stored as data/<Patient ID>/<Study Instance UID>/<Series Instance UID>/
            <SOP Instance UID>.dcm and deduplicated by SOP Instance UID (0008,0018).

            Query keys match like a DICOM C-FIND (PS3.4 C.2.2.2): * and ? wild cards
            (C.2.2.2.4) are case-sensitive except for Patient's Name; Study Date takes a
            single date or a range (YYYYMMDD-YYYYMMDD, -YYYYMMDD, YYYYMMDD-; C.2.2.2.5.1);
            UID keys take one UID or a backslash-separated list (C.2.2.2.2). Patients are
            keyed on Patient ID together with Issuer of Patient ID (0010,0021).

            Examples:
              # Initialize a new archive
              dicom-archive init --path /data/archive

              # Import DICOM files
              dicom-archive import file1.dcm file2.dcm --archive /data/archive

              # Query archive metadata
              dicom-archive query --archive /data/archive --patient-name "DOE*"

              # List archive contents
              dicom-archive list --archive /data/archive

              # Export files from archive
              dicom-archive export --archive /data/archive --study-uid 1.2.3 --output /tmp/out

              # Check archive integrity
              dicom-archive check --archive /data/archive

              # Show archive statistics
              dicom-archive stats --archive /data/archive
            """,
        version: "1.2.1",
        subcommands: [
            Init.self,
            Import.self,
            Query.self,
            List.self,
            Export.self,
            Check.self,
            Stats.self
        ]
    )
}

// MARK: - Init Subcommand

extension DICOMArchive {
    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Initialize a new DICOM archive"
        )

        @Option(name: .shortAndLong, help: "Path for the new archive directory")
        var path: String

        @Flag(name: .long, help: "Overwrite existing archive")
        var force: Bool = false

        mutating func run() throws {
            try runArchive { try ArchiveStore.initArchive(at: path, force: force) }
        }
    }
}

// MARK: - Import Subcommand

extension DICOMArchive {
    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Import DICOM files into the archive"
        )

        @Argument(help: "DICOM files or directories to import")
        var files: [String]

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Flag(name: .long, help: "Recursive import from directories")
        var recursive: Bool = false

        @Flag(name: .long, help: "Skip duplicate SOP Instance UIDs without error")
        var skipDuplicates: Bool = false

        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false

        mutating func run() throws {
            try runArchive { try ArchiveStore.importFiles(
                into: archive, files: files, recursive: recursive,
                skipDuplicates: skipDuplicates, verbose: verbose) }
        }
    }
}

// MARK: - Query Subcommand

extension DICOMArchive {
    struct Query: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "query",
            abstract: "Query archive metadata"
        )

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Option(name: .long, help: "Filter by Patient's Name (0010,0010); * and ? wild cards (PS3.4 C.2.2.2.4), case-insensitive")
        var patientName: String?

        @Option(name: .long, help: "Filter by Patient ID (0010,0020); * and ? wild cards, case-sensitive (PS3.4 C.2.2.2.4)")
        var patientID: String?

        @Option(name: .long, help: "Filter by Study Instance UID (0020,000D); one UID or a backslash-separated list (PS3.4 C.2.2.2.2)")
        var studyUID: String?

        @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("filter")
            + " A study matches when any of its series has it (Modalities in Study (0008,0061))."))
        var modality: String?

        @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
        var strictModality: Bool = false

        @Option(name: .long, help: "Filter by Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD, YYYYMMDD- (PS3.4 C.2.2.2.5.1)")
        var studyDate: String?

        @Option(name: .shortAndLong, help: "Output format: table, json, text. JSON adds ModalitiesInStudy, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances (PS3.6 keywords); modality, seriesCount, imageCount are deprecated")
        var format: String = "table"

        mutating func run() throws {
            // One answer to "is that a modality?" across every dicom-* tool.
            modality = try ModalityOptionValidator.resolve(
                modality, strict: strictModality)
            ArchiveQueryKeys.printWarnings([ArchiveMatching.studyDateKeyWarning(studyDate)])

            try runArchive { try ArchiveStore.query(
                in: archive, patientName: patientName, patientID: patientID,
                studyUID: studyUID, modality: modality, studyDate: studyDate,
                format: format) }
        }
    }
}

// MARK: - List Subcommand

extension DICOMArchive {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List archive contents"
        )

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Option(name: .shortAndLong, help: "Output format: tree, table, json")
        var format: String = "tree"

        @Flag(name: .long, help: "Show individual instances")
        var showInstances: Bool = false

        mutating func run() throws {
            try runArchive { try ArchiveStore.list(in: archive, format: format, showInstances: showInstances) }
        }
    }
}

// MARK: - Export Subcommand

extension DICOMArchive {
    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Export files from the archive"
        )

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Option(name: .shortAndLong, help: "Output directory for exported files")
        var output: String

        @Option(name: .long, help: "Export by Study Instance UID (0020,000D); one UID or a backslash-separated list (PS3.4 C.2.2.2.2)")
        var studyUID: String?

        @Option(name: .long, help: "Export by Series Instance UID (0020,000E); one UID or a backslash-separated list (PS3.4 C.2.2.2.2)")
        var seriesUID: String?

        @Option(name: .long, help: "Export by Patient ID (0010,0020); exact match, no wild cards")
        var patientID: String?

        @Flag(name: .long, help: "Flatten output to <SOP Instance UID>.dcm (no Patient ID / Study / Series subdirectories)")
        var flatten: Bool = false

        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false

        mutating func run() throws {
            try runArchive { try ArchiveStore.export(
                from: archive, output: output, studyUID: studyUID, seriesUID: seriesUID,
                patientID: patientID, flatten: flatten, verbose: verbose) }
        }
    }
}

// MARK: - Check Subcommand

extension DICOMArchive {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Check archive integrity"
        )

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Flag(name: .long, help: "Verify DICOM file readability")
        var verifyFiles: Bool = false

        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false

        mutating func run() throws {
            try runArchive { try ArchiveStore.check(in: archive, verifyFiles: verifyFiles, verbose: verbose) }
        }
    }
}

// MARK: - Stats Subcommand

extension DICOMArchive {
    struct Stats: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stats",
            abstract: "Show archive statistics"
        )

        @Option(name: .shortAndLong, help: "Path to the archive")
        var archive: String

        @Option(name: .shortAndLong, help: "Output format: text, json")
        var format: String = "text"

        mutating func run() throws {
            try runArchive { try ArchiveStore.stats(in: archive, format: format) }
        }
    }
}

DICOMArchive.main()
