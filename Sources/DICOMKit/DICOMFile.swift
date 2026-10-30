// NEMA-verified: 2026a, checked 2026-09-29 — PS3.10 2026a 7.1 preamble and prefix rules; the VR sniff list is the 34 VRs of PS3.5 2026a Table 6.2-1 (OV, SV, UV added)
import Foundation

/// DICOM File
///
/// Represents a DICOM Part 10 file with File Meta Information and main data set.
/// Also supports legacy DICOM files without the standard preamble and DICM prefix.
/// Reference: DICOM PS3.10 Section 7 - DICOM File Format
public struct DICOMFile: Sendable {
    /// File Meta Information (Group 0002 elements)
    ///
    /// Contains metadata about the file, including Transfer Syntax UID.
    /// Reference: PS3.10 Section 7.1
    public let fileMetaInformation: DataSet
    
    /// Main data set (all elements after File Meta Information)
    public let dataSet: DataSet
    
    /// Creates a DICOM file
    /// - Parameters:
    ///   - fileMetaInformation: File Meta Information data set
    ///   - dataSet: Main data set
    public init(fileMetaInformation: DataSet, dataSet: DataSet) {
        self.fileMetaInformation = fileMetaInformation
        self.dataSet = dataSet
    }
    
    /// Reads a DICOM file from data
    ///
    /// Validates the 128-byte preamble and "DICM" prefix per PS3.10 Section 7.1.
    /// Parses File Meta Information and main data set using Explicit VR Little Endian.
    ///
    /// - Parameter data: Raw file data
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if file is invalid or parsing fails
    public static func read(from data: Data) throws -> DICOMFile {
        return try read(from: data, force: false)
    }
    
    /// Reads a DICOM file from data with optional forced parsing
    ///
    /// When `force` is false (default), validates the 128-byte preamble and "DICM" prefix
    /// per PS3.10 Section 7.1.
    ///
    /// When `force` is true, attempts to parse the file even without the standard
    /// DICM prefix. This enables reading legacy DICOM files that:
    /// - Were created before the Part 10 standard
    /// - Start directly with data elements (no preamble)
    /// - Use non-standard file formats
    ///
    /// For legacy files without File Meta Information, assumes Implicit VR Little Endian
    /// transfer syntax (the DICOM default).
    ///
    /// - Parameters:
    ///   - data: Raw file data
    ///   - force: If true, attempts to parse files without DICM prefix
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if file is invalid or parsing fails
    public static func read(from data: Data, force: Bool) throws -> DICOMFile {
        return try read(from: data, force: force, options: .default)
    }
    
    /// Reads a DICOM file from data with parsing options
    ///
    /// Supports advanced parsing options including:
    /// - Metadata-only parsing (skip pixel data)
    /// - Lazy pixel data loading (defer loading until access)
    /// - Memory-mapped file access (for large files)
    /// - Partial parsing (stop after specific tag)
    ///
    /// - Parameters:
    ///   - data: Raw file data
    ///   - force: If true, attempts to parse files without DICM prefix
    ///   - options: Parsing options controlling behavior
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if file is invalid or parsing fails
    public static func read(from data: Data, force: Bool = false, options: ParsingOptions) throws -> DICOMFile {
        try validateStrictOptions(force: force, options: options)
        if options.validationPolicy == .strict,
           data.count > options.strictResourceLimits.maximumInputBytes {
            throw StrictParsingError.resourceLimitExceeded(
                resource: .inputBytes, limit: options.strictResourceLimits.maximumInputBytes)
        }
        // Rebase sliced input once at the public boundary. The parse pipeline below
        // (hasDICMPrefix, DICOMParser) mixes slice-relative reads (readUInt16LE et al.
        // add `startIndex`) with absolute indexing (`subdata(in:)`, `data[128..<132]`);
        // on a Data slice with a non-zero startIndex the two index spaces disagree —
        // silent misreads or a trap (caught by SliceIndependenceTests). Free for the
        // normal case: `Data(data)` only copies when the input actually is a slice.
        // The zero-copy replacement is WP-B borrowed windows (copy map, §19).
        let data = data.startIndex == 0 ? data : Data(data)
        // Check if this is a standard Part 10 file with DICM prefix
        if hasDICMPrefix(data) {
            return try readPart10File(from: data, options: options)
        }
        
        // Not a standard Part 10 file
        if force {
            // Try to parse as legacy DICOM file
            return try readLegacyFile(from: data, options: options)
        } else {
            // Require DICM prefix by default
            if data.count < 132 {
                throw DICOMError.unexpectedEndOfData
            }
            throw DICOMError.invalidDICMPrefix
        }
    }
    
