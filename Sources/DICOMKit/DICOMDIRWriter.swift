// NEMA-verified: 2026a, checked 2026-10-01 — PS3.3 2026a F.3.2.2 offsets and Table F.3-3 record keys; Implementation Class UID is no longer the Deflated Transfer Syntax UID; (0002,0000) is computed by DICOMFile.write() (PS3.10 Table 7.1-1); the Builder adds the PS3.11 2026a Additional DICOMDIR Keys of the profile and its Icon Image Sequence (D239)
// NEMA-verified: 2026a, checked 2026-10-01 — Builder: one record per instance under its PATIENT/STUDY/SERIES records (PS3.3 2026a F.4, Table F.4-1; was first image per series, D129), of the record type PS3.3 F.5 gives its SOP Class with its Type 1/2 keys (D229, D230); File-set Consistency Flag always 0000H (Table F.3-3, D231); refuses File IDs outside PS3.10 2026a 8.2/8.5 (D131) and SOP Classes / Transfer Syntaxes the profile's PS3.11 2026a table does not list (DICOMDIRProfileRules, D70)
import Foundation
import DICOMCore

/// DICOMDIR Writer
///
/// Writes DICOMDIR files (Media Storage Directory).
/// Reference: DICOM PS3.10 - Media Storage and File Format
/// Reference: DICOM PS3.3 F.5 - Media Storage Directory SOP Class
public struct DICOMDIRWriter {
    /// Media Storage Directory SOP Class UID
    private static let mediaStorageDirectorySOPClassUID = "1.2.840.10008.1.3.10"
    
    /// Write a DICOMDIR to data
    ///
    /// - Parameter directory: DICOMDIR structure to write
    /// - Returns: Serialized DICOM file data
    /// - Throws: DICOMError if writing fails
    public static func write(_ directory: DICOMDirectory) throws -> Data {
        let layout = FlatLayout(rootRecords: directory.rootRecords)
        // The file meta must be IDENTICAL across both passes — it carries a freshly
        // generated Media Storage SOP Instance UID whose length can differ run-to-run,
        // which would shift every item's byte position between the probe and the final
        // encode and corrupt the measured offsets. Generate it once.
        let fileMeta = createFileMetaInformation()
        // Pass 1: encode with zero navigation offsets to measure each record item's byte
        // position in the serialized file.
        let probe = try encode(directory, layout: layout, fileMeta: fileMeta, itemByteOffsets: nil)
        let offsets = try Self.itemByteOffsets(in: probe, expectedCount: layout.records.count)
        // Pass 2: encode again with the real offsets. Every navigation offset is a fixed
        // 4-byte UL, so the byte layout is byte-for-byte identical to the probe — the
        // measured item positions stay valid, giving a DICOMDIR whose offsets an external
        // offset-following reader (pydicom/dcmtk) can navigate (PS3.10 8.5, PS3.3 F.3).
        return try encode(directory, layout: layout, fileMeta: fileMeta, itemByteOffsets: offsets)
    }

    /// Depth-first flattening of the record tree with per-node navigation links. The
    /// order (record, then its children recursively) MUST match `encode`'s serialization
    /// order so each record's next-sibling and first-child resolve to the right item.
    private struct FlatLayout {
        let records: [DirectoryRecord]
        let firstChild: [Int?]
        let nextSibling: [Int?]
        let rootIndices: [Int]

        init(rootRecords: [DirectoryRecord]) {
            var records: [DirectoryRecord] = []
            var firstChild: [Int?] = []
            var nextSibling: [Int?] = []
            func addLevel(_ siblings: [DirectoryRecord]) -> [Int] {
                var indices: [Int] = []
                for record in siblings {
                    let index = records.count
                    records.append(record)
                    firstChild.append(nil)
                    nextSibling.append(nil)
                    indices.append(index)
                    firstChild[index] = addLevel(record.children).first
                }
                for position in 0..<max(0, indices.count - 1) {
                    nextSibling[indices[position]] = indices[position + 1]
                }
                return indices
            }
            self.rootIndices = addLevel(rootRecords)
            self.records = records
            self.firstChild = firstChild
            self.nextSibling = nextSibling
        }
    }

