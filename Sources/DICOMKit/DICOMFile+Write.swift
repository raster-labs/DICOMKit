// NEMA-verified: 2026a, checked 2026-10-01 — PS3.10 2026a Table 7.1-1: the Type 1 File Meta elements are written and (0002,0000) is computed in write(); create() takes (0002,0002)/(0002,0003) from the data set's (0008,0016)/(0008,0018) when present (D175), synchronizingMediaStorageUIDs() re-aligns a carried-over File Meta; the Implementation Class UID is under the library's own root per PS3.5 9.2.2 (P-UID closed)
import Foundation
import DICOMCore

// MARK: - DataSet Writing Extension

extension DataSet {
    
    /// Serializes the data set to binary data
    ///
    /// Serializes all data elements in tag order using the specified writer configuration.
    ///
    /// Reference: PS3.5 Section 7.1 - Data Element Structure
    ///
    /// - Parameter writer: The DICOM writer to use for serialization
    /// - Returns: Serialized data set
    public func write(using writer: DICOMWriter = DICOMWriter()) -> Data {
        var data = Data()
        
        // Elements must be written in tag order per DICOM specification
        let sortedTags = tags.sorted()
        
        for tag in sortedTags {
            if let element = self[tag] {
                data.append(writer.serializeElement(element))
            }
        }
        
        return data
    }
    
    // MARK: - Convenience Setters
    
    /// Sets a string value for the given tag
    ///
    /// - Parameters:
    ///   - value: The string value to set
    ///   - tag: The tag to set
    ///   - vr: The Value Representation to use
    public mutating func setString(_ value: String, for tag: Tag, vr: VR) {
        self[tag] = DataElement.string(tag: tag, vr: vr, value: value)
    }
    
    /// Sets multiple string values for the given tag
    ///
    /// - Parameters:
    ///   - values: The string values to set
    ///   - tag: The tag to set
    ///   - vr: The Value Representation to use
    public mutating func setStrings(_ values: [String], for tag: Tag, vr: VR) {
        self[tag] = DataElement.strings(tag: tag, vr: vr, values: values)
    }
    
    /// Sets a UInt16 value for the given tag
    ///
    /// - Parameters:
    ///   - value: The UInt16 value to set
    ///   - tag: The tag to set
    public mutating func setUInt16(_ value: UInt16, for tag: Tag) {
        self[tag] = DataElement.uint16(tag: tag, value: value)
    }
    
    /// Sets multiple UInt16 values for the given tag
    ///
    /// - Parameters:
    ///   - values: The UInt16 values to set
    ///   - tag: The tag to set
    public mutating func setUInt16s(_ values: [UInt16], for tag: Tag) {
        self[tag] = DataElement.uint16s(tag: tag, values: values)
    }
    
    /// Sets a UInt32 value for the given tag
    ///
    /// - Parameters:
    ///   - value: The UInt32 value to set
    ///   - tag: The tag to set
    public mutating func setUInt32(_ value: UInt32, for tag: Tag) {
        self[tag] = DataElement.uint32(tag: tag, value: value)
    }
    
    /// Sets a sequence value for the given tag
    ///
    /// - Parameters:
    ///   - items: The sequence items to set
    ///   - tag: The tag to set
    public mutating func setSequence(_ items: [SequenceItem], for tag: Tag) {
        // Serialize items to calculate length
        let writer = DICOMWriter()
        var itemsData = Data()
        for item in items {
            itemsData.append(writer.serializeSequenceItem(item))
        }
        
        self[tag] = DataElement(
            tag: tag,
            vr: .SQ,
            length: UInt32(itemsData.count),
            valueData: itemsData,
            sequenceItems: items
        )
    }
    