    /// Reads a DICOM file from URL with parsing options
    ///
    /// Supports reading from file URL with advanced parsing options.
    /// Can use memory-mapped file access for large files when specified in options.
    ///
    /// - Parameters:
    ///   - url: File URL to read from
    ///   - force: If true, attempts to parse files without DICM prefix
    ///   - options: Parsing options controlling behavior
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if file is invalid or parsing fails
    public static func read(from url: URL, force: Bool = false, options: ParsingOptions = .default) throws -> DICOMFile {
        if options.validationPolicy == .strict {
            try validateStrictOptions(force: force, options: options)
            // Strict URL ingestion is local-file-only and bounded, even if the file
            // grows while being read. A size preflight alone would permit that race.
            guard url.isFileURL else { throw StrictParsingError.invalidOptions }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let limit = options.strictResourceLimits.maximumInputBytes
            var data = Data()
            while true {
                let remaining = limit - data.count
                // At the boundary, probe just one byte for EOF; never append it.
                let count = remaining == 0 ? 1 : min(64 * 1024, remaining)
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                guard chunk.count <= remaining else {
                    throw StrictParsingError.resourceLimitExceeded(resource: .inputBytes, limit: limit)
                }
                data.append(chunk)
            }
            return try read(from: data, force: force, options: options)
        }
        // `useMemoryMapping` maps the file (.mappedIfSafe) so pages are faulted
        // in on demand instead of read eagerly — the file must not be modified
        // while the parsed structures are alive.
        let source = try FileByteSource(url: url, mapped: options.useMemoryMapping)
        return try read(from: source.wholeData(), force: force, options: options)
    }
    
    #if canImport(Darwin) || canImport(Glibc)
    /// Compatibility options adapter. Build `BoundedParsingOptions` before entering
    /// a managed operation to keep caller-owned Set/String policy storage outside it.
    public static func readBounded(from source: borrowing VerifiedFileByteSource,
                                   options: ParsingOptions, cancellation: DICOMCancellation = .never)
        throws -> BoundedDICOMFile {
        try readBounded(from: source, options: BoundedParsingOptions(options), cancellation: cancellation)
    }