    /// Serializes the directory. With `itemByteOffsets == nil` every navigation offset is
    /// written as 0 (the measuring pass); otherwise the real offsets are threaded in.
    private static func encode(
        _ directory: DICOMDirectory,
        layout: FlatLayout,
        fileMeta: DataSet,
        itemByteOffsets: [Int]?
    ) throws -> Data {
        var dataSet = DataSet()

        if !directory.fileSetID.isEmpty {
            dataSet[.fileSetID] = DataElement.string(tag: .fileSetID, vr: .CS, value: directory.fileSetID)
        }
        if let charset = directory.specificCharacterSet {
            dataSet[.specificCharacterSet] = DataElement.string(tag: .specificCharacterSet, vr: .CS, value: charset)
        }
        if let fileSetDescriptor = directory.fileSetDescriptorFileID {
            dataSet[.fileSetDescriptorFileID] = DataElement.strings(tag: .fileSetDescriptorFileID, vr: .CS, values: fileSetDescriptor)
        }
        if let charset = directory.specificCharacterSetOfFileSetDescriptorFile {
            dataSet[.specificCharacterSetOfFileSetDescriptorFile] = DataElement.string(tag: .specificCharacterSetOfFileSetDescriptorFile, vr: .CS, value: charset)
        }

        // Byte offset of the item at `index`, or 0 in the measuring pass / for no link.
        func offset(_ index: Int?) -> UInt32 {
            guard let itemByteOffsets, let index else { return 0 }
            return UInt32(itemByteOffsets[index])
        }

        // Root-entity navigation offsets (PS3.3 F.3.2.2).
        dataSet[.offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity] =
            DataElement.uint32(tag: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity,
                               value: offset(layout.rootIndices.first))
        dataSet[.offsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity] =
            DataElement.uint32(tag: .offsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity,
                               value: offset(layout.rootIndices.last))

        // PS3.3 2026a Table F.3-3: "The Value FFFFH shall never be present" (D231); 0000H is
        // written whatever `isConsistent` says.
        dataSet[.fileSetConsistencyFlag] = DataElement.uint16(tag: .fileSetConsistencyFlag, value: 0x0000)

        var items: [SequenceItem] = []
        for index in layout.records.indices {
            let recordDataSet = try buildDirectoryRecordDataSet(
                from: layout.records[index],
                nextOffset: offset(layout.nextSibling[index]),
                lowerOffset: offset(layout.firstChild[index]))
            items.append(SequenceItem(elements: Array(recordDataSet)))
        }
        dataSet.setSequence(items, for: .directoryRecordSequence)

        let dicomFile = DICOMFile(fileMetaInformation: fileMeta, dataSet: dataSet)
        return try dicomFile.write()
    }