    /// Sets an integer value for the given tag with the specified VR
    ///
    /// Supports the following VR types:
    /// - `.IS` (Integer String): Stores the integer as a string representation
    /// - `.US` (Unsigned Short): Stores as a binary UInt16 value
    /// - `.UL` (Unsigned Long): Stores as a binary UInt32 value
    /// - `.SS` (Signed Short): Stores as a binary Int16 value
    /// - `.SL` (Signed Long): Stores as a binary Int32 value
    ///
    /// - Parameters:
    ///   - value: The integer value to set
    ///   - tag: The tag to set
    ///   - vr: The Value Representation to use
    public mutating func setInt(_ value: Int, for tag: Tag, vr: VR) {
        switch vr {
        case .IS:
            self[tag] = DataElement.string(tag: tag, vr: .IS, value: String(value))
        case .US:
            self[tag] = DataElement.uint16(tag: tag, value: UInt16(value))
        case .UL:
            self[tag] = DataElement.uint32(tag: tag, value: UInt32(value))
        case .SS:
            self[tag] = DataElement.int16(tag: tag, value: Int16(value))
        case .SL:
            self[tag] = DataElement.int32(tag: tag, value: Int32(value))
        default:
            // Fall back to string representation for other VRs
            self[tag] = DataElement.string(tag: tag, vr: vr, value: String(value))
        }
    }
    
    /// Removes the element at the given tag
    ///
    /// - Parameter tag: The tag to remove
    public mutating func remove(tag: Tag) {
        self[tag] = nil
    }
}

// MARK: - DICOMFile Writing Extension

extension DICOMFile {

    /// Implementation Class UID (0002,0012) written by every file writer of this library.
    ///
    /// PS3.10 Table 7.1-1 makes it Type 1 and PS3.5 §9.2.2 requires a privately defined UID
    /// under a registered root the organisation owns. The value is arc `.3` of the library's
    /// private root `1.2.826.0.1.3680043.10.511` followed by the library version (0.5.0).
    /// Before 2026-09-29 it was `1.2.276.0.7230010.3.0.3.6.5`, which is DCMTK 3.6.5's own
    /// Implementation Class UID under the OFFIS root.
    public static let implementationClassUID = "1.2.826.0.1.3680043.10.511.3.0.5.0"

    /// Implementation Version Name (0002,0013) written by every file writer of this library.
    public static let implementationVersionName = "DICOMKIT_0.5.0"

    /// DICOM File Preamble size (128 bytes of zeros)
    private static let preambleSize = 128
    
    /// DICOM File Prefix
    private static let dicomPrefix: [UInt8] = [0x44, 0x49, 0x43, 0x4D] // "DICM"
    
    /// Writes the DICOM file to binary data
    ///
    /// Generates a complete DICOM Part 10 file with:
    /// - 128-byte preamble (zeros)
    /// - "DICM" prefix
    /// - File Meta Information (always Explicit VR Little Endian)
    /// - Main data set (using the transfer syntax specified in File Meta Information)
    ///
    /// Reference: PS3.10 Section 7 - DICOM File Format
    ///
    /// - Returns: Complete DICOM file data
    /// - Throws: DICOMError if writing fails
    public func write() throws -> Data {
        var data = Data()
        
        // 1. Write 128-byte preamble (all zeros)
        data.append(Data(count: Self.preambleSize))
        
        // 2. Write "DICM" prefix
        data.append(contentsOf: Self.dicomPrefix)
        
        // 3. Write File Meta Information (always Explicit VR Little Endian per PS3.10).
        //    File Meta Information Group Length (0002,0000) is Type 1 (PS3.10 Table 7.1-1):
        //    it is computed here when the caller did not set it.
        let fileMetaWriter = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        var fileMetaInformation = self.fileMetaInformation
        if fileMetaInformation[.fileMetaInformationGroupLength] == nil {
            let others = fileMetaInformation.write(using: fileMetaWriter)
            fileMetaInformation[.fileMetaInformationGroupLength] = DataElement.uint32(
                tag: .fileMetaInformationGroupLength, value: UInt32(others.count))
        }
        data.append(fileMetaInformation.write(using: fileMetaWriter))
        
        // 4. Determine transfer syntax for main data set
        let transferSyntaxUID = self.transferSyntaxUID ?? "1.2.840.10008.1.2.1"
        let transferSyntax = TransferSyntax.from(uid: transferSyntaxUID)
        
        // Ensure transfer syntax is supported for writing
        let isExplicitVR = transferSyntax?.isExplicitVR ?? true
        let byteOrder = transferSyntax?.byteOrder ?? .littleEndian
        
        // 5. Write main data set
        let mainWriter = DICOMWriter(byteOrder: byteOrder, explicitVR: isExplicitVR)
        data.append(dataSet.write(using: mainWriter))
        
        return data
    }
    