    /// Strict full structural parsing through the canonical parser over verified windows.
    /// This value-outcome core does not invoke Swift's throwing runtime.
    public static func readBoundedOutcome(from source: borrowing VerifiedFileByteSource,
                                          options: BoundedParsingOptions,
                                          cancellation: DICOMCancellation = .never)
        -> DICOMParserOutcome<BoundedDICOMFile> {
        guard source.count <= options.strictResourceLimits.maximumInputBytes else {
            return .failure(.strict(.resourceLimitExceeded(resource: .inputBytes,
                limit: options.strictResourceLimits.maximumInputBytes)))
        }
        if case .failure(let failure) = source.validateOutcome(cancellation: cancellation) {
            return .failure(.managed(failure))
        }
        guard source.count >= 132 else { return .failure(.managed(DICOMManagedFailure(.unexpectedEnd))) }
        switch source.readOutcome(128..<132, resource: .metadata, cancellation: cancellation) {
        case .failure(let failure): return .failure(.managed(failure))
        case .success(let prefix):
            guard prefix.withBorrowedBytes({ $0[0] == 0x44 && $0[1] == 0x49 && $0[2] == 0x43 && $0[3] == 0x4D }) else {
                return .failure(.managed(DICOMManagedFailure(.invalidPrefix)))
            }
        }
        var failure = DICOMParserFailure.unexpectedEndOfData
        guard let storage = BoundedParseStorage.make(source: source).takeValue(failure: &failure) else {
            return .failure(failure)
        }
        let capture = storage.capture.withCancellation(cancellation)
        var parser = DICOMParser(source: source.view.withCancellation(cancellation), options: options, capture: capture)
        if case .failure(let failure) = parser.parseFileMetaInformationCore(startOffset: 132) {
            return .failure(failure)
        }
        guard let metaOwner = storage.share().takeValue(failure: &failure) else { return .failure(failure) }
        let meta = BoundedDICOMDataSet(storage: metaOwner, scope: 0)
        guard let optionalSyntax = meta.elementOutcome(for: .transferSyntaxUID).takeValue(failure: &failure) else {
            return .failure(failure)
        }
        guard let syntax = consume optionalSyntax, syntax.vr.characterRepertoire != nil, syntax.length > 0 else {
            return .failure(.strict(.missingTransferSyntax))
        }
        guard let transferSyntax = syntax.transferSyntaxToken(cancellation: cancellation)
            .takeValue(failure: &failure) else { return .failure(failure) }
        if case .failure(let failure) = parser.parseDataSetCore(transferSyntax: transferSyntax) {
            return .failure(failure)
        }
        if !transferSyntax.isExplicitVR,
           case .failure(let failure) = capture.resolveImplicitContextualVR() { return .failure(failure) }
        if case .failure(let failure) = capture.seal() { return .failure(failure) }
        return .success(BoundedDICOMFile(storage: storage, transferSyntax: transferSyntax))
    }

