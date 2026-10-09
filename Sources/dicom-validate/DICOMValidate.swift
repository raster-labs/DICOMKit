// NEMA-verified: 2026a, checked 2026-10-01 — printed Type / PS3.3 module-table / PS3.5 7.4.1-7.4.4 citations run on 10 fixtures and diffed against PS3.3 2026a (81 distinct messages; the 2 engine mismatches, D140 and D143, fixed in DICOMKit); --iod takes PS3.6 Table A-1 keywords and UIDs (DICOMValidator.iodName(forIODOption:), D248); --level help states what level 2 checks (PS3.6 Table 6-1 VR and VM; PS3.5 Table 6.2-1 lengths, repertoires and DA/TM/UI/AS/DS/IS forms; PS3.5 6.2.1 PN component groups)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

// The validation engine (`DICOMValidator`), report renderer (`ValidationReport`),
// and `ValidationOutputFormat` now live in the DICOMKit library so the CLI and
// DICOMStudio run the exact same code. ArgumentParser stays out of the library,
// so the CLI supplies the command-line conformance here.
extension ValidationOutputFormat: ExpressibleByArgument {}

@main
struct DICOMValidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-validate",
        abstract: "Validate DICOM files against standards and best practices",
        discussion: """
            Validates DICOM files for conformance to the DICOM standard.
            Supports multiple validation levels from basic file format to IOD-specific rules.
            
            Examples:
              dicom-validate file.dcm
              dicom-validate file.dcm --level 3 --detailed
              dicom-validate file.dcm --iod CTImageStorage
              dicom-validate file.dcm --iod ComputedRadiographyImageStorage
              dicom-validate study/ --recursive --format json --output report.json
              dicom-validate file.dcm --strict
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "Path to DICOM file or directory")
    var inputPath: String
    
    @Option(name: .long, help: "Validation level (1-5): 1=File Meta Information (PS3.10 Table 7.1-1), 2=VR and VM against PS3.6 Table 6-1, value length, character repertoire and DA/TM/UI/AS/DS/IS value forms (PS3.5 Table 6.2-1, 6.2.1, 9.1), 3=IOD Type 1/1C/2/2C (PS3.3), 4=Best practices, 5=J2K codestream")
    var level: Int = 3
    
    @Option(name: .long, help: "IOD to validate against: SOP Class keyword or UID of PS3.6 Table A-1 (e.g. CTImageStorage, MRImageStorage, ComputedRadiographyImageStorage, UltrasoundImageStorage, SecondaryCaptureImageStorage, GrayscaleSoftcopyPresentationStateStorage, PseudoColorSoftcopyPresentationStateStorage, an SR or Key Object Selection keyword); short names CT, MR, CR, US, SC, GSPS, SR, KOS also accepted; default: from SOP Class UID (0008,0016)")
    var iod: String?
    
    @Flag(name: .long, help: "Show detailed validation report")
    var detailed: Bool = false
    
    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false
    
    @Option(name: .shortAndLong, help: "Output format: text, json")
    var format: ValidationOutputFormat = .text
    
    @Option(name: .shortAndLong, help: "Output file path (stdout if not specified)")
    var output: String?
    
    @Flag(name: .long, help: "Treat warnings as errors (exit code non-zero)")
    var strict: Bool = false
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDirectory) else {
            throw ValidationError("Input path not found: \(inputPath)")
        }
        
        guard level >= 1 && level <= 5 else {
            throw ValidationError("Validation level must be between 1 and 5")
        }
        
        let results: [ValidationResult]
        if isDirectory.boolValue {
            guard recursive else {
                throw ValidationError("Directory validation requires --recursive flag")
            }
            results = try validateDirectory(url: inputURL)
        } else {
            let result = try validateFile(url: inputURL)
            results = [result]
        }
        
        let report = ValidationReport(results: results, detailed: detailed, strict: strict)
        let outputText = try report.render(format: format)
        
        if let outputPath = output {
            let resolvedOutputPath = OutputPathResolver.resolveFileOutput(
                output: outputPath,
                input: inputPath,
                fileExtension: format == .json ? "json" : "txt"
            )
            let outputURL = URL(fileURLWithPath: resolvedOutputPath)

            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try outputText.write(to: outputURL, atomically: true, encoding: .utf8)
            } catch {
                throw ValidationError(
                    "Failed to write validation report to \(resolvedOutputPath): \(error.localizedDescription)"
                )
            }
        } else {
            print(outputText, terminator: "")
        }
        
        let exitCode = report.exitCode()
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
    
    private func validateDirectory(url: URL) throws -> [ValidationResult] {
        // Shared, sorted directory walk — the same gatherer the Workshop uses, so
        // both surfaces validate the same files in the same order.
        guard let fileURLs = FileGatherer.regularFiles(under: url) else {
            throw ValidationError("Failed to enumerate directory: \(url.path)")
        }

        var results: [ValidationResult] = []

        for fileURL in fileURLs {
            do {
                let result = try validateFile(url: fileURL)
                results.append(result)
            } catch {
                let result = ValidationResult(
                    filePath: fileURL.path,
                    isValid: false,
                    errors: [ValidationIssue(level: .error, message: error.localizedDescription, tag: nil)],
                    warnings: []
                )
                results.append(result)
            }
        }
        
        return results
    }
    
    private func validateFile(url: URL) throws -> ValidationResult {
        let fileData = try Data(contentsOf: url)
        
        let validator = DICOMValidator(level: level, iod: iod.map(DICOMValidator.iodName(forIODOption:)), force: force)
        return try validator.validate(data: fileData, filePath: url.path)
    }
}
