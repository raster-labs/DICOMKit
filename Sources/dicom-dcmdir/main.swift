// NEMA-verified: 2026a, checked 2026-10-01 — the --profile help and error text name only identifiers from PS3.11 2026a Tables A.1-1, B.1-1, C.1-1, D.1-1, E.1-1, G.1-1, H.1-1 to N.1-1 (64 identifiers extracted by script; STD-GEN-DVD and STD-GEN-USB are family headings, not identifiers, D29); the accepted values are those of DICOMCore.DICOMDIRProfile
// NEMA-verified: 2026a, checked 2026-10-01 — create derives the default File-set ID per PS3.10 2026a 8.1/8.5; File IDs outside 8.2/8.5 and SOP Classes / Transfer Syntaxes outside the profile's PS3.11 2026a table are refused by the engine (D70, D131), --copy-to assigns conformant File IDs, no DICOMDIR is written when every file is refused (PS3.11 D.3.3); validate reports each failure with its PS3.10 8.1, 8.2, 8.5, 8.6 / PS3.3 Table F.3-2, F.3-3, F.4-1 clause and --check-files tests every Referenced File ID (0004,1500) on disk (8.6); dump record labels are the 35 Directory Record Type terms of PS3.3 Table F.4-1 (DICOMCore.DirectoryRecordType)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMDCMDIR: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-dcmdir",
        abstract: "DICOMDIR management tool for media storage directories",
        discussion: """
            Create, update, validate, and manage DICOMDIR files for CD/DVD/USB media.
            
            DICOMDIR is a special DICOM file that provides an index of all DICOM files
            on removable media, enabling efficient browsing without reading all files.
            
            Examples:
              # Create DICOMDIR for a directory of DICOM files
              dicom-dcmdir create study_folder/ --output DICOMDIR
              
              # Validate an existing DICOMDIR
              dicom-dcmdir validate /media/cdrom/DICOMDIR
              
              # Display DICOMDIR structure
              dicom-dcmdir dump DICOMDIR --format tree
              
              # Update DICOMDIR with new files
              dicom-dcmdir update DICOMDIR --add new_series/
            """,
        version: "1.2.0",
        subcommands: [
            Create.self,
            Validate.self,
            Dump.self,
            Update.self
        ]
    )
}

// MARK: - Create Subcommand