    /// Byte offset (from the start of the file) of each top-level Directory Record
    /// Sequence item — the position of each record's (FFFE,E000) item tag, which is what
    /// the navigation offsets reference (PS3.3 F.3.2.2). Walks the sequence by its defined
    /// item lengths, so nested sequences inside a record are skipped whole.
    private static func itemByteOffsets(in data: Data, expectedCount: Int) throws -> [Int] {
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int {
            Int(UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8)
                | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24))
        }
        // Locate the (0004,1220) Directory Record Sequence, explicit VR 'SQ'.
        var header = -1
        var scan = 0
        while scan + 12 <= bytes.count {
            if bytes[scan] == 0x04, bytes[scan + 1] == 0x00,
               bytes[scan + 2] == 0x20, bytes[scan + 3] == 0x12,
               bytes[scan + 4] == 0x53, bytes[scan + 5] == 0x51 {   // 'S','Q'
                header = scan
                break
            }
            scan += 1
        }
        guard header >= 0 else {
            throw DICOMError.parsingFailed("Directory Record Sequence not found while computing DICOMDIR offsets")
        }
        let valueStart = header + 12                     // explicit-VR SQ: 12-byte header
        let sequenceEnd = valueStart + u32(header + 8)
        var offsets: [Int] = []
        var cursor = valueStart
        while cursor + 8 <= min(sequenceEnd, bytes.count),
              bytes[cursor] == 0xFE, bytes[cursor + 1] == 0xFF,
              bytes[cursor + 2] == 0x00, bytes[cursor + 3] == 0xE0 {
            offsets.append(cursor)                       // offset = position of the item tag
            cursor += 8 + u32(cursor + 4)                // defined-length item: skip whole
        }
        guard offsets.count == expectedCount else {
            throw DICOMError.parsingFailed(
                "DICOMDIR item count mismatch computing offsets (\(offsets.count) vs \(expectedCount))")
        }
        return offsets
    }
    
    /// Write a DICOMDIR to a file URL
    ///
    /// - Parameters:
    ///   - directory: DICOMDIR structure to write
    ///   - url: File URL to write to
    /// - Throws: DICOMError or IO error if writing fails
    public static func write(_ directory: DICOMDirectory, to url: URL) throws {
        let data = try write(directory)
        try data.write(to: url)
    }
    
    /// Create file meta information for DICOMDIR
    ///
    /// - Returns: DataSet with file meta information
    private static func createFileMetaInformation() -> DataSet {
        var fmi = DataSet()
        
        // File Meta Information Group Length - will be set by DICOMFile.write()
        // File Meta Information Version
        var versionData = Data(count: 2)
        versionData[0] = 0x00
        versionData[1] = 0x01
        fmi[.fileMetaInformationVersion] = DataElement.data(tag: .fileMetaInformationVersion, vr: .OB, data: versionData)
        
        // Media Storage SOP Class UID (DICOMDIR)
        fmi[.mediaStorageSOPClassUID] = DataElement.string(tag: .mediaStorageSOPClassUID, vr: .UI, value: mediaStorageDirectorySOPClassUID)
        
        // Media Storage SOP Instance UID (generate unique UID)
        let sopInstanceUID = UIDGenerator.generateUID()
        fmi[.mediaStorageSOPInstanceUID] = DataElement.string(tag: .mediaStorageSOPInstanceUID, vr: .UI, value: sopInstanceUID.value)
        
        // Transfer Syntax UID (Explicit VR Little Endian)
        fmi[.transferSyntaxUID] = DataElement.string(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRLittleEndian.uid)
        
        // Implementation Class UID and Version Name: the same values every file this
        // library writes carries (the literal here used to be the Deflated Explicit VR
        // Little Endian Transfer Syntax UID, which is not an implementation UID).
        fmi[.implementationClassUID] = DataElement.string(tag: .implementationClassUID, vr: .UI, value: DICOMFile.implementationClassUID)
        fmi[.implementationVersionName] = DataElement.string(tag: .implementationVersionName, vr: .SH, value: DICOMFile.implementationVersionName)
        
        return fmi
    }
    
    /// Build a DataSet for a single directory record, with its computed navigation
    /// offsets (next sibling / first child), each a 4-byte UL (PS3.3 F.3.2.2).
    private static func buildDirectoryRecordDataSet(
        from record: DirectoryRecord,
        nextOffset: UInt32,
        lowerOffset: UInt32
    ) throws -> DataSet {
        var dataSet = DataSet()
        
        // Add directory record type
        dataSet[.directoryRecordType] = DataElement.string(tag: .directoryRecordType, vr: .CS, value: record.recordType.rawValue)
        
        // Add in-use flag
        let inUseFlag: UInt16 = record.isActive ? 0xFFFF : 0x0000
        dataSet[.recordInUseFlag] = DataElement.uint16(tag: .recordInUseFlag, value: inUseFlag)
        
        // Add referenced file information (for IMAGE and similar records)
        if let referencedFileID = record.referencedFileID {
            dataSet[.referencedFileID] = DataElement.strings(tag: .referencedFileID, vr: .CS, values: referencedFileID)
        }
        
        if let sopClassUID = record.referencedSOPClassUID {
            dataSet[.referencedSOPClassUIDInFile] = DataElement.string(tag: .referencedSOPClassUIDInFile, vr: .UI, value: sopClassUID)
        }
        
        if let sopInstanceUID = record.referencedSOPInstanceUID {
            dataSet[.referencedSOPInstanceUIDInFile] = DataElement.string(tag: .referencedSOPInstanceUIDInFile, vr: .UI, value: sopInstanceUID)
        }
        
        if let transferSyntaxUID = record.referencedTransferSyntaxUID {
            dataSet[.referencedTransferSyntaxUIDInFile] = DataElement.string(tag: .referencedTransferSyntaxUIDInFile, vr: .UI, value: transferSyntaxUID)
        }
        
        // Navigation offsets (0 = no next sibling / no children). Computed by the
        // two-pass encode; a fixed 4-byte UL so re-encoding does not shift byte layout.
        dataSet[.offsetOfTheNextDirectoryRecord] = DataElement.uint32(tag: .offsetOfTheNextDirectoryRecord, value: nextOffset)
        dataSet[.offsetOfReferencedLowerLevelDirectoryEntity] = DataElement.uint32(tag: .offsetOfReferencedLowerLevelDirectoryEntity, value: lowerOffset)
        
        // Add all other attributes
        for (tag, element) in record.attributes {
            dataSet[tag] = element
        }
        
        return dataSet
    }
}