    /// Creates a new DICOM file with File Meta Information automatically generated
    ///
    /// Generates required File Meta Information elements including:
    /// - File Meta Information Version (0002,0001)
    /// - Media Storage SOP Class UID (0002,0002)
    /// - Media Storage SOP Instance UID (0002,0003)
    /// - Transfer Syntax UID (0002,0010)
    /// - Implementation Class UID (0002,0012)
    /// - Implementation Version Name (0002,0013)
    ///
    /// PS3.10 2026a Table 7.1-1: Media Storage SOP Class UID (0002,0002) and Media Storage SOP
    /// Instance UID (0002,0003) "uniquely identify the SOP Class / SOP Instance associated with
    /// the Data Set", so they always equal the data set's SOP Class UID (0008,0016) and SOP
    /// Instance UID (0008,0018). Resolution, per UID:
    /// 1. the data set's value, when present and non-empty — it is authoritative, and a
    ///    `sopClassUID` / `sopInstanceUID` argument that differs from it is ignored;
    /// 2. otherwise the argument;
    /// 3. otherwise Secondary Capture Image Storage (class) or a newly generated UID (instance).
    /// When the data set lacks (0008,0016) / (0008,0018), the resolved value is written into the
    /// returned file's data set as well, so File Meta and data set agree. Exception: a Basic
    /// Directory (DICOMDIR, Media Storage Directory Storage 1.2.840.10008.1.3.10) data set has
    /// no SOP Common Module (PS3.3 2026a Table F.3-1), so nothing is added to it.
    ///
    /// Before 2026-10-01 the arguments were used as given: an omitted `sopInstanceUID` produced a
    /// fresh UID different from (0008,0018), and an omitted `sopClassUID` produced Secondary
    /// Capture whatever the data set's class (D175).
    ///
    /// Reference: PS3.10 Section 7.1 - DICOM File Meta Information
    ///
    /// - Parameters:
    ///   - dataSet: The main data set
    ///   - sopClassUID: SOP Class UID used when the data set has no (0008,0016)
    ///     (nil: Secondary Capture Image Storage)
    ///   - sopInstanceUID: SOP Instance UID used when the data set has no (0008,0018)
    ///     (nil: auto-generated)
    ///   - transferSyntaxUID: Transfer Syntax UID (defaults to Explicit VR Little Endian)
    /// - Returns: A new DICOMFile with generated File Meta Information
    public static func create(
        dataSet: DataSet,
        sopClassUID: String? = nil,
        sopInstanceUID: String? = nil,
        transferSyntaxUID: String = "1.2.840.10008.1.2.1" // Explicit VR Little Endian
    ) -> DICOMFile {
        var dataSet = dataSet
        var fileMetaInfo = DataSet()

        let dataSetClassUID = Self.nonEmptyUID(dataSet.string(for: .sopClassUID))
        let dataSetInstanceUID = Self.nonEmptyUID(dataSet.string(for: .sopInstanceUID))
        let classUID = dataSetClassUID
            ?? Self.nonEmptyUID(sopClassUID)
            ?? Self.secondaryCaptureImageStorageUID
        let instanceUID = dataSetInstanceUID
            ?? Self.nonEmptyUID(sopInstanceUID)
            ?? UIDGenerator.generateSOPInstanceUID().value

        // Keep the data set in agreement with the File Meta (PS3.10 Table 7.1-1), except for a
        // Basic Directory data set, which carries no SOP Common Module (PS3.3 Table F.3-1).
        if classUID != Self.mediaStorageDirectoryStorageUID {
            if dataSetClassUID == nil {
                dataSet.setString(classUID, for: .sopClassUID, vr: .UI)
            }
            if dataSetInstanceUID == nil {
                dataSet.setString(instanceUID, for: .sopInstanceUID, vr: .UI)
            }
        }
        
        // File Meta Information Version (0002,0001)
        fileMetaInfo[.fileMetaInformationVersion] = DataElement.data(
            tag: .fileMetaInformationVersion,
            vr: .OB,
            data: Data([0x00, 0x01])
        )
        
        // Media Storage SOP Class UID (0002,0002)
        fileMetaInfo.setString(classUID, for: .mediaStorageSOPClassUID, vr: .UI)
        
        // Media Storage SOP Instance UID (0002,0003)
        fileMetaInfo.setString(instanceUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
        
        // Transfer Syntax UID (0002,0010)
        fileMetaInfo.setString(transferSyntaxUID, for: .transferSyntaxUID, vr: .UI)
        
        // Implementation Class UID (0002,0012) and Version Name (0002,0013)
        fileMetaInfo.setString(Self.implementationClassUID, for: .implementationClassUID, vr: .UI)
        fileMetaInfo.setString(Self.implementationVersionName, for: .implementationVersionName, vr: .SH)
        
        // Calculate and set File Meta Information Group Length (0002,0000)
        Self.setGroupLength(in: &fileMetaInfo)
        
        return DICOMFile(fileMetaInformation: fileMetaInfo, dataSet: dataSet)
    }

    /// A copy of this file whose Media Storage SOP Class UID (0002,0002) and Media Storage SOP
    /// Instance UID (0002,0003) equal the data set's SOP Class UID (0008,0016) and SOP Instance
    /// UID (0008,0018), as PS3.10 2026a Table 7.1-1 requires.
    ///
    /// Use it after replacing the data set of a file whose File Meta came from elsewhere (for
    /// example a de-identified data set with a regenerated SOP Instance UID, PS3.15 2026a
    /// Table E.1-1 action U on both (0002,0003) and (0008,0018)). A UID the data set lacks (or
    /// has empty) leaves the File Meta element unchanged. All other File Meta elements are kept;
    /// File Meta Information Group Length (0002,0000), when present, is recomputed.
    public func synchronizingMediaStorageUIDs() -> DICOMFile {
        var meta = fileMetaInformation
        var changed = false
        if let classUID = Self.nonEmptyUID(dataSet.string(for: .sopClassUID)),
           Self.nonEmptyUID(meta.string(for: .mediaStorageSOPClassUID)) != classUID {
            meta.setString(classUID, for: .mediaStorageSOPClassUID, vr: .UI)
            changed = true
        }
        if let instanceUID = Self.nonEmptyUID(dataSet.string(for: .sopInstanceUID)),
           Self.nonEmptyUID(meta.string(for: .mediaStorageSOPInstanceUID)) != instanceUID {
            meta.setString(instanceUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
            changed = true
        }
        guard changed else { return self }
        if meta[.fileMetaInformationGroupLength] != nil {
            Self.setGroupLength(in: &meta)
        }
        return DICOMFile(fileMetaInformation: meta, dataSet: dataSet)
    }

    /// Secondary Capture Image Storage (PS3.4 2026a Table B.5-1), the class used when neither the
    /// data set nor the caller names one.
    private static let secondaryCaptureImageStorageUID = "1.2.840.10008.5.1.4.1.1.7"

    /// Media Storage Directory Storage (PS3.4 2026a Table I.4-1), the DICOMDIR (Basic Directory IOD) class.
    private static let mediaStorageDirectoryStorageUID = "1.2.840.10008.1.3.10"

    /// A UID string with padding (trailing NUL / space) removed, or nil when it is absent or empty.
    private static func nonEmptyUID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Sets File Meta Information Group Length (0002,0000) to the byte length of the other
    /// File Meta elements (PS3.10 Table 7.1-1).
    private static func setGroupLength(in fileMeta: inout DataSet) {
        fileMeta.remove(tag: .fileMetaInformationGroupLength)
        let metaInfoData = fileMeta.write(using: DICOMWriter(byteOrder: .littleEndian, explicitVR: true))
        fileMeta[.fileMetaInformationGroupLength] = DataElement.uint32(
            tag: .fileMetaInformationGroupLength,
            value: UInt32(metaInfoData.count)
        )
    }
}