extension DICOMDCMDIR {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a DICOMDIR from a directory of DICOM files"
        )
        
        @Argument(help: "Directory containing DICOM files")
        var inputDirectory: String
        
        @Option(name: .shortAndLong, help: "Output DICOMDIR path (default: DICOMDIR in input directory)")
        var output: String?
        
        @Option(name: .long, help: "File-set ID (0004,1130): up to 16 characters A-Z, 0-9, _ (PS3.10 8.1, 8.5); any other value is refused (exit 1); default: the directory name upper-cased, other characters as _, cut to 16")
        var fileSetID: String?
        
        @Option(name: .long, help: "PS3.11 Application Profile identifier, e.g. STD-GEN-CD (default), STD-GEN-DVD-JPEG, STD-GEN-DVD-J2K, STD-GEN-USB-JPEG, STD-GEN-USB-J2K, STD-GEN-BD-JPEG (deprecated: STD-GEN-DVD, STD-GEN-USB, STD-GEN-SEC, STD-CTMR-XXXX, STD-US-XXXX are not PS3.11 identifiers; still accepted with a warning)")
        var profile: String = "STD-GEN-CD"
        
        // `.inversion` is required by ArgumentParser for a Bool flag whose default is
        // `true` (a plain `@Flag … = true` would always be true and is rejected at
        // validation, breaking the whole `create` command). This keeps recursion ON by
        // default while exposing `--no-recursive` to disable it.
        @Flag(inversion: .prefixedNo, help: "Recursively scan subdirectories (default: on)")
        var recursive: Bool = true
        
        @Flag(name: .long, help: "Include only valid DICOM files")
        var strict: Bool = false
        
        @Option(name: .long, help: "Copy the files into a new File-set in this folder under File IDs the tool assigns, DICOM\\PTnnnnnn\\STnnnnnn\\SEnnnnnn\\IMnnnnnn (PS3.10 8.2, 8.5), and write the DICOMDIR there (default output: <folder>/DICOMDIR). Without it, files are indexed in place and a path that is not a PS3.10 File ID (e.g. img1.dcm) is refused")
        var copyTo: String?
        
        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false
        
        mutating func run() throws {
            let inputURL = URL(fileURLWithPath: inputDirectory)
            
            guard FileManager.default.fileExists(atPath: inputDirectory) else {
                throw ValidationError("Input directory not found: \(inputDirectory)")
            }
            
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputDirectory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ValidationError("Input path is not a directory: \(inputDirectory)")
            }
            
            // Determine the output DICOMDIR file path. When --output points at a
            // directory (or a trailing-slash path), the DICOMDIR is written INSIDE it;
            // writing onto a directory path otherwise fails ("couldn't be saved in the
            // folder …"). Default: a DICOMDIR inside the input directory.
            let copyRoot = copyTo.map { URL(fileURLWithPath: $0) }
            let outputPath = DICOMDIRWorkflow.resolvedDICOMDIRPath(
                output ?? ((copyTo ?? inputDirectory) + "/DICOMDIR"))
            // The File IDs are relative to the DICOMDIR's folder (PS3.10 8.6): with --copy-to
            // the DICOMDIR goes in the root of the new File-set.
            if let copyRoot, URL(fileURLWithPath: outputPath).deletingLastPathComponent().standardizedFileURL.path
                != copyRoot.standardizedFileURL.path {
                throw ValidationError("With --copy-to the DICOMDIR is written in that folder (PS3.10 8.6); omit --output or use --output \(copyRoot.path)/DICOMDIR")
            }
            
            // Determine file-set ID
            let fsID: String
            if let id = fileSetID {
                // P-DCMDIR-FSID: refuse (exit 1) instead of writing a non-conformant ID.
                if let refusal = DICOMDIRFileSetRules.fileSetIDRefusal(id) {
                    FileHandle.standardError.write(Data("Error: \(refusal)\n".utf8))
                    throw ExitCode.failure
                }
                fsID = id
            } else {
                fsID = DICOMDIRFileSetRules.defaultFileSetID(fromDirectoryName: inputURL.lastPathComponent)
            }
            
            // Parse profile
            guard let dicomProfile = DICOMDIRProfile(rawValue: profile) else {
                let standard = DICOMDIRProfile.allStandard.map(\.rawValue).joined(separator: ", ")
                throw ValidationError("Invalid profile: \(profile). Use a PS3.11 Application Profile identifier: \(standard), or STD-US-<ID|SC|CC>-<SF|MF>-<media>")
            }
            // P-DCMDIR-PROFILE: a pre-2026-09-25 spelling still works, with a note naming the
            // PS3.11 identifier that is written.
            if let note = DICOMDIRFileSetRules.profileDeprecationNote(requested: profile, resolved: dicomProfile) {
                FileHandle.standardError.write(Data((note + "\n").utf8))
            }
            
            if verbose {
                print("Creating DICOMDIR...")
                print("  Input directory: \(inputDirectory)")
                print("  Output file: \(outputPath)")
                print("  File-set ID: \(fsID)")
                print("  Profile: \(dicomProfile.rawValue)")
                print("  Recursive: \(recursive)")
                print("")
            }
            
            // Build the DICOMDIR via the shared DICOMDIRWorkflow — the single source
            // of truth shared with DICOMStudio's CLI Workshop (file discovery, the
            // build loop, and the relative-path computation), so the produced
            // DICOMDIR cannot drift between the two surfaces.
            let result: DICOMDIRWorkflow.CreateResult
            do {
                result = try DICOMDIRWorkflow.buildDirectory(
                    fromFilesIn: inputURL, recursive: recursive, strict: strict,
                    fileSetID: fsID, profile: dicomProfile, copyingInto: copyRoot,
                    verbose: verbose, progress: { print($0, terminator: "") })
            } catch DICOMDIRWorkflow.WorkflowError.noDICOMFiles {
                throw ValidationError("No DICOM files found in directory: \(inputDirectory)")
            }

            // Every file refused (PS3.10 8.2/8.5 File ID, PS3.11 profile table, duplicate
            // instance): a DICOMDIR without directory records is not written (PS3.11 D.3.3).
            guard result.processed > 0 else {
                var message = "Error: no file could be indexed; no DICOMDIR written\n"
                for failure in result.failures { message += "  \(failure.file): \(failure.reason)\n" }
                if copyTo == nil {
                    message += "Use --copy-to <folder> to copy the files into a new File-set under conformant File IDs (PS3.10 8.2, 8.5)\n"
                }
                FileHandle.standardError.write(Data(message.utf8))
                throw ExitCode.failure
            }

            // Write to file (creating intermediate directories so a fresh --output
            // path doesn't fail on a missing parent).
            let outputFileURL = URL(fileURLWithPath: outputPath)
            try? FileManager.default.createDirectory(
                at: outputFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DICOMDIRWriter.write(result.directory, to: outputFileURL)

            // Print the shared summary block.
            print(DICOMDIRWorkflow.renderCreateSummary(result, outputPath: outputPath), terminator: "")

            if result.failed > 0 {
                FileHandle.standardError.write(Data("Warning: \(result.failed) file(s) not indexed (listed in the summary)\n".utf8))
            }
        }
    }
}

// MARK: - Validate Subcommand

