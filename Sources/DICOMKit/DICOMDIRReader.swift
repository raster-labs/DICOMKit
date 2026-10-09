// NEMA-verified: 2026a, checked 2026-10-01 — PS3.3 2026a Table F.3-3, Table F.4-1 and F.6.1: unknown record types are skipped, not fatal (D14); the tree follows the F.3.2.2 / Table F.3-3 offsets (0004,1200), (0004,1400), (0004,1420) from the first byte of the File Meta Information, sequence order only when they cannot be followed, PRIVATE records kept where the offsets place them, Record In-use Flag other than 0000H read as FFFFH (D240); every Series-level record type of Table F.4-1 is kept under its SERIES and HANGING PROTOCOL / PALETTE / IMPLANT* / INVENTORY at the root (D232); the profile is an assumption, no attribute carries it (D15)
import Foundation
import DICOMCore

/// DICOMDIR Reader
///
/// Reads and parses DICOMDIR files (Media Storage Directory).
/// Reference: DICOM PS3.10 - Media Storage and File Format
/// Reference: DICOM PS3.3 F.5 - Media Storage Directory SOP Class
public struct DICOMDIRReader {
    /// Read a DICOMDIR file from data
    ///
    /// - Parameter data: Raw DICOMDIR file data
    /// - Returns: Parsed DICOMDIR structure
    /// - Throws: DICOMError if parsing fails
    public static func read(from data: Data) throws -> DICOMDirectory {
        // Read as a standard DICOM file
        let dicomFile = try DICOMFile.read(from: data)
        
        // Verify it's a DICOMDIR (SOP Class UID should be 1.2.840.10008.1.3.10)
        let sopClassUID = dicomFile.fileMetaInformation.string(for: .mediaStorageSOPClassUID)
        guard sopClassUID == "1.2.840.10008.1.3.10" else {
            throw DICOMError.parsingFailed("Not a valid DICOMDIR file (incorrect SOP Class UID)")
        }
        
        return try parse(dataSet: dicomFile.dataSet, itemByteOffsets: directoryRecordItemOffsets(in: data))
    }
    
    /// Read a DICOMDIR file from URL
    ///
    /// - Parameter url: File URL to the DICOMDIR file
    /// - Returns: Parsed DICOMDIR structure
    /// - Throws: DICOMError if reading or parsing fails
    public static func read(from url: URL) throws -> DICOMDirectory {
        let data = try Data(contentsOf: url)
        return try read(from: data)
    }
    
    /// Parse a DICOMDIR from a DataSet
    ///
    /// - Parameter dataSet: DICOM DataSet containing directory information
    /// - Returns: Parsed DICOMDIR structure
    /// - Throws: DICOMError if parsing fails
    /// - Parameter itemByteOffsets: Byte offset of each Directory Record Sequence item, from the
    ///   first byte of the File Meta Information (PS3.3 F.3.2.2), in sequence order; nil when
    ///   the file bytes are not at hand, and the tree is then rebuilt from the sequence order.
    static func parse(dataSet: DataSet, itemByteOffsets: [Int]? = nil) throws -> DICOMDirectory {
        // Extract file-set metadata
        let fileSetID = dataSet.string(for: .fileSetID) ?? ""
        let specificCharacterSet = dataSet.string(for: .specificCharacterSet)
        
        // Extract file-set descriptor information
        let fileSetDescriptorFileID = dataSet.strings(for: .fileSetDescriptorFileID)
        let specificCharacterSetOfFileSetDescriptorFile = dataSet.string(for: .specificCharacterSetOfFileSetDescriptorFile)
        
        // Extract consistency flag
        let consistencyFlag = dataSet.uint16(for: .fileSetConsistencyFlag) ?? 0x0000
        let isConsistent = (consistencyFlag == 0x0000)
        
        // Parse directory record sequence
        let rootRecords = try parseDirectoryRecordSequence(dataSet: dataSet, itemByteOffsets: itemByteOffsets)
        
        // No DICOMDIR attribute carries the PS3.11 Application Profile; it is conformance
        // metadata of the medium. The type's default (STD-GEN-CD) is an assumption, and a
        // caller that knows the medium sets `profile` itself.
        return DICOMDirectory(
            fileSetID: fileSetID,
            specificCharacterSet: specificCharacterSet,
            fileSetDescriptorFileID: fileSetDescriptorFileID,
            specificCharacterSetOfFileSetDescriptorFile: specificCharacterSetOfFileSetDescriptorFile,
            rootRecords: rootRecords,
            isConsistent: isConsistent
        )
    }
    