    /// Parse on the admitted worker. Retain execution through deferred acquisition
    /// and decoding until the complete synchronous worker operation actually returns.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public static func readBoundedOutcome(from source: borrowing VerifiedFileByteSource,
                                          options: BoundedParsingOptions,
                                          execution: borrowing DICOMExecutionReservation,
                                          cancellation: DICOMCancellation = .never)
        -> DICOMParserOutcome<BoundedDICOMFile> {
        if case .failure(let failure) = source.validateExecutionOutcome(execution) {
            return .failure(.managed(failure))
        }
        return readBoundedOutcome(from: source, options: options, cancellation: cancellation)
    }

    /// Throwing compatibility adapter outside the qualified operation boundary.
    public static func readBounded(from source: borrowing VerifiedFileByteSource,
                                   options: BoundedParsingOptions, cancellation: DICOMCancellation = .never)
        throws(DICOMParserFailure) -> BoundedDICOMFile {
        try readBoundedOutcome(from: source, options: options, cancellation: cancellation).get()
    }

    /// Throwing compatibility adapter; use readBoundedOutcome inside admitted work.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public static func readBounded(from source: borrowing VerifiedFileByteSource,
                                   options: BoundedParsingOptions,
                                   execution: borrowing DICOMExecutionReservation,
                                   cancellation: DICOMCancellation = .never)
        throws(DICOMParserFailure) -> BoundedDICOMFile {
        try readBoundedOutcome(from: source, options: options, execution: execution, cancellation: cancellation).get()
    }
    #endif

    private static func validateStrictOptions(force: Bool, options: ParsingOptions) throws {
        if options.validationPolicy == .strict {
            guard !force, options.mode == .full, options.stopAfterTag == nil,
                  options.maxElements.map({ $0 > 0 }) ?? true,
                  options.strictResourceLimits.isValid else {
                throw StrictParsingError.invalidOptions
            }
            if let allowed = options.allowedTransferSyntaxUIDs {
                guard allowed.isSubset(of: ParsingOptions.strictNativeTransferSyntaxUIDs
                    .union(ParsingOptions.strictCompressedTransferSyntaxUIDs)) else {
                    throw StrictParsingError.invalidOptions
                }
                if !allowed.isDisjoint(with: ParsingOptions.strictCompressedTransferSyntaxUIDs) {
                    guard options.strictEncapsulation, options.maximumEncapsulatedBytes > 0,
                          options.maxFragmentCount.map({ $0 > 0 }) ?? true else {
                        throw StrictParsingError.invalidOptions
                    }
                }
            }
        }
    }

    /// Checks if the data has a valid DICM prefix at offset 128
    ///
    /// - Parameter data: Raw file data
    /// - Returns: true if DICM prefix is present
    private static func hasDICMPrefix(_ data: Data) -> Bool {
        guard data.count >= 132 else {
            return false
        }
        
        let dicmOffset = 128
        let dicmBytes = data[dicmOffset..<dicmOffset+4]
        return dicmBytes.elementsEqual([0x44, 0x49, 0x43, 0x4D]) // "DICM" in ASCII
    }
    
    /// Reads a standard DICOM Part 10 file with preamble and DICM prefix
    ///
    /// - Parameters:
    ///   - data: Raw file data
    ///   - options: Parsing options controlling behavior
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if parsing fails
    private static func readPart10File(from data: Data, options: ParsingOptions = .default) throws -> DICOMFile {
        // Parse File Meta Information (starts at offset 132, after DICM prefix)
        var parser = DICOMParser(data: data, options: options)
        let fileMetaInfo = try parser.parseFileMetaInformation(startOffset: 132)
        
        // Get Transfer Syntax UID from File Meta Information
        // Default to Explicit VR Little Endian if not specified
        if options.validationPolicy == .strict {
            guard let uid = fileMetaInfo.string(for: .transferSyntaxUID), !uid.isEmpty else {
                throw StrictParsingError.missingTransferSyntax
            }
        }
        let transferSyntaxUID = fileMetaInfo.string(for: .transferSyntaxUID) ?? "1.2.840.10008.1.2.1"
        
        // Parse main data set
        let mainDataSet = try parser.parseDataSet(transferSyntaxUID: transferSyntaxUID)
        
        return DICOMFile(fileMetaInformation: fileMetaInfo, dataSet: mainDataSet)
    }
    
    /// Reads a legacy DICOM file without preamble and DICM prefix
    ///
    /// Legacy files start directly with data elements. This method uses heuristics
    /// to detect valid DICOM content and determine the transfer syntax.
    ///
    /// - Parameters:
    ///   - data: Raw file data
    ///   - options: Parsing options controlling behavior
    /// - Returns: Parsed DICOM file
    /// - Throws: DICOMError if parsing fails
    private static func readLegacyFile(from data: Data, options: ParsingOptions = .default) throws -> DICOMFile {
        // Need at least 8 bytes for a minimal data element
        guard data.count >= 8 else {
            throw DICOMError.unexpectedEndOfData
        }
        
        // Detect if this looks like valid DICOM data
        guard looksLikeDICOMData(data) else {
            throw DICOMError.parsingFailed("Data does not appear to be a valid DICOM file")
        }
        
        // Legacy files typically use Implicit VR Little Endian (the DICOM default)
        // But some may use Explicit VR - try to detect based on VR bytes
        let transferSyntaxUID = detectTransferSyntax(from: data)
        
        var parser = DICOMParser(data: data, options: options)
        
        // Check if there's File Meta Information (group 0002) at the start
        if let groupNumber = data.readUInt16LE(at: 0), groupNumber == 0x0002 {
            // Has File Meta Information - parse it first
            let fileMetaInfo = try parser.parseFileMetaInformation(startOffset: 0)
            
            // Use transfer syntax from meta info if available, otherwise use detected one
            let actualTransferSyntaxUID = fileMetaInfo.string(for: .transferSyntaxUID) ?? transferSyntaxUID
            
            let mainDataSet = try parser.parseDataSet(transferSyntaxUID: actualTransferSyntaxUID)
            return DICOMFile(fileMetaInformation: fileMetaInfo, dataSet: mainDataSet)
        } else {
            // No File Meta Information - parse directly as main data set
            let mainDataSet = try parser.parseDataSet(startOffset: 0, transferSyntaxUID: transferSyntaxUID)
            return DICOMFile(fileMetaInformation: DataSet(elements: []), dataSet: mainDataSet)
        }
    }
    
    /// Heuristically checks if data looks like valid DICOM content
    ///
    /// Checks for valid DICOM tag patterns at the start of the data.
    /// Valid DICOM data typically starts with common groups like 0x0002, 0x0008, etc.
    ///
    /// - Parameter data: Raw file data
    /// - Returns: true if data appears to be DICOM
    private static func looksLikeDICOMData(_ data: Data) -> Bool {
        guard data.count >= 4 else {
            return false
        }
        
        // Read the first two bytes as a group number (Little Endian)
        guard let groupNumber = data.readUInt16LE(at: 0) else {
            return false
        }
        
        // Valid DICOM group numbers are even (per DICOM standard)
        // Odd group numbers are private, but still valid
        // Common standard groups: 0x0002, 0x0008, 0x0010, 0x0018, 0x0020, etc.
        
        // Check for typical DICOM starting groups
        let validStartingGroups: [UInt16] = [
            0x0002, // File Meta Information
            0x0008, // Identifying Information
            0x0010, // Patient Information
            0x0018, // Acquisition Information
            0x0020, // Relationship Information
            0x0028, // Image Presentation
            0x0032, // Study Information
            0x0038, // Visit Information
            0x0040  // Procedure Information
        ]
        
        if validStartingGroups.contains(groupNumber) {
            return true
        }
        
        // Also accept any even group number < 0x7FFF as potentially valid
        // (excluding private groups which start with odd numbers)
        if groupNumber % 2 == 0 && groupNumber < 0x7FFF && groupNumber != 0 {
            return true
        }
        
        return false
    }
    
    /// Detects the transfer syntax by examining the VR encoding
    ///
    /// Looks at the bytes following the first tag to determine if VR is explicit.
    /// If bytes 4-5 look like valid ASCII VR codes, assumes Explicit VR.
    ///
    /// - Parameter data: Raw file data
    /// - Returns: Detected transfer syntax UID
    private static func detectTransferSyntax(from data: Data) -> String {
        // Need at least 6 bytes to check for VR
        guard data.count >= 6 else {
            // Default to Implicit VR Little Endian
            return "1.2.840.10008.1.2"
        }
        
        // Check bytes 4-5 for potential VR (ASCII characters)
        let byte4 = data[4]
        let byte5 = data[5]
        
        // Valid VR codes are two uppercase ASCII letters
        if isUppercaseASCII(byte4) && isUppercaseASCII(byte5) {
            // Check if it's a known VR code
            if let vrString = String(bytes: [byte4, byte5], encoding: .ascii),
               isKnownVR(vrString) {
                // Looks like Explicit VR
                return "1.2.840.10008.1.2.1" // Explicit VR Little Endian
            }
        }
        
        // Default to Implicit VR Little Endian
        return "1.2.840.10008.1.2"
    }
    
    /// Checks if a byte is an uppercase ASCII letter (A-Z)
    private static func isUppercaseASCII(_ byte: UInt8) -> Bool {
        return byte >= 0x41 && byte <= 0x5A // 'A' to 'Z'
    }
    
    /// Checks if a string is a known DICOM VR code
    private static func isKnownVR(_ vrString: String) -> Bool {
        // The 34 VRs of PS3.5 Table 6.2-1
        let knownVRs = [
            "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS",
            "LO", "LT", "OB", "OD", "OF", "OL", "OV", "OW", "PN", "SH", "SL",
            "SQ", "SS", "ST", "SV", "TM", "UC", "UI", "UL", "UN", "UR", "US", "UT", "UV"
        ]
        return knownVRs.contains(vrString)
    }
    
    /// Transfer Syntax UID from File Meta Information
    ///
    /// Returns the Transfer Syntax UID (0002,0010) if present.
    public var transferSyntaxUID: String? {
        return fileMetaInformation.string(for: .transferSyntaxUID)
    }
    
    /// SOP Class UID from main data set
    ///
    /// Returns the SOP Class UID (0008,0016) if present.
    public var sopClassUID: String? {
        return dataSet.string(for: .sopClassUID)
    }
    
    /// SOP Instance UID from main data set
    ///
    /// Returns the SOP Instance UID (0008,0018) if present.
    public var sopInstanceUID: String? {
        return dataSet.string(for: .sopInstanceUID)
    }
}
