// NEMA-verified: 2026a, checked 2026-10-01 — --profile and the Option flags against PS3.15 2026a E.1-E.3 and the 12 Option columns of Table E.1-1 (all 12 Options offered — Retain Safe Private and Clean Graphics added 2026-10-01, Clean Structured Content (Table E.3.4-1) and Clean Recognizable Visual Features (E.3.2, operator --redact-region required, exit 1 without) added 2026-10-01, D159); on a fixture of the 647 data-set rows of Table E.1-1, --profile ps315 matches 647 (5 SQ D rows kept with scrubbed items) (the default; basic is its alias, P-ANON-PROFILE) and the deprecated legacy-basic 11, legacy-clinical-trial 15, legacy-research 1 (documented as not PS3.15); --retain-dates deprecated (P-ANON-RETAIN-DATES, E.3.6); recorded codes match PS3.16 2026a CID 7050 (13 rows); (0002,0003) follows (0008,0018) per PS3.10 2026a 7.1
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMAnon: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-anon",
        abstract: "Anonymize DICOM files by removing or replacing patient identifiers",
        discussion: """
            Anonymizes DICOM files according to various profiles to protect patient privacy.
            Supports multiple anonymization strategies and batch processing.

            --profile ps315 (the default; basic is an alias of it) applies the PS3.15 Basic
            Application Level Confidentiality Profile (every row of Table E.1-1) and the
            Options selected with the --retain-* and --clean-* flags, and records Patient
            Identity Removed (0012,0062), De-identification Method (0012,0063) and
            De-identification Method Code Sequence (0012,0064). The deprecated profiles
            legacy-basic, legacy-clinical-trial and legacy-research are fixed attribute
            lists, NOT the PS3.15 Basic Profile: legacy-basic removes or replaces 14
            attributes, legacy-clinical-trial adds 8 study/series/acquisition/content dates
            and times, legacy-research handles 3; none of them records (0012,0062). In
            earlier releases basic named the legacy-basic list; clinical-trial and research
            still select legacy-clinical-trial and legacy-research, with a deprecation note.

            --dry-run and --verbose list each changed attribute with its PS3.6 name and
            the PS3.15 Table E.1-1a action code (D, Z, X, C, U).

            Examples:
              dicom-anon file.dcm --output anon.dcm --profile ps315
              dicom-anon file.dcm --output anon.dcm --profile ps315 --retain-modified-dates --shift-dates -100
              dicom-anon file.dcm --output anon.dcm --profile ps315 --retain-uids --retain-device
              dicom-anon input_dir/ --output anon_dir/ --recursive
              dicom-anon file.dcm --output anon.dcm --remove 0010,0010 --replace 0010,0030=19700101
              dicom-anon file.dcm --dry-run
              dicom-anon file.dcm --output anon.dcm --audit-log anonymization.log
              dicom-anon file.dcm --output anon.dcm --profile legacy-basic --shift-dates 100
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "Path to DICOM file or directory")
    var inputPath: String
    
    @Option(name: .shortAndLong, help: "Output file or directory path")
    var output: String?
    
    @Option(name: .long, help: """
        Anonymization profile: ps315 (PS3.15 Basic Application Level Confidentiality \
        Profile, Table E.1-1; the default) or its alias basic; deprecated: the legacy \
        attribute lists legacy-basic, legacy-clinical-trial, legacy-research (not \
        PS3.15; clinical-trial and research select the last two)
        """)
    var profile: String = DICOMKit.AnonCLI.defaultProfile

    // PS3.15 Annex E Options (E.3); they act only on --profile ps315.
    @Flag(name: .long, help: """
        Deprecated: use --retain-full-dates or --retain-modified-dates. PS3.15 Retain \
        Longitudinal Temporal Information With Full Dates Option; with --shift-dates, \
        ... With Modified Dates Option (--profile ps315)
        """)
    var retainDates: Bool = false

    @Flag(name: .long, help: "PS3.15 Retain Longitudinal Temporal Information With Full Dates Option: dates and times kept (--profile ps315)")
    var retainFullDates: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Retain Longitudinal Temporal Information With Modified Dates Option: dates \
        shifted by --shift-dates, which it requires; times kept (--profile ps315)
        """)
    var retainModifiedDates: Bool = false

    @Flag(name: .long, help: "PS3.15 Retain Patient Characteristics Option (--profile ps315)")
    var retainCharacteristics: Bool = false

    @Flag(name: .long, help: "PS3.15 Retain Device Identity Option (--profile ps315)")
    var retainDevice: Bool = false

    @Flag(name: .long, help: "PS3.15 Retain Institution Identity Option (--profile ps315)")
    var retainInstitution: Bool = false

    @Flag(name: .long, help: "PS3.15 Retain UIDs Option: UIDs kept instead of replaced (U) (--profile ps315)")
    var retainUids: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Clean Descriptors Option (--profile ps315): descriptor attributes are kept \
        with the names, identifiers and dates the profile removes elsewhere taken out of \
        their text (E.3.5); review free text before release
        """)
    var cleanDescriptors: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Retain Safe Private Option (--profile ps315): keep the private attributes \
        PS3.15 Table E.3.10-1 lists for their Private Creator, or that the file declares safe \
        in Private Data Element Characteristics Sequence (0008,0300); other private attributes \
        are removed (E.3.10)
        """)
    var retainSafePrivate: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Clean Graphics Option (--profile ps315): keep Graphic Annotation Sequence \
        (0070,0001) with the names, identifiers and dates the profile removes taken out of \
        its text (E.3.3); overlays are still removed
        """)
    var cleanGraphics: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Clean Structured Content Option (--profile ps315): keep Content Sequence \
        (0040,A730) values (without it, Basic D: every Text Value and numeric value is a \
        dummy), Acquisition Context Sequence and Specimen Preparation Sequence; each \
        Content Item gets the action PS3.15 Table E.3.4-1 gives its Concept Name (removed, \
        dummy, kept or cleaned) and the text kept is cleaned (E.3.4)
        """)
    var cleanStructuredContent: Bool = false

    @Flag(name: .long, help: """
        PS3.15 Clean Recognizable Visual Features Option (--profile ps315): blank the \
        --redact-region areas (required; not detected automatically) on every frame, set \
        Recognizable Visual Features (0028,0302) = NO and record code 113102 (E.3.2)
        """)
    var cleanRecognizableVisualFeatures: Bool = false

    @Flag(name: .long, help: """
        PS3.15: Clean Pixel Data — blank burned-in identifiers out of the image itself. \
        Chooses the region automatically (declared clinical region, else device template) \
        and REFUSES rather than guessing when it cannot. Records code 113101 and sets \
        Burned In Annotation = NO only when pixels were actually blanked.
        """)
    var cleanPixelData: Bool = false

    @Option(name: .long, help: """
        Region to blank as x,y,width,height (repeatable). Implies --clean-pixel-data \
        and overrides automatic region selection; with --clean-recognizable-visual-features \
        the regions are the recognizable features to blank, and imply nothing else.
        """)
    var redactRegion: [String] = []

    @Option(name: .long, help: "Fill value for blanked pixels (default: 0 = black)")
    var redactFill: Int?

    @Option(name: .long, help: """
        Number of days to shift dates (preserves intervals). With --profile ps315 this \
        is the Modified Dates Option and needs --retain-modified-dates
        """)
    var shiftDates: Int?
    
    @Flag(name: .long, help: """
        Regenerate Study, Series and SOP Instance UIDs (legacy-* profiles). --profile \
        ps315 always replaces UIDs (Table E.1-1 action U) unless --retain-uids
        """)
    var regenerateUids: Bool = false
    
    @Option(name: .long, help: "Tags to remove (format: 0010,0010 or a PS3.6 keyword)")
    var remove: [String] = []
    
    @Option(name: .long, help: "Tags to replace (format: 0010,0010=VALUE or KEYWORD=VALUE)")
    var replace: [String] = []
    
    @Option(name: .long, help: "Tags to keep (preserve from anonymization; legacy-* profiles only)")
    var keep: [String] = []
    
    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Preview changes without modifying files")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Create backup of original files")
    var backup: Bool = false
    
    @Option(name: .long, help: "Path to audit log file")
    var auditLog: String?
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false

    @Flag(name: .long, help: """
        Proceed even when the pixels may still carry PHI (Burned In Annotation = YES, \
        or overlay planes present) (--profile ps315). Without this, such files are \
        refused unwritten, because without --clean-pixel-data only the data set is \
        de-identified.
        """)
    var allowBurnedInPHI: Bool = false

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDirectory) else {
            throw AnonymizationError.fileNotFound
        }
        
        // Parse profile
        let anonProfile = try parseProfile()
        do {
            try DICOMKit.AnonCLI.validate(profile: profile, flags: ps315Flags, shiftDates: shiftDates,
                                          regenerateUids: regenerateUids, keep: keep, redactRegions: redactRegion)
        } catch let error as DICOMKit.AnonCLI.ValidationError {
            // Rethrown as the CLI's own ValidationError: same message and exit status as before the lift (D275).
            throw ValidationError(error.message)
        }
        if let notice = DICOMKit.AnonCLI.legacyProfileNotice(profile) {
            FileHandle.standardError.write(Data((notice + "\n").utf8))
        }
        if retainDates {
            FileHandle.standardError.write(Data((DICOMKit.AnonCLI.retainDatesNotice(shiftDates: shiftDates) + "\n").utf8))
        }
        
        // Parse custom actions
        let customActions = try parseCustomActions()
        let preserveTags = try parsePreserveTags()
        
        // Create anonymizer
        let anonymizer = Anonymizer(
            profile: anonProfile,
            shiftDates: shiftDates,
            regenerateUIDs: regenerateUids,
            preserveTags: preserveTags,
            customActions: customActions
        )
        
        // Process files
        var results: [AnonymizationResult] = []
        var reports: [(path: String, actions: [DICOMKit.AnonCLI.AttributeAction])] = []
        
        if isDirectory.boolValue {
            guard recursive else {
                throw ValidationError("Directory anonymization requires --recursive flag")
            }
            guard let outputPath = output else {
                throw ValidationError("Directory anonymization requires --output directory")
            }
            (results, reports) = try anonymizeDirectory(
                inputURL: inputURL,
                outputURL: URL(fileURLWithPath: outputPath),
                anonymizer: anonymizer
            )
        } else {
            // Writing back over the input is never implied. Without --output there is
            // nowhere to write, so anonymizing would silently discard its result and
            // still report success — require --output unless this is a --dry-run preview.
            guard dryRun || output != nil else {
                throw ValidationError("Anonymization requires --output (or use --dry-run to preview without writing)")
            }
            let (result, actions) = try anonymizeFile(
                inputURL: inputURL,
                outputURL: output.map { URL(fileURLWithPath: $0) },
                anonymizer: anonymizer
            )
            results = [result]
            reports = [(inputURL.path, actions)]
        }
        
        // Per-attribute actions (PS3.6 name + PS3.15 Table E.1-1a code)
        if dryRun || verbose {
            for report in reports {
                print(DICOMKit.AnonCLI.actionLines(path: report.path, actions: report.actions), terminator: "")
            }
        }

        // Print summary
        printSummary(results: results)
        
        // Write audit log if requested
        if let auditLogPath = auditLog {
            let auditURL = URL(fileURLWithPath: auditLogPath)
            if isPS315 {
                // The PS3.15 engine keeps no change log of its own.
                let text = DICOMKit.AnonCLI.auditLogText(
                    profileDescription: ps315Options.methodCodes.map(\.meaning)
                        + (cleanRecognizableVisualFeatures
                           ? [ConfidentialityProfile.DeidentificationMethodCode.cleanRecognizableVisualFeaturesOption.meaning]
                           : []),
                    files: reports, generated: Date())
                try text.write(to: auditURL, atomically: true, encoding: .utf8)
            } else {
                try anonymizer.writeAuditLog(to: auditURL)
            }
            if verbose {
                print(AnonConsole.auditLogLine(path: auditLogPath))
            }
        }
        
        // Exit with error if any failures
        if results.contains(where: { !$0.success }) {
            throw ExitCode.failure
        }
    }
    
    private var isPS315: Bool { DICOMKit.AnonCLI.resolveProfile(profile)?.isPS315 ?? false }

    private var ps315Flags: DICOMKit.AnonCLI.PS315Flags {
        DICOMKit.AnonCLI.PS315Flags(
            retainDates: retainDates, retainFullDates: retainFullDates,
            retainModifiedDates: retainModifiedDates, retainCharacteristics: retainCharacteristics,
            retainDevice: retainDevice, retainInstitution: retainInstitution,
            retainUids: retainUids, cleanDescriptors: cleanDescriptors,
            retainSafePrivate: retainSafePrivate, cleanGraphics: cleanGraphics,
            cleanStructuredContent: cleanStructuredContent,
            cleanRecognizableVisualFeatures: cleanRecognizableVisualFeatures)
    }

    private var ps315Options: ConfidentialityProfile.Options {
        DICOMKit.AnonCLI.options(flags: ps315Flags, shiftDates: shiftDates)
    }

    private func parseProfile() throws -> AnonymizationProfile {
        guard let resolved = DICOMKit.AnonCLI.resolveProfile(profile) else {
            throw AnonymizationError.invalidProfile
        }
        // The ps315 path bypasses the legacy engine (see anonymizeFile); for it this
        // value is only used to build the shared Anonymizer instance.
        return resolved.legacyProfile ?? .basic
    }
    
    private func parseCustomActions() throws -> [Tag: AnonymizationAction] {
        var actions: [Tag: AnonymizationAction] = [:]
        
        // Parse remove tags
        for tagString in remove {
            let tag = try parseTag(tagString)
            actions[tag] = .remove
        }
        
        // Parse replace tags
        for replaceString in replace {
            let parts = replaceString.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw ValidationError("Invalid replace format: \(replaceString). Use TAG=VALUE")
            }
            let tag = try parseTag(String(parts[0]))
            let value = String(parts[1])
            actions[tag] = .replaceWithDummy(value)
        }
        
        return actions
    }
    
    private func parsePreserveTags() throws -> Set<Tag> {
        var tags = Set<Tag>()
        
        for tagString in keep {
            let tag = try parseTag(tagString)
            tags.insert(tag)
        }
        
        return tags
    }
    
    private func parseTag(_ string: String) throws -> Tag {
        guard let tag = DICOMKit.AnonCLI.parseTag(string) else {
            throw ValidationError("Invalid tag format: \(string)")
        }
        return tag
    }
    
    private func anonymizeDirectory(
        inputURL: URL,
        outputURL: URL,
        anonymizer: Anonymizer
    ) throws -> ([AnonymizationResult], [(path: String, actions: [DICOMKit.AnonCLI.AttributeAction])]) {
        // Create output directory
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        
        guard let fileURLs = FileGatherer.regularFiles(under: inputURL) else {
            throw ValidationError("Failed to enumerate directory: \(inputURL.path)")
        }

        var results: [AnonymizationResult] = []
        var reports: [(path: String, actions: [DICOMKit.AnonCLI.AttributeAction])] = []

        for fileURL in fileURLs {
            // Calculate relative path
            guard let relativePath = fileURL.path.replacingOccurrences(
                of: inputURL.path,
                with: ""
            ).dropFirst().nilIfEmpty else { continue }
            
            let outputFileURL = outputURL.appendingPathComponent(relativePath)
            
            // Create intermediate directories
            try FileManager.default.createDirectory(
                at: outputFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            do {
                let (result, actions) = try anonymizeFile(
                    inputURL: fileURL,
                    outputURL: outputFileURL,
                    anonymizer: anonymizer
                )
                results.append(result)
                reports.append((fileURL.path, actions))
                
                if verbose {
                    print(AnonConsole.fileSuccessLine(relativePath: String(relativePath)))
                }
            } catch {
                if verbose {
                    print(AnonConsole.fileFailureLine(relativePath: String(relativePath), message: error.localizedDescription))
                }
                results.append(AnonymizationResult(
                    filePath: fileURL.path,
                    success: false,
                    changedTags: [],
                    warnings: [error.localizedDescription]
                ))
            }
        }
        
        return (results, reports)
    }
    
    private func anonymizeFile(
        inputURL: URL,
        outputURL: URL?,
        anonymizer: Anonymizer
    ) throws -> (AnonymizationResult, [DICOMKit.AnonCLI.AttributeAction]) {
        // Read DICOM file
        var fileData = try Data(contentsOf: inputURL)
        var dicomFile = try DICOMFile.read(from: fileData, force: force)
        let sourceDataSet = dicomFile.dataSet

        // --- Pixel cleaning runs FIRST, before any header de-identification. ---
        // The region decision reads Modality / Manufacturer / model, which
        // de-identification removes; planning afterwards would see a scrubbed data set
        // and match nothing. Both CTP and Presidio document this same ordering
        // dependency, so the order here is a correctness requirement, not a preference.
        let editor = PixelEditor(verbose: false)
        let explicit = try redactRegion.map { spec -> PixelRedactionPlan.Region in
            let r = try editor.parseRegion(spec)
            return PixelRedactionPlan.Region(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        // With --clean-recognizable-visual-features the regions are the features to blank
        // (PS3.15 E.3.2); they claim nothing about burned-in text unless --clean-pixel-data.
        if cleanPixelData || (!redactRegion.isEmpty && !cleanRecognizableVisualFeatures) {
            let plan = PixelRedactionPlan.plan(for: dicomFile.dataSet, explicitRegions: explicit)
            if let (redacted, outcome) = try PixelRedactor().redact(
                fileData: fileData, plan: plan, fillValue: redactFill) {
                fileData = redacted
                dicomFile = try DICOMFile.read(from: redacted, force: force)
                if verbose {
                    print(AnonConsole.pixelRedactionLines(outcome: outcome), terminator: "")
                }
            }
        }
        if cleanRecognizableVisualFeatures {
            let (redacted, outcome) = try PixelRedactor().redactRecognizableVisualFeatures(
                fileData: fileData, regions: explicit, fillValue: redactFill)
            fileData = redacted
            dicomFile = try DICOMFile.read(from: redacted, force: force)
            if verbose {
                print(DICOMKit.AnonCLI.visualFeaturesLines(outcome: outcome), terminator: "")
            }
        }

        // Anonymize — PS3.15 Annex E engine or legacy profile.
        let anonymizedFile: DICOMFile
        let result: AnonymizationResult
        if isPS315 {
            let (file, res, _) = anonymizer.deidentify(file: dicomFile, options: ps315Options)
            // Refuse to emit a file whose pixels may still identify the patient unless
            // the operator explicitly accepts that. Writing it silently is the harmful
            // case: the metadata looks clean, so the file reads as safe to release.
            if !res.warnings.isEmpty && !allowBurnedInPHI {
                throw ValidationError(
                    """
                    Refusing to anonymize \(inputURL.lastPathComponent): the pixel data may \
                    still contain PHI.

                    \(res.warnings.map { "  ⚠️  \($0)" }.joined(separator: "\n"))

                    Without --clean-pixel-data this tool de-identifies the DATASET ONLY, \
                    so burned-in text survives unchanged.

                    Pass --clean-pixel-data to blank it (add --redact-region x,y,w,h if \
                    the automatic region selection cannot resolve this device), or \
                    --allow-burned-in-phi to write the metadata-scrubbed file anyway \
                    (it will be marked Patient Identity Removed = NO).
                    """)
            }
            // --remove / --replace: the engine takes no custom actions, so apply them here.
            var scrubbed = file.dataSet
            DICOMKit.AnonCLI.applyCustomActions(try parseCustomActions(), source: dicomFile.dataSet, to: &scrubbed)
            anonymizedFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: scrubbed)
            result = AnonymizationResult(
                filePath: inputURL.path, success: res.success,
                changedTags: res.changedTags, warnings: res.warnings)
        } else {
            (anonymizedFile, result) = try anonymizer.anonymize(file: dicomFile, filePath: inputURL.path)
        }
        
        // Write output if not dry-run
        if !dryRun, let outputURL = outputURL {
            // Backup if requested
            if backup {
                let backupURL = outputURL.appendingPathExtension("backup")
                try? FileManager.default.copyItem(at: inputURL, to: backupURL)
            }
            
            // Write anonymized file. PS3.10 7.1 (DICOM File Meta Information), Table 7.1-1: Media Storage SOP Instance UID (0002,0003)
            // equals SOP Instance UID (0008,0018); the engines leave the file meta as read,
            // which would carry the original UID that Table E.1-1 replaces (U).
            let outputData = try DICOMKit.AnonCLI.syncingMediaStorageSOPInstanceUID(anonymizedFile).write()
            try outputData.write(to: outputURL)
        }
        
        let actions = DICOMKit.AnonCLI.attributeActions(
            before: sourceDataSet, after: anonymizedFile.dataSet,
            options: isPS315 ? ps315Options : nil)
        return (result, actions)
    }
    
    private func printSummary(results: [AnonymizationResult]) {
        print(AnonConsole.summary(
            totalFiles: results.count,
            successful: results.filter { $0.success }.count,
            failed: results.filter { !$0.success }.count,
            dryRun: dryRun,
            warnings: results.flatMap { $0.warnings },
            modifiedTags: Set(results.flatMap { $0.changedTags }.map { "\($0)" }),
            verbose: verbose
        ), terminator: "")
    }
}

struct ValidationError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

// CLI-only error type (the shared DICOMKit `Anonymizer` engine never throws it;
// only the command's argument parsing / file checks do).
enum AnonymizationError: Error, LocalizedError {
    case invalidProfile
    case fileNotFound
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Invalid anonymization profile (use ps315, basic, legacy-basic, legacy-clinical-trial or legacy-research)"
        case .fileNotFound:
            return "File not found"
        case .writeError(let msg):
            return "Write error: \(msg)"
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}

extension Substring {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : String(self)
    }
}

DICOMAnon.main()
