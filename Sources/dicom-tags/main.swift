// NEMA-verified: 2026a, checked 2026-10-01 — tag specifiers resolve PS3.6 2026a Table 6-1/7-1 keywords exactly (case-sensitive) or (gggg,eeee); --set writes the dictionary VR within PS3.5 Table 6.2-1 limits and group 0002 is refused per PS3.10 7.1, both by the shared DICOMKit TagEditor/TagEditRules (D150); --list-modalities = PS3.3 C.7.3.1.1.1 (79 current terms match, 18 retired not listed)
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary

// The tag-editing engine (`TagEditor`) and `TagEditorError` now live in the
// DICOMKit library so the CLI and DICOMStudio run the exact same code. This CLI
// is a thin adapter: parse argv → read file(s) → TagEditor.applyChanges → print
// → write.
@available(macOS 10.15, *)
struct DICOMTags: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-tags",
        abstract: "Add, modify, and delete tags in DICOM files",
        discussion: """
            Manipulate DICOM tags by setting values, deleting tags, removing private tags,
            or copying tags from another DICOM file. A tag is given by its PS3.6 keyword
            (e.g., PatientName, exact case) or as GGGG,EEEE (e.g., 0010,0010).

            --set writes the PS3.6 dictionary VR and refuses a value outside the PS3.5
            Table 6.2-1 limits for that VR (length, characters, numeric range). US, SS, UL,
            SL, FL and FD values are given as decimal numbers, multiple values separated
            by a backslash. File Meta Information (group 0002) cannot be edited here: PS3.10
            7.1 keeps it out of the Data Set and the file writer sets it.

            Examples:
              dicom-tags file.dcm --set PatientName=DOE^JOHN
              dicom-tags file.dcm --set 0010,0010=DOE^JOHN --output modified.dcm
              dicom-tags file.dcm --delete PatientName --delete PatientBirthDate
              dicom-tags file.dcm --delete-private --output clean.dcm
              dicom-tags file.dcm --copy-from source.dcm --tags PatientName,PatientID
              dicom-tags file.dcm --set StudyDescription=Research --delete AccessionNumber --dry-run
              dicom-tags --list-modalities
            """,
        version: "1.3.1"
    )

    @Argument(help: "Input DICOM file path (omit with --list-modalities)")
    var input: String?

    @Flag(name: .long, help: "Print every DICOM Modality (0008,0060) defined term and exit")
    var listModalities: Bool = false

    @Option(name: .shortAndLong, help: "Output file path (defaults to overwrite input)")
    var output: String?

    @Option(name: .long, help: "Tag values to set (format: Keyword=Value or GGGG,EEEE=Value)")
    var set: [String] = []

    @Option(name: .long, help: "Tags to delete (by keyword or GGGG,EEEE)")
    var delete: [String] = []

    @Flag(name: .long, help: "Delete all private tags (odd group numbers)")
    var deletePrivate: Bool = false

    @Option(name: .long, help: "Copy tags from another DICOM file")
    var copyFrom: String?

    @Option(name: .long, help: "Comma-separated keywords or GGGG,EEEE tags to copy (used with --copy-from)")
    var tags: String?

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Show what would be changed without writing")
    var dryRun: Bool = false

    mutating func run() throws {
        if listModalities {
            print(ModalityOptionValidator.listing())
            return
        }
        guard let input else {
            throw ValidationError("Missing expected argument '<input>'")
        }
        guard FileManager.default.fileExists(atPath: input) else {
            throw TagEditorError.fileNotFound(input)
        }

        let copyTags: [String] = tags?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []

        if let copyFrom = copyFrom {
            guard FileManager.default.fileExists(atPath: copyFrom) else {
                throw TagEditorError.fileNotFound(copyFrom)
            }
        }

        if set.isEmpty && delete.isEmpty && !deletePrivate && copyFrom == nil {
            throw TagEditorError.noOperationsSpecified
        }

        // Read input + optional copy-from source.
        let dicomFile = try DICOMFile.read(from: try Data(contentsOf: URL(fileURLWithPath: input)))
        var dataSet = dicomFile.dataSet

        var sourceDataSet: DataSet?
        if let copyFrom = copyFrom {
            let sourceFile = try DICOMFile.read(from: try Data(contentsOf: URL(fileURLWithPath: copyFrom)))
            sourceDataSet = sourceFile.dataSet
        }

        // Deletes, private-tag removal, copies and sets via the shared DICOMKit engine,
        // which refuses (throws, before anything changes) an edit the standard does not
        // allow: group 0002, Items/delimiters, unused groups, or a --set value outside the
        // PS3.5 Table 6.2-1 limits of the VR it writes (TagEditRules, D150).
        let changes = try TagEditor().applyCheckedChanges(
            to: &dataSet,
            sets: set,
            deletes: delete,
            deletePrivate: deletePrivate,
            sourceDataSet: sourceDataSet,
            copyTags: copyTags,
            verbose: verbose,
            dryRun: dryRun
        )

        // Console lines via the SHARED TagEditConsole (DICOMKit) — the same
        // builders the Workshop executor uses, so app and CLI stay text-exact.
        fprint(TagEditConsole.changesBlock(changes, verbose: verbose, dryRun: dryRun))

        let destPath = OutputPathResolver.resolveFileOutput(output: output, input: input)
        if !dryRun {
            let modifiedFile = DICOMFile(fileMetaInformation: dicomFile.fileMetaInformation, dataSet: dataSet)
            let outputData = try modifiedFile.write()
            let destURL = URL(fileURLWithPath: destPath)
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try outputData.write(to: destURL)
        }

        fprint(TagEditConsole.completionLine(dryRun: dryRun, outputPath: destPath))
    }
}

private func fprint(_ message: String) {
    // Route the change preview / dry-run summary to STDOUT so the CLI and DICOMStudio
    // (which shows it in-console) are text-exact. These are results, not errors.
    // The shared TagEditConsole builders already terminate their lines.
    print(message, terminator: "")
}

DICOMTags.main()