// MARK: - DICOMDIR Builder

extension DICOMDirectory {
    /// Builder for constructing DICOMDIR from DICOM files
    ///
    /// Every added instance gets its own record under its PATIENT / STUDY / SERIES records
    /// (PS3.3 F.4, Table F.4-1), of the Directory Record Type PS3.3 F.5 gives its SOP Class
    /// (IMAGE, SR DOCUMENT, PRESENTATION, RT DOSE, ENCAP DOC, …; HANGING PROTOCOL, PALETTE,
    /// IMPLANT*, INVENTORY at the root), with the Type 1 / 2 keys of its PS3.3 F.5 table
    /// (``DICOMDIRRecordKeys``); records keep the order in which they were first added.
    /// A STUDY without Study ID gets its ordinal in the File-set, a SERIES without Series
    /// Number its ordinal in the study, a record without Instance Number its ordinal in the
    /// series (PS3.11 D.3.3.1: the FSC supplies them); a Study Date / Time the instance lacks
    /// is taken from its Series, Acquisition or Content Date / Time, else 19000101 / 000000
    /// (``suppliesMissingStudyDateTime``); any other missing Type 1 key refuses the file. The
    /// profile's PS3.11 "Additional DICOMDIR Keys" (Tables A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2)
    /// are added to the PATIENT, SERIES and instance records, with an Icon Image Sequence made from
    /// the pixels where STD-XABC-CD / STD-XA1K require one; a required key that cannot be supplied
    /// refuses the file (``DICOMDIRProfileRules/Refusal/missingProfileKey(profile:recordType:key:tag:table:reason:)``). `addFile` refuses (throws ``DICOMDIRProfileRules/Refusal``) a File ID that
    /// breaks PS3.10 8.2 / 8.5, a SOP Class or Transfer Syntax the profile's PS3.11 table
    /// does not list, and a SOP Instance that is already indexed.
    public struct Builder {
        private var fileSetID: String
        private var profile: DICOMDIRProfile
        private var specificCharacterSet: String?
        /// PATIENT records in first-added order (DirectoryRecord is a value type: children
        /// are always mutated in place through these indices, never through a copy).
        private var patients: [DirectoryRecord] = []
        private var patientIndex: [String: Int] = [:]
        private var indexedInstances: [String: [String]] = [:]
        /// Root-level records other than PATIENT (PS3.3 Table F.4-1), in first-added order.
        private var otherRootRecords: [DirectoryRecord] = []
        /// STUDY records created so far; the next one without a Study ID gets this count + 1.
        private var studyCount = 0