extension DICOMDCMDIR {
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate a DICOMDIR file"
        )
        
        @Argument(help: "Path to DICOMDIR file")
        var dicomdirPath: String
        
        @Flag(name: .long, help: "Check that every Referenced File ID (0004,1500) names a file in the File-set (PS3.10 8.6)")
        var checkFiles: Bool = false
        
        @Flag(name: .long, help: "Detailed validation output")
        var detailed: Bool = false
        
        mutating func run() throws {
            // Accept either a DICOMDIR file or the media DIRECTORY that contains it.
            let resolvedPath = DICOMDIRWorkflow.resolvedDICOMDIRPath(dicomdirPath)
            let fileURL = URL(fileURLWithPath: resolvedPath)

            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ValidationError(resolvedPath == dicomdirPath
                    ? "DICOMDIR file not found: \(dicomdirPath)"
                    : "No DICOMDIR found in directory: \(dicomdirPath)")
            }

            print("Validating DICOMDIR: \(resolvedPath)")
            print("")
            
            // Read DICOMDIR
            let directory: DICOMDirectory
            do {
                directory = try DICOMDIRReader.read(from: fileURL)
            } catch {
                print("❌ Failed to read DICOMDIR: \(DICOMDIRFileSetRules.describe(error))")
                throw ExitCode(1)
            }
            
            // Validate structure (PS3.3 Table F.4-1 hierarchy, duplicate SOP Instances)
            do {
                try directory.validate(checkFileExistence: checkFiles)
            } catch {
                print("❌ Validation failed: \(DICOMDIRFileSetRules.describe(error))")
                throw ExitCode(1)
            }

            // File-set ID and File ID rules (PS3.10 8.1, 8.2, 8.5, 8.6; PS3.3 Table F.3-3)
            let findings = DICOMDIRFileSetRules.findings(
                for: directory, mediaFolder: fileURL.deletingLastPathComponent(), checkFiles: checkFiles)
            if !findings.isEmpty {
                for finding in findings { print("❌ \(finding)") }
                print("")
                print("❌ Validation failed: \(findings.count) rule violation(s)")
                throw ExitCode(1)
            }

            // Render the shared validation report — the single source of truth
            // shared with DICOMStudio's CLI Workshop.
            print(DICOMDIRWorkflow.renderValidationReport(directory, detailed: detailed), terminator: "")
        }
    }
}

// MARK: - Dump Subcommand

extension DICOMDCMDIR {
    struct Dump: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dump",
            abstract: "Display DICOMDIR structure"
        )
        
        @Argument(help: "Path to DICOMDIR file")
        var dicomdirPath: String
        
        @Option(name: .shortAndLong, help: "Output format: tree, json, text")
        var format: String = "tree"
        
        @Flag(name: .long, help: "Show all attributes for each record")
        var verbose: Bool = false
        
        mutating func run() throws {
            // Accept either a DICOMDIR file or the media DIRECTORY that contains it.
            let resolvedPath = DICOMDIRWorkflow.resolvedDICOMDIRPath(dicomdirPath)
            let fileURL = URL(fileURLWithPath: resolvedPath)

            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ValidationError(resolvedPath == dicomdirPath
                    ? "DICOMDIR file not found: \(dicomdirPath)"
                    : "No DICOMDIR found in directory: \(dicomdirPath)")
            }

            // Read DICOMDIR
            let directory: DICOMDirectory
            do {
                directory = try DICOMDIRReader.read(from: fileURL)
            } catch {
                print("Error reading DICOMDIR: \(DICOMDIRFileSetRules.describe(error))")
                throw ExitCode(1)
            }
            
            // Render via the shared DICOMDIRDumpFormatter (single source of truth
            // shared with DICOMStudio's CLI Workshop). Empty terminator so the
            // formatter's own trailing newline is not doubled.
            guard let rendered = DICOMDIRDumpFormatter.render(directory, format: format, verbose: verbose) else {
                throw ValidationError("Invalid format: \(format). Use tree, json, or text")
            }
            print(rendered, terminator: "")
        }
    }
}

// MARK: - Update Subcommand

extension DICOMDCMDIR {
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update an existing DICOMDIR with new files"
        )
        
        @Argument(help: "Path to existing DICOMDIR file")
        var dicomdirPath: String
        
        @Option(name: .long, help: "Directory with new DICOM files to add")
        var add: String?
        
        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false
        
        mutating func run() throws {
            // Entire update via the SHARED DICOMDIRWorkflow (DICOMKit) — the
            // same code the Studio Workshop executor runs: parse the existing
            // DICOMDIR, union its referenced files with --add, rebuild with the
            // original file-set ID/profile, write back.
            let dicomdirURL = DICOMDIRWorkflow.resolvedDICOMDIRURL(URL(fileURLWithPath: dicomdirPath))
            guard FileManager.default.fileExists(atPath: dicomdirURL.path) else {
                throw ValidationError("DICOMDIR not found: \(dicomdirURL.path)")
            }
            if verbose {
                print("Updating DICOMDIR: \(dicomdirURL.path)")
                if let add { print("Adding from: \(add)") }
                print("")
            }
            let result = try DICOMDIRWorkflow.updateDirectory(
                dicomdirURL: dicomdirURL, addPath: add,
                verbose: verbose, progress: { print($0, terminator: "") }
            )
            try DICOMDIRWriter.write(result.directory, to: dicomdirURL)
            print(DICOMDIRWorkflow.renderUpdateSummary(result, outputPath: dicomdirURL.path), terminator: "")
        }
    }
}

DICOMDCMDIR.main()
