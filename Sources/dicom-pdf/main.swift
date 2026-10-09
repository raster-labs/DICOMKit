// NEMA-verified: 2026a, checked 2026-10-01 — input/output contract of all 19 option/flag/argument declarations by script: Encapsulated PDF Storage 1.2.840.10008.5.1.4.1.1.104.1 (PS3.6 2026a Table A-1); a round trip of an odd-length PDF diffed against PS3.3 2026a Tables A.45.1-1, C.7-1, C.7-3, C.24-1, C.7-8, C.8-24, C.24-2, C.12-1 (every Type 1/2 attribute present; (0042,0015) and (0008,0005) completed and the padding byte stripped on extraction by DICOMKit EncapsulatedDocumentBuilder.OptionRules, D272); --modality default DOC / M3D (C.24-1, A.85.x.4.3); --conversion-type 8 Defined Terms (C.8-24); --burned-in-annotation YES/NO and --hl7-instance-identifier (C.24-2); the option vocabularies are EncapsulatedDocumentBuilder.OptionRules (D272); 2026-10-06: a directory --extract skips a file without Encapsulated Document (0042,0011) (C.24.2) and exits 1 only for a document that failed (D271)

import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMPdf: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-pdf",
        abstract: "Extract and encapsulate PDF/CDA/3D documents from/to DICOM format",
        discussion: """
            Extract documents (PDF, CDA, STL, OBJ, MTL) from DICOM Encapsulated Document files,
            or encapsulate documents into DICOM format for PACS storage.
            
            Supported document types:
            - PDF (Portable Document Format)
            - CDA (Clinical Document Architecture XML)
            - STL (Stereolithography 3D models)
            - OBJ (Wavefront 3D object files)
            - MTL (Wavefront material files)
            
            Examples:
              # Extract PDF from DICOM
              dicom-pdf report.dcm --output report.pdf --extract
              
              # Create Encapsulated PDF DICOM
              dicom-pdf report.pdf --output report.dcm \\
                --patient-name "DOE^JOHN" \\
                --patient-id "12345" \\
                --title "Radiology Report"
              
              # Extract CDA document
              dicom-pdf cda.dcm --output cda.xml --extract

              # Encapsulate a CDA document; HL7 Instance Identifier (0040,E001) is
              # read from /ClinicalDocument/id unless given
              dicom-pdf cda.xml --output cda.dcm --patient-name "DOE^JOHN" \\
                --patient-id "12345" --hl7-instance-identifier "2.16.840.1.113883.19^X1"

              # A scanned paper report (Conversion Type SD, PS3.3 Table C.8-24)
              dicom-pdf scan.pdf --output scan.dcm --patient-name "DOE^JOHN" \\
                --patient-id "12345" --conversion-type SD
              
              # Batch extract all documents from directory
              dicom-pdf study/ --output documents/ --extract --recursive
              
              # Encapsulate 3D model
              dicom-pdf model.stl --output model.dcm \\
                --patient-name "SMITH^JANE" \\
                --study-uid "1.2.3.4.5"
            """,
        version: "1.1.5"
    )
    
    @Argument(help: "Input file or directory (DICOM or document)")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output file or directory path")
    var output: String?
    
    @Flag(name: .long, help: "Extract mode: Extract document from DICOM")
    var extract: Bool = false
    
    @Option(name: .long, help: "Patient's Name (for encapsulation mode)")
    var patientName: String?
    
    @Option(name: .long, help: "Patient ID (for encapsulation mode)")
    var patientId: String?
    
    @Option(name: .long, help: "Document Title (0042,0010) (for encapsulation mode)")
    var title: String?
    
    @Option(name: .long, help: "Study Instance UID (auto-generated if not provided)")
    var studyUid: String?
    
    @Option(name: .long, help: "Series Instance UID (auto-generated if not provided)")
    var seriesUid: String?
    
    @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("to write (default: DOC; STL/OBJ/MTL require M3D, PS3.3 A.85.x.4.3)")))
    var modality: String?

    @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
    var strictModality: Bool = false
    
    @Option(name: .long, help: "Series Description")
    var seriesDescription: String?
    
    @Option(name: .long, help: "Series Number")
    var seriesNumber: Int?
    
    @Option(name: .long, help: "Instance Number")
    var instanceNumber: Int?
    
    @Option(name: .long, help: ArgumentHelp(stringLiteral: "Conversion Type (0008,0064) for PDF and CDA, a PS3.3 Table C.8-24 Defined Term: \(EncapsulatedDocumentBuilder.OptionRules.conversionTypes.joined(separator: ", ")) (default: \(EncapsulatedDocumentBuilder.OptionRules.defaultConversionType))"))
    var conversionType: String?

    @Option(name: .long, help: "Burned In Annotation (0028,0301): YES or NO, whether the document identifies the patient and the date (default: YES)")
    var burnedInAnnotation: String?

    @Option(name: .long, help: "HL7 Instance Identifier (0040,E001) of a CDA document, UID or UID^extension (default: read from /ClinicalDocument/id; single file only)")
    var hl7InstanceIdentifier: String?

    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Show document metadata (extract mode)")
    var showMetadata: Bool = false
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        // Validate input exists
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input path not found: \(input)")
        }
        
        // Determine if input is a directory
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory)
        
        if isDirectory.boolValue {
            guard recursive else {
                throw ValidationError("Directory processing requires --recursive flag")
            }
            
            if extract {
                try extractFromDirectory(inputPath: input, outputPath: output)
            } else {
                try encapsulateFromDirectory(inputPath: input, outputPath: output)
            }
        } else {
            if extract {
                try extractFromFile(inputPath: input, outputPath: output)
            } else {
                try encapsulateFile(inputPath: input, outputPath: output)
            }
        }
    }
    
    // MARK: - Extraction Mode
    
    private func extractFromFile(inputPath: String, outputPath: String?) throws {
        if verbose {
            print("Extracting document from: \(inputPath)")
        }
        
        // Read DICOM file
        let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let dicomFile = try DICOMFile.read(from: inputData)
        
        // Parse encapsulated document
        let document = try EncapsulatedDocumentParser.parse(from: dicomFile.dataSet)
        
        // Show metadata if requested
        if showMetadata {
            // Shared renderer (DICOMKit) — emitted verbatim by the Studio reimplementation too.
            print(document.metadataReport(), terminator: "")
        }

        // Determine output path
        let finalOutputPath: String
        if let specifiedOutput = outputPath {
            finalOutputPath = specifiedOutput
        } else {
            // Auto-generate output filename based on document type
            let inputURL = URL(fileURLWithPath: inputPath)
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let fileExtension = document.documentType.fileExtension
            finalOutputPath = inputURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).\(fileExtension)")
                .path
        }

        // Write document data, without the trailing padding (0042,0015)
        let documentBytes = EncapsulatedDocumentBuilder.OptionRules.documentBytes(document.documentData, in: dicomFile.dataSet)
        try documentBytes.write(to: URL(fileURLWithPath: finalOutputPath))

        if verbose {
            print("✓ Extracted \(document.documentType) (\(EncapsulatedDocumentFormatting.fileSize(Int64(documentBytes.count))))")
            print("  Output: \(finalOutputPath)")
        } else {
            print("Extracted: \(finalOutputPath)")
        }
    }
    
    /// The verbose line for a file a directory `--extract` skips (D271): not a DICOM file, or
    /// one without Encapsulated Document (0042,0011) (PS3.3 2026a C.24.2).
    static func skippedLine(fileName: String) -> String {
        "⊘ \(fileName): not an Encapsulated Document (skipped)"
    }

    private func extractFromDirectory(inputPath: String, outputPath: String?) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        
        // Determine output directory
        let outputDirURL: URL
        if let specifiedOutput = outputPath {
            outputDirURL = URL(fileURLWithPath: specifiedOutput)
        } else {
            outputDirURL = inputURL.appendingPathComponent("extracted")
        }
        
        // Create output directory
        try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
        
        if verbose {
            print("Extracting documents from: \(inputPath)")
            print("Output directory: \(outputDirURL.path)")
            print()
        }
        
        var successCount = 0
        var failureCount = 0
        var extractedFiles: [String] = []
        
        // Enumerate DICOM files via the shared, sorted gatherer (same walk as the Workshop).
        let fileURLs = FileGatherer.regularFiles(under: inputURL) ?? []

        for fileURL in fileURLs {
            // D271: a file that is not an Encapsulated Document — not a DICOM file, or a data set
            // without Encapsulated Document (0042,0011) (PS3.3 2026a C.24.2) — is skipped, as
            // dicom-image skips non-images and dicom-export files without pixel data; only a
            // document that fails to extract counts as failed.
            let inputData: Data
            do {
                inputData = try Data(contentsOf: fileURL)
            } catch {
                failureCount += 1
                if verbose {
                    print("✗ \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
                continue
            }
            guard let dicomFile = try? DICOMFile.read(from: inputData),
                  dicomFile.dataSet[.encapsulatedDocument] != nil else {
                if verbose {
                    print(Self.skippedLine(fileName: fileURL.lastPathComponent))
                }
                continue
            }
            do {
                let document = try EncapsulatedDocumentParser.parse(from: dicomFile.dataSet)
                
                // Generate output filename
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let fileExtension = document.documentType.fileExtension
                let outputFileURL = outputDirURL.appendingPathComponent("\(baseName).\(fileExtension)")
                
                // Write document data, without the trailing padding (0042,0015)
                try EncapsulatedDocumentBuilder.OptionRules.documentBytes(document.documentData, in: dicomFile.dataSet)
                    .write(to: outputFileURL)
                
                successCount += 1
                extractedFiles.append(outputFileURL.path)
                
                if verbose {
                    print("✓ \(fileURL.lastPathComponent) → \(outputFileURL.lastPathComponent)")
                }
            } catch {
                failureCount += 1
                if verbose {
                    print("✗ \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        // Summary
        print()
        print("Extraction complete:")
        print("  Successful: \(successCount)")
        if failureCount > 0 {
            print("  Failed: \(failureCount)")
        }
        print("  Output directory: \(outputDirURL.path)")
        // D271: like dicom-convert's directory run (P-CONVERT-EXIT), a run with any
        // failed document exits 1 after the summary; skipped files do not count.
        if failureCount > 0 {
            throw ExitCode.failure
        }
    }
    
    // MARK: - Encapsulation Mode
    
    private func encapsulateFile(inputPath: String, outputPath: String?) throws {
        if verbose {
            print("Encapsulating document: \(inputPath)")
        }
        
        // Read document file
        let documentData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        
        // Detect document type from file extension (shared DICOMKit mapping)
        let inputURL = URL(fileURLWithPath: inputPath)
        let documentType = EncapsulatedDocumentType(fileExtension: inputURL.pathExtension)

        // Validate required metadata for encapsulation
        guard let patientName = patientName, !patientName.isEmpty else {
            throw ValidationError("Patient's Name is required for encapsulation (--patient-name)")
        }

        guard let patientId = patientId, !patientId.isEmpty else {
            throw ValidationError("Patient ID is required for encapsulation (--patient-id)")
        }

        // Generate UIDs if not provided (shared UIDGenerator — same as the app).
        let finalStudyUID = studyUid ?? UIDGenerator.generateUID().value
        let finalSeriesUID = seriesUid ?? UIDGenerator.generateUID().value

        if hl7InstanceIdentifier != nil, documentType != .cda {
            throw ValidationError("--hl7-instance-identifier applies to CDA documents only (HL7 Instance Identifier (0040,E001) is Type 1C, required if the document is CDA; PS3.3 Table C.24-2)")
        }

        let dataSet = try encapsulatedDataSet(
            documentData: documentData, documentType: documentType,
            patientName: patientName, patientID: patientId,
            studyUID: finalStudyUID, seriesUID: finalSeriesUID,
            instanceNumber: instanceNumber, hl7Override: hl7InstanceIdentifier)
        
        // Create DICOM file
        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            // F15: the file-meta Media Storage SOP Class UID must equal the dataset's
            // SOP Class UID (PS3.10), not default to Secondary Capture (1.1.7).
            sopClassUID: documentType.sopClassUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1" // Explicit VR Little Endian
        )
        
        // Write DICOM file
        let dicomData = try dicomFile.write()
        
        // Determine output path
        let finalOutputPath: String
        if let specifiedOutput = outputPath {
            finalOutputPath = specifiedOutput
        } else {
            finalOutputPath = inputURL.deletingPathExtension().appendingPathExtension("dcm").path
        }
        
        try dicomData.write(to: URL(fileURLWithPath: finalOutputPath))
        
        if verbose {
            print("✓ Encapsulated \(documentType) (\(EncapsulatedDocumentFormatting.fileSize(Int64(documentData.count))))")
            print("  DICOM size: \(EncapsulatedDocumentFormatting.fileSize(Int64(dicomData.count)))")
            print("  Patient: \(patientName) [\(patientId)]")
            print("  Study UID: \(finalStudyUID)")
            print("  Output: \(finalOutputPath)")
        } else {
            print("Encapsulated: \(finalOutputPath)")
        }
    }
    
    private func encapsulateFromDirectory(inputPath: String, outputPath: String?) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        
        // Determine output directory
        let outputDirURL: URL
        if let specifiedOutput = outputPath {
            outputDirURL = URL(fileURLWithPath: specifiedOutput)
        } else {
            outputDirURL = inputURL.appendingPathComponent("encapsulated")
        }
        
        // Create output directory
        try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
        
        if verbose {
            print("Encapsulating documents from: \(inputPath)")
            print("Output directory: \(outputDirURL.path)")
            print()
        }
        
        // Validate required metadata
        guard let patientName = patientName, !patientName.isEmpty else {
            throw ValidationError("Patient's Name is required for batch encapsulation (--patient-name)")
        }

        // One identifier cannot name several CDA documents.
        if hl7InstanceIdentifier != nil {
            throw ValidationError("--hl7-instance-identifier names one CDA document; in directory mode each CDA's /ClinicalDocument/id is used")
        }
        
        guard let patientId = patientId, !patientId.isEmpty else {
            throw ValidationError("Patient ID is required for batch encapsulation (--patient-id)")
        }
        
        var successCount = 0
        var failureCount = 0
        var instanceNum = instanceNumber ?? 1
        
        // Generate series UIDs once for the batch (shared UIDGenerator — same as the app).
        let finalStudyUID = studyUid ?? UIDGenerator.generateUID().value
        let finalSeriesUID = seriesUid ?? UIDGenerator.generateUID().value
        
        // Enumerate document files via the shared, sorted gatherer (same walk as the Workshop).
        let documentURLs = FileGatherer.regularFiles(under: inputURL) ?? []

        for fileURL in documentURLs {
            // Check if it's a supported document type (shared DICOMKit mapping)
            let documentType = EncapsulatedDocumentType(fileExtension: fileURL.pathExtension)
            guard documentType != .unknown else {
                if verbose {
                    print("⊘ \(fileURL.lastPathComponent): Unsupported file type")
                }
                continue
            }

            // Try to encapsulate this file
            do {
                let documentData = try Data(contentsOf: fileURL)

                // Batch uses the running instance counter.
                let dataSet = try encapsulatedDataSet(
                    documentData: documentData, documentType: documentType,
                    patientName: patientName, patientID: patientId,
                    studyUID: finalStudyUID, seriesUID: finalSeriesUID,
                    instanceNumber: instanceNum, hl7Override: nil)
                
                // Create DICOM file
                let dicomFile = DICOMFile.create(
                    dataSet: dataSet,
                    sopClassUID: documentType.sopClassUID,  // F15: match dataset SOP class (PS3.10)
                    transferSyntaxUID: "1.2.840.10008.1.2.1"
                )
                
                let dicomData = try dicomFile.write()
                
                // Generate output filename
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let outputFileURL = outputDirURL.appendingPathComponent("\(baseName).dcm")
                
                try dicomData.write(to: outputFileURL)
                
                successCount += 1
                instanceNum += 1
                
                if verbose {
                    print("✓ \(fileURL.lastPathComponent) → \(outputFileURL.lastPathComponent)")
                }
            } catch {
                failureCount += 1
                if verbose {
                    print("✗ \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        // Summary
        print()
        print("Encapsulation complete:")
        print("  Successful: \(successCount)")
        if failureCount > 0 {
            print("  Failed: \(failureCount)")
        }
        print("  Study UID: \(finalStudyUID)")
        print("  Series UID: \(finalSeriesUID)")
        print("  Output directory: \(outputDirURL.path)")
        // D271: like dicom-convert's directory run (P-CONVERT-EXIT), a run with any
        // failed file exits 1 after the summary.
        if failureCount > 0 {
            throw ExitCode.failure
        }
    }
    
    // MARK: - Helper Methods

    /// The dataset of one encapsulated document: the shared builder option chain,
    /// then this tool's options (Conversion Type, Burned In Annotation, HL7
    /// Instance Identifier) and the attributes the builder leaves out
    /// (Encapsulated Document Length, Specific Character Set).
    func encapsulatedDataSet(
        documentData: Data,
        documentType: EncapsulatedDocumentType,
        patientName: String,
        patientID: String,
        studyUID: String,
        seriesUID: String,
        instanceNumber: Int?,
        hl7Override: String?
    ) throws -> DataSet {
        // Determine modality (explicit override, else the document-type default).
        // resolve() normalizes aliases and honours --strict-modality.
        let finalModality = try ModalityOptionValidator.resolve(
            modality, strict: strictModality, verbose: verbose)
            ?? documentType.defaultModality

        // Build encapsulated document (shared option chain).
        let builder = EncapsulatedDocumentBuilder(
            documentData: documentData,
            mimeType: documentType.expectedMIMEType,
            documentType: documentType,
            studyInstanceUID: studyUID,
            seriesInstanceUID: seriesUID
        )
        .applyStandardOptions(
            patientName: patientName,
            patientID: patientID,
            modality: finalModality,
            title: title,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            instanceNumber: instanceNumber
        )
        if let conversionType {
            builder.setConversionType(try PDFOptionValues.conversionType(conversionType))
        }
        if let burnedInAnnotation {
            builder.setBurnedInAnnotation(try PDFOptionValues.burnedInAnnotation(burnedInAnnotation))
        }
        if documentType == .cda {
            guard let identifier = hl7Override ?? EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(fromCDA: documentData) else {
                throw ValidationError("HL7 Instance Identifier (0040,E001) is required for a CDA document (PS3.3 Table C.24-2) and /ClinicalDocument/id has no root; pass --hl7-instance-identifier")
            }
            builder.setHL7InstanceIdentifier(identifier)
        }

        var dataSet = try builder.buildDataSet()
        EncapsulatedDocumentBuilder.OptionRules.complete(&dataSet, documentByteCount: documentData.count)
        return dataSet
    }
    //
    // Document-type ↔ file-extension mapping, default modality, the byte-size
    // formatter, the `--show-metadata` report, and the builder option chain all
    // moved to DICOMKit's shared `EncapsulatedDocumentWorkflow` so the CLI and the
    // Studio reimplementation cannot drift. UID generation now uses the shared
    // `UIDGenerator` (DICOMCore) — the same generator the app uses.
}

enum ExportFormat: String, ExpressibleByArgument {
    case pdf
    case xml
    case stl
    case obj
    case mtl
    case dicom
}

DICOMPdf.main()