        /// Whether a STUDY record whose instance carries no Study, Series, Acquisition or Content
        /// Date / Time gets Study Date 19000101 and Study Time 000000 (true, the default), or the
        /// instance is refused (``DICOMDIRProfileRules/Refusal/missingRecordKey(recordType:key:tag:table:)``).
        /// Study Date and Time are Type 1 keys of the STUDY record (PS3.3 2026a Table F.5-2) but
        /// Type 2 in the General Study Module, and empty after de-identification (PS3.15 Table
        /// E.1-1 action Z), so the File-set Creator has to supply them (PS3.11 2026a D.3.3.1).
        public var suppliesMissingStudyDateTime: Bool = true
        
        /// Initialize a new DICOMDIR builder
        ///
        /// - Parameters:
        ///   - fileSetID: File-set identifier
        ///   - profile: Application profile (default: .standardGeneralCD)
        public init(fileSetID: String = "", profile: DICOMDIRProfile = .standardGeneralCD) {
            self.fileSetID = fileSetID
            self.profile = profile
        }
        
        /// Add a DICOM file to the directory
        ///
        /// - Parameters:
        ///   - file: DICOM file to add
        ///   - relativePath: Referenced File ID components (PS3.10 8.2: 1-8 components of
        ///     1-8 characters A-Z, 0-9, _), relative to the DICOMDIR's directory
        /// - Throws: DICOMError if a record key is missing; DICOMDIRProfileRules.Refusal if
        ///   the File ID, the SOP Class / Transfer Syntax (PS3.11 profile table) or a
        ///   duplicate SOP Instance makes the file unfit for this File-set
        public mutating func addFile(_ file: DICOMFile, relativePath: [String]) throws {
            let dataSet = file.dataSet

            // Extract instance information
            guard let sopClassUID = file.fileMetaInformation.string(for: .mediaStorageSOPClassUID) else {
                throw DICOMError.parsingFailed( "Missing SOP Class UID")
            }
            guard let sopInstanceUID = file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID) else {
                throw DICOMError.parsingFailed( "Missing SOP Instance UID")
            }
            let transferSyntaxUID = file.fileMetaInformation.string(for: .transferSyntaxUID) ?? TransferSyntax.explicitVRLittleEndian.uid

            // PS3.10 8.2 / 8.5: the Referenced File ID (0004,1500) must be a conformant File ID.
            let problems = DICOMDIRProfileRules.fileIDProblems(relativePath)
            guard problems.isEmpty else {
                throw DICOMDIRProfileRules.Refusal.nonConformantFileID(fileID: relativePath, problems: problems)
            }
            // PS3.11: the profile is a conformance claim; refuse what its table does not list
            // (a "Multi-frame Composite IODs" row only for an instance with Number of Frames).
            if let refusal = DICOMDIRProfileRules.refusal(
                sopClassUID: sopClassUID, transferSyntaxUID: transferSyntaxUID, profile: profile,
                isMultiFrame: dataSet[.numberOfFrames] != nil) {
                throw refusal
            }
            // PS3.11: the profile's image attribute values (Tables A.3-3 ... L.4-2, C.3-2).
            let attributeProblems = DICOMDIRProfileRules.imageAttributeProblems(
                in: dataSet, sopClassUID: sopClassUID, transferSyntaxUID: transferSyntaxUID, profile: profile)
            guard attributeProblems.isEmpty else {
                throw DICOMDIRProfileRules.Refusal.imageAttributeValues(
                    sopClassUID: sopClassUID, profile: profile.rawValue, problems: attributeProblems)
            }
            if let existing = indexedInstances[sopInstanceUID] {
                throw DICOMDIRProfileRules.Refusal.duplicateSOPInstance(sopInstanceUID: sopInstanceUID, fileID: existing)
            }