    /// Parse the Directory Record Sequence
    ///
    /// PS3.3 2026a F.3.2.2: the Root Directory Entity starts at Offset of the First Directory
    /// Record of the Root Directory Entity (0004,1200); each Directory Entity is a chain of
    /// records linked by Offset of the Next Directory Record (0004,1400), and a record's
    /// lower-level entity starts at Offset of Referenced Lower-Level Directory Entity
    /// (0004,1420). The tree is built from those offsets when the item byte offsets are known
    /// and every offset lands on an item; otherwise (no file bytes, offsets all zero, or an
    /// offset that does not resolve) it falls back to the sequence order.
    ///
    /// - Parameters:
    ///   - dataSet: DataSet containing the sequence
    ///   - itemByteOffsets: Byte offset of each item, in sequence order, when known
    /// - Returns: Array of root directory records
    /// - Throws: DICOMError if parsing fails
    private static func parseDirectoryRecordSequence(
        dataSet: DataSet, itemByteOffsets: [Int]?
    ) throws -> [DirectoryRecord] {
        guard let items = dataSet.sequence(for: .directoryRecordSequence) else {
            // No directory records
            return []
        }

        // First pass: parse every item (nil for a record type this reader does not know)
        let parsed = try items.map { try parseDirectoryRecord(from: $0) }

        if let offsets = itemByteOffsets, offsets.count == items.count,
           let roots = recordTree(items: items, parsed: parsed, itemByteOffsets: offsets,
                                  rootFirstOffset: dataSet.uint32(for: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity) ?? 0) {
            return roots
        }
        return sequenceOrderTree(parsed)
    }

    /// Byte offset of each Directory Record Sequence (0004,1220) item — the first byte of its
    /// Item tag (FFFE,E000) — counted from the first byte of the File Meta Information (the
    /// File Preamble, PS3.10 7.1), as PS3.3 2026a Table F.3-3 defines the navigation offsets.
    /// Walks Explicit or Implicit VR Little Endian data, defined or undefined lengths; nil for
    /// another Transfer Syntax, a file without the 128-byte preamble and "DICM", or bytes that
    /// do not parse.
    static func directoryRecordItemOffsets(in data: Data) -> [Int]? {
        let b = [UInt8](data)
        let undefined = 0xFFFF_FFFF
        func u16(_ i: Int) -> Int? { i + 2 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : nil }
        func u32(_ i: Int) -> Int? {
            guard i + 4 <= b.count else { return nil }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"]
        // (group, element, value start, value length) of the element at `at`
        func header(_ at: Int, explicit: Bool) -> (Int, Int, Int, Int)? {
            guard let group = u16(at), let element = u16(at + 2) else { return nil }
            if group == 0xFFFE || !explicit {
                guard let length = u32(at + 4) else { return nil }
                return (group, element, at + 8, length)
            }
            guard at + 6 <= b.count, let vr = String(bytes: b[(at + 4)..<(at + 6)], encoding: .ascii) else { return nil }
            if longVRs.contains(vr) {
                guard let length = u32(at + 8) else { return nil }
                return (group, element, at + 12, length)
            }
            guard let length = u16(at + 6) else { return nil }
            return (group, element, at + 8, length)
        }
        // End of an undefined-length value (items up to the Sequence Delimitation Item)
        func endOfUndefinedValue(_ start: Int, explicit: Bool, depth: Int) -> Int? {
            guard depth < 64 else { return nil }
            var at = start
            while case let (group, element, value, length)? = header(at, explicit: explicit), group == 0xFFFE {
                if element == 0xE0DD { return value }
                guard element == 0xE000 else { return nil }
                if length == undefined {
                    guard let end = endOfUndefinedItem(value, explicit: explicit, depth: depth + 1) else { return nil }
                    at = end
                } else {
                    at = value + length
                }
            }
            return nil
        }
        // End of an undefined-length item (elements up to the Item Delimitation Item)
        func endOfUndefinedItem(_ start: Int, explicit: Bool, depth: Int) -> Int? {
            var at = start
            while case let (group, element, value, length)? = header(at, explicit: explicit) {
                if group == 0xFFFE, element == 0xE00D { return value }
                if length == undefined {
                    guard let end = endOfUndefinedValue(value, explicit: explicit, depth: depth + 1) else { return nil }
                    at = end
                } else {
                    at = value + length
                }
                guard at <= b.count else { return nil }
            }
            return nil
        }

        guard b.count >= 132, b[128] == 0x44, b[129] == 0x49, b[130] == 0x43, b[131] == 0x4D else { return nil }
        // File Meta Information: group 0002, always Explicit VR Little Endian (PS3.10 7.1)
        var at = 132
        var transferSyntax = ""
        while case let (group, element, value, length)? = header(at, explicit: true), group == 0x0002 {
            guard length != undefined, value + length <= b.count else { return nil }
            if element == 0x0010 {
                transferSyntax = String(decoding: b[value..<(value + length)], as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            }
            at = value + length
        }
        let explicit: Bool
        switch transferSyntax {
        case "1.2.840.10008.1.2.1": explicit = true
        case "1.2.840.10008.1.2": explicit = false
        default: return nil
        }
        // Top-level elements up to the Directory Record Sequence (0004,1220)
        while case let (group, element, value, length)? = header(at, explicit: explicit) {
            if group == 0x0004, element == 0x1220 {
                var offsets: [Int] = []
                var item = value
                let end = length == undefined ? nil : value + length
                while end.map({ item < $0 }) ?? true,
                      case let (g, e, itemValue, itemLength)? = header(item, explicit: explicit), g == 0xFFFE {
                    if e == 0xE0DD { break }
                    guard e == 0xE000 else { return nil }
                    offsets.append(item)
                    if itemLength == undefined {
                        guard let next = endOfUndefinedItem(itemValue, explicit: explicit, depth: 1) else { return nil }
                        item = next
                    } else {
                        item = itemValue + itemLength
                    }
                }
                return offsets
            }
            if length == undefined {
                guard let end = endOfUndefinedValue(value, explicit: explicit, depth: 0) else { return nil }
                at = end
            } else {
                at = value + length
            }
        }
        return nil
    }

    /// The record tree by the PS3.3 F.3.2.2 offsets, or nil when an offset does not land on an
    /// item, a record is reached twice, or the root offset is 0 although records exist.
    /// A record of a type this reader does not know is skipped with its lower-level entity
    /// (F.6.1); PRIVATE records are kept where the offsets place them.
    static func recordTree(
        items: [SequenceItem], parsed: [DirectoryRecord?], itemByteOffsets: [Int], rootFirstOffset: UInt32
    ) -> [DirectoryRecord]? {
        guard !items.isEmpty else { return [] }
        guard rootFirstOffset != 0 else { return nil }
        var indexByOffset: [Int: Int] = [:]
        for (index, offset) in itemByteOffsets.enumerated() { indexByOffset[offset] = index }
        var visited = Set<Int>()

        func entity(startingAt first: UInt32) -> [DirectoryRecord]? {
            var records: [DirectoryRecord] = []
            var offset = first
            while offset != 0 {
                guard let index = indexByOffset[Int(offset)], visited.insert(index).inserted else { return nil }
                let item = items[index]
                let lower = item[.offsetOfReferencedLowerLevelDirectoryEntity]?.uint32Value ?? 0
                if var record = parsed[index] {
                    if lower != 0 {
                        guard let children = entity(startingAt: lower) else { return nil }
                        record.children = children
                    }
                    records.append(record)
                }
                offset = item[.offsetOfTheNextDirectoryRecord]?.uint32Value ?? 0
            }
            return records
        }
        return entity(startingAt: rootFirstOffset)
    }

    /// The record tree rebuilt from the sequence order (records in depth-first order), for a
    /// DICOMDIR whose offsets cannot be followed.
    private static func sequenceOrderTree(_ parsed: [DirectoryRecord?]) -> [DirectoryRecord] {
        // Build hierarchy: PATIENT -> STUDY -> SERIES -> instance records, plus the other
        // root-level records (PS3.3 2026a Table F.4-1)
        var patients: [DirectoryRecord] = []
        var otherRoots: [DirectoryRecord] = []
        let seriesLevelTypes = (DirectoryRecordType.series.allowedChildTypes ?? []).subtracting([.private])
        var currentPatient: DirectoryRecord?
        var currentStudy: DirectoryRecord?
        var currentSeries: DirectoryRecord?
        
        for case let record? in parsed {
            
            switch record.recordType {
            case .patient:
                // Save previous patient if any
                if var patient = currentPatient {
                    if var study = currentStudy {
                        if let series = currentSeries {
                            study.addChild(series)
                            currentSeries = nil
                        }
                        patient.addChild(study)
                        currentStudy = nil
                    }
                    patients.append(patient)
                }
                currentPatient = record
                
            case .study:
                // Close the open study (and its open series) into the current patient.
                // DirectoryRecord is a value type, so the mutated copies MUST be written
                // back or the accumulated children are lost.
                if var patient = currentPatient, var study = currentStudy {
                    if let series = currentSeries {
                        study.addChild(series)
                        currentSeries = nil
                    }
                    patient.addChild(study)
                    currentPatient = patient
                }
                currentStudy = record

            case .series:
                // Close the open series into the current study — writing the mutated
                // study back (value type), else earlier series/images are dropped.
                if var study = currentStudy, let series = currentSeries {
                    study.addChild(series)
                    currentStudy = study
                    currentSeries = nil
                }
                currentSeries = record
                
            case let type where seriesLevelTypes.contains(type):
                // Every Table F.4-1 record type of the Series Directory Entity (IMAGE, RT DOSE,
                // KEY OBJECT DOC, ENCAP DOC, RT TREAT RECORD, SPECTROSCOPY, RAW DATA, …)
                if var series = currentSeries {
                    series.addChild(record)
                    currentSeries = series
                }

            case let type where DirectoryRecordType.rootLevelTypes.contains(type) && type != .private:
                // HANGING PROTOCOL, PALETTE, IMPLANT, IMPLANT ASSY, IMPLANT GROUP, INVENTORY
                otherRoots.append(record)

            case .private:
                // PS3.3 2026a Table F.4-1: PRIVATE may appear under any record type; in sequence
                // order it belongs to the deepest open entity
                if var series = currentSeries {
                    series.addChild(record)
                    currentSeries = series
                } else if var study = currentStudy {
                    study.addChild(record)
                    currentStudy = study
                } else if var patient = currentPatient {
                    patient.addChild(record)
                    currentPatient = patient
                } else {
                    otherRoots.append(record)
                }

            default:
                // retired record types are skipped
                break
            }
        }
        
        // Save final records
        if var patient = currentPatient {
            if var study = currentStudy {
                if let series = currentSeries {
                    study.addChild(series)
                }
                patient.addChild(study)
            }
            patients.append(patient)
        }
        
        return patients + otherRoots
    }
    
    /// Parse a single directory record from a SequenceItem
    ///
    /// - Parameter item: SequenceItem for the record
    /// - Returns: Parsed directory record, or nil for a Directory Record Type this reader
    ///   does not know. PS3.3 F.6.1 lets a File-set Reader ignore privately defined
    ///   records and still find a conformant Directory; a type from a later edition is
    ///   treated the same way rather than failing the whole DICOMDIR.
    /// - Throws: DICOMError if the record has no Directory Record Type (Type 1)
    private static func parseDirectoryRecord(from item: SequenceItem) throws -> DirectoryRecord? {
        // Get record type
        guard let recordTypeString = item.string(for: .directoryRecordType)?
                .trimmingCharacters(in: .whitespaces) else {
            throw DICOMError.parsingFailed("Missing Directory Record Type (0004,1430)")
        }
        guard let recordType = DirectoryRecordType(rawValue: recordTypeString) else {
            return nil
        }
        
        // Get in-use flag
        // PS3.3 2026a Table F.3-3: values other than FFFFH (and the retired 0000H) "shall be
        // interpreted as FFFFH by File-set Readers"
        let inUseFlag = item[.recordInUseFlag]?.uint16Value ?? 0xFFFF
        let isActive = (inUseFlag != 0x0000)
        
        // Get referenced file information
        let referencedFileID = item.strings(for: .referencedFileID)
        let referencedSOPClassUID = item.string(for: .referencedSOPClassUIDInFile)
        let referencedSOPInstanceUID = item.string(for: .referencedSOPInstanceUIDInFile)
        let referencedTransferSyntaxUID = item.string(for: .referencedTransferSyntaxUIDInFile)
        
        // Extract all other attributes for this record
        var attributes: [Tag: DataElement] = [:]
        for tag in item.tags {
            // Skip navigation and reference tags (we handle those separately)
            if tag == .directoryRecordType || 
               tag == .recordInUseFlag ||
               tag == .offsetOfTheNextDirectoryRecord ||
               tag == .offsetOfReferencedLowerLevelDirectoryEntity ||
               tag == .referencedFileID ||
               tag == .referencedSOPClassUIDInFile ||
               tag == .referencedSOPInstanceUIDInFile ||
               tag == .referencedTransferSyntaxUIDInFile {
                continue
            }
            
            if let element = item[tag] {
                attributes[tag] = element
            }
        }
        
        return DirectoryRecord(
            recordType: recordType,
            referencedFileID: referencedFileID,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedTransferSyntaxUID: referencedTransferSyntaxUID,
            isActive: isActive,
            attributes: attributes,
            children: []
        )
    }
}