            // The record type that references this SOP Class (PS3.3 F.5, Table F.4-1).
            guard let recordType = Self.recordType(sopClassUID: sopClassUID, dataSet: dataSet) else {
                throw DICOMDIRProfileRules.Refusal.noDirectoryRecordType(sopClassUID: sopClassUID)
            }
            func keys(_ type: DirectoryRecordType, _ assigned: DICOMDIRRecordKeys.Assigned) throws -> [Tag: DataElement] {
                do {
                    return try DICOMDIRRecordKeys.keyElements(for: type, from: dataSet, assigned: assigned)
                } catch let missing as DICOMDIRRecordKeys.MissingKey {
                    throw DICOMDIRProfileRules.Refusal.missingRecordKey(
                        recordType: missing.recordType.rawValue, key: missing.key.name,
                        tag: missing.key.tag.description, table: missing.table)
                }
            }
            func instanceRecord(_ attributes: [Tag: DataElement]) -> DirectoryRecord {
                DirectoryRecord(
                    recordType: recordType,
                    referencedFileID: relativePath,
                    referencedSOPClassUID: sopClassUID,
                    referencedSOPInstanceUID: sopInstanceUID,
                    referencedTransferSyntaxUID: transferSyntaxUID,
                    attributes: attributes)
            }

            // Root-level records (HANGING PROTOCOL, PALETTE, IMPLANT*, INVENTORY): no PATIENT.
            if DirectoryRecordType.rootLevelTypes.contains(recordType) {
                otherRootRecords.append(instanceRecord(try keys(recordType, .init())))
                indexedInstances[sopInstanceUID] = relativePath
                return
            }

            guard let patientID = dataSet.string(for: .patientID) else {
                throw DICOMError.parsingFailed( "Missing Patient ID")
            }
            guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
                throw DICOMError.parsingFailed( "Missing Study Instance UID")
            }
            guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
                throw DICOMError.parsingFailed( "Missing Series Instance UID")
            }

            // Every record's keys are computed before anything is added, so a refused instance
            // leaves the directory unchanged.
            let p = patientIndex[patientID]
            let s = p.flatMap { p in patients[p].children.firstIndex(where: {
                $0.recordType == .study && $0.attribute(for: .studyInstanceUID)?.stringValue == studyInstanceUID
            }) }
            let r = s.flatMap { s in patients[p!].children[s].children.firstIndex(where: {
                $0.recordType == .series && $0.attribute(for: .seriesInstanceUID)?.stringValue == seriesInstanceUID
            }) }

            // PS3.11 2026a "Additional DICOMDIR Keys" of the profile (Tables A.3-2 ... I.3-2) and its
            // Icon Images section, for this instance's PATIENT, SERIES and own record.
            func profileKeys(_ type: DirectoryRecordType) throws -> [Tag: DataElement] {
                try DICOMDIRProfileRules.additionalKeyElements(for: type, profile: profile, file: file, sopClassUID: sopClassUID)
            }
            let patientExtra = try profileKeys(.patient)
            let seriesExtra = try profileKeys(.series)
            let leafExtra = try profileKeys(recordType)

            var newPatient: DirectoryRecord?
            if p == nil {
                newPatient = DirectoryRecord(recordType: .patient,
                                             attributes: Self.merged(try keys(.patient, .init()), patientExtra))
            }
            var newStudy: DirectoryRecord?
            if s == nil {
                studyCount += 1
                var assigned = DICOMDIRRecordKeys.Assigned()
                assigned.studyID = String(studyCount)                 // SH
                if suppliesMissingStudyDateTime {
                    assigned.studyDate = "19000101"
                    assigned.studyTime = "000000"
                }
                var attributes = try keys(.study, assigned)
                attributes[.studyInstanceUID] = DataElement.string(tag: .studyInstanceUID, vr: .UI, value: studyInstanceUID)
                newStudy = DirectoryRecord(recordType: .study, attributes: attributes)
            }
            var newSeries: DirectoryRecord?
            if r == nil {
                let seriesInStudy = s.map { patients[p!].children[$0].children.count } ?? 0
                var assigned = DICOMDIRRecordKeys.Assigned()
                assigned.seriesNumber = String(seriesInStudy + 1)     // IS
                assigned.modality = "OT"   // Type 1 in every IOD; "OT" for an instance without one (as before)
                var attributes = Self.merged(try keys(.series, assigned), seriesExtra)
                if let description = dataSet[.seriesDescription] { attributes[.seriesDescription] = description }
                newSeries = DirectoryRecord(recordType: .series, attributes: attributes)
            }
            let instancesInSeries = r.map { patients[p!].children[s!].children[$0].children.count } ?? 0
            var assigned = DICOMDIRRecordKeys.Assigned()
            assigned.instanceNumber = String(instancesInSeries + 1)   // IS
            let leaf = instanceRecord(Self.merged(try keys(recordType, assigned), leafExtra))

            // PATIENT (root entity) — found or appended.
            let pi: Int
            if let p {
                pi = p
                // "Required if present in any objects referenced by subordinate records" (H.3-2, I.3-2)
                Self.fill(&patients[pi], with: patientExtra)
            } else {
                pi = patients.count
                patients.append(newPatient!)
                patientIndex[patientID] = pi
            }
            // STUDY under that PATIENT.
            let si: Int
            if let s { si = s } else {
                si = patients[pi].children.count
                patients[pi].addChild(newStudy!)
            }
            // SERIES under that STUDY.
            let ri: Int
            if let r {
                ri = r
                Self.fill(&patients[pi].children[si].children[ri], with: seriesExtra)
            } else {
                ri = patients[pi].children[si].children.count
                patients[pi].children[si].addChild(newSeries!)
            }
            // One record per instance, of the type its SOP Class calls for (PS3.3 F.4, F.5).
            patients[pi].children[si].children[ri].addChild(leaf)
            indexedInstances[sopInstanceUID] = relativePath
        }

        /// `base` with the profile's additional keys; a non-empty value is never replaced by an empty one.
        static func merged(_ base: [Tag: DataElement], _ extra: [Tag: DataElement]) -> [Tag: DataElement] {
            base.merging(extra) { old, new in isEmpty(old) ? new : old }
        }

        /// Sets the additional keys an existing PATIENT / SERIES record lacks or has empty.
        static func fill(_ record: inout DirectoryRecord, with extra: [Tag: DataElement]) {
            for (tag, element) in extra where !isEmpty(element) {
                if let existing = record.attribute(for: tag), !isEmpty(existing) { continue }
                record.setAttribute(element, for: tag)
            }
        }

        private static func isEmpty(_ element: DataElement) -> Bool {
            element.vr == .SQ ? (element.sequenceItems ?? []).isEmpty : element.length == 0
        }

        /// The Directory Record Type for an instance: PS3.3 2026a F.5 per SOP Class; for a SOP
        /// Class PS3.4 does not list (private, retired) IMAGE when the instance has Pixel Data.
        static func recordType(sopClassUID: String, dataSet: DataSet) -> DirectoryRecordType? {
            if let type = DICOMDIRRecordKeys.recordType(forSOPClassUID: sopClassUID) { return type }
            if DICOMDIRRecordKeys.hasNoDirectoryRecordType(sopClassUID: sopClassUID) { return nil }
            return dataSet[.pixelData] != nil ? .image : nil
        }
        
        /// Build the final DICOMDIR
        ///
        /// - Returns: Complete DICOMDIR structure
        public func build() -> DICOMDirectory {
            return DICOMDirectory(
                fileSetID: fileSetID,
                profile: profile,
                specificCharacterSet: specificCharacterSet,
                rootRecords: patients + otherRootRecords
            )
        }
    }
}
