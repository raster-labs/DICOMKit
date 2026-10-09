import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

@Suite("UIDGenerator Tests")
struct UIDGeneratorTests {
    
    @Test("Generate unique UIDs")
    func testGenerateUniqueUIDs() {
        let generator = UIDGenerator()
        
        let uid1 = generator.generate()
        let uid2 = generator.generate()
        
        // UIDs should be different
        #expect(uid1.value != uid2.value)
        
        // UIDs should be valid
        #expect(uid1.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(uid2.value.count <= DICOMUniqueIdentifier.maximumLength)
    }
    
    @Test("Generate UID with custom root")
    func testGenerateUIDWithCustomRoot() {
        let customRoot = "1.2.3.4.5"
        let generator = UIDGenerator(root: customRoot)
        
        let uid = generator.generate()
        
        #expect(uid.value.hasPrefix(customRoot))
    }
    
    @Test("Generate typed UIDs")
    func testGenerateTypedUIDs() {
        let generator = UIDGenerator()
        
        let studyUID = generator.generateStudyInstanceUID()
        let seriesUID = generator.generateSeriesInstanceUID()
        let sopUID = generator.generateSOPInstanceUID()
        
        // All should be unique
        #expect(studyUID.value != seriesUID.value)
        #expect(seriesUID.value != sopUID.value)
        #expect(studyUID.value != sopUID.value)
        
        // All should be valid UIDs
        #expect(studyUID.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(seriesUID.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(sopUID.value.count <= DICOMUniqueIdentifier.maximumLength)
    }
    
    @Test("Static UID generation methods")
    func testStaticUIDGeneration() {
        let uid1 = UIDGenerator.generateUID()
        let uid2 = UIDGenerator.generateStudyInstanceUID()
        let uid3 = UIDGenerator.generateSeriesInstanceUID()
        let uid4 = UIDGenerator.generateSOPInstanceUID()
        
        // All should be valid and unique
        #expect(uid1.value != uid2.value)
        #expect(uid1.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(uid2.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(uid3.value.count <= DICOMUniqueIdentifier.maximumLength)
        #expect(uid4.value.count <= DICOMUniqueIdentifier.maximumLength)
    }
    
    @Test("Shared generator instance")
    func testSharedGenerator() {
        let uid1 = UIDGenerator.shared.generate()
        let uid2 = UIDGenerator.shared.generate()
        
        // Should generate different UIDs
        #expect(uid1.value != uid2.value)
    }
}

@Suite("DICOMWriter Tests")
struct DICOMWriterTests {
    
    // MARK: - String Serialization
    
    @Test("Serialize string with even length")
    func testSerializeStringEvenLength() {
        let writer = DICOMWriter()
        let data = writer.serializeString("Test", vr: .LO)
        
        #expect(data.count == 4)
        #expect(String(data: data, encoding: .utf8) == "Test")
    }
    
    @Test("Serialize string with odd length - space padding")
    func testSerializeStringOddLengthSpacePadding() {
        let writer = DICOMWriter()
        let data = writer.serializeString("Tes", vr: .LO)
        
        #expect(data.count == 4)
        #expect(data[3] == 0x20) // Space padding
    }
    
    @Test("Serialize UID string with null padding")
    func testSerializeUIDStringNullPadding() {
        let writer = DICOMWriter()
        let data = writer.serializeString("1.2.3", vr: .UI)
        
        #expect(data.count == 6)
        #expect(data[5] == 0x00) // Null padding for UI
    }
    
    @Test("Serialize multiple strings")
    func testSerializeMultipleStrings() {
        let writer = DICOMWriter()
        let data = writer.serializeStrings(["A", "B", "C"], vr: .CS)
        
        #expect(String(data: data, encoding: .utf8) == "A\\B\\C ")
        #expect(data.count % 2 == 0) // Even length
    }
    
    // MARK: - Numeric Serialization
    
    @Test("Serialize UInt16 Little Endian")
    func testSerializeUInt16LittleEndian() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeUInt16(0x1234)
        
        #expect(data.count == 2)
        #expect(data[0] == 0x34)
        #expect(data[1] == 0x12)
    }
    
    @Test("Serialize UInt16 Big Endian")
    func testSerializeUInt16BigEndian() {
        let writer = DICOMWriter(byteOrder: .bigEndian)
        let data = writer.serializeUInt16(0x1234)
        
        #expect(data.count == 2)
        #expect(data[0] == 0x12)
        #expect(data[1] == 0x34)
    }
    
    @Test("Serialize UInt32 Little Endian")
    func testSerializeUInt32LittleEndian() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeUInt32(0x12345678)
        
        #expect(data.count == 4)
        #expect(data[0] == 0x78)
        #expect(data[1] == 0x56)
        #expect(data[2] == 0x34)
        #expect(data[3] == 0x12)
    }
    
    @Test("Serialize UInt32 Big Endian")
    func testSerializeUInt32BigEndian() {
        let writer = DICOMWriter(byteOrder: .bigEndian)
        let data = writer.serializeUInt32(0x12345678)
        
        #expect(data.count == 4)
        #expect(data[0] == 0x12)
        #expect(data[1] == 0x34)
        #expect(data[2] == 0x56)
        #expect(data[3] == 0x78)
    }
    
    @Test("Serialize Int16")
    func testSerializeInt16() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeInt16(-1)
        
        #expect(data.count == 2)
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0xFF)
    }
    
    @Test("Serialize Int32")
    func testSerializeInt32() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeInt32(-1)
        
        #expect(data.count == 4)
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0xFF)
        #expect(data[2] == 0xFF)
        #expect(data[3] == 0xFF)
    }
    
    @Test("Serialize Float32")
    func testSerializeFloat32() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeFloat32(1.0)
        
        #expect(data.count == 4)
        // 1.0 in IEEE 754 = 0x3F800000
        #expect(data[0] == 0x00)
        #expect(data[1] == 0x00)
        #expect(data[2] == 0x80)
        #expect(data[3] == 0x3F)
    }
    
    @Test("Serialize Float64")
    func testSerializeFloat64() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeFloat64(1.0)
        
        #expect(data.count == 8)
        // 1.0 in IEEE 754 double = 0x3FF0000000000000
        #expect(data[7] == 0x3F)
        #expect(data[6] == 0xF0)
    }
    
    @Test("Serialize multiple UInt16 values")
    func testSerializeMultipleUInt16() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let data = writer.serializeUInt16s([0x0100, 0x0200, 0x0300])
        
        #expect(data.count == 6)
    }
    
    // MARK: - Tag Serialization
    
    @Test("Serialize Tag")
    func testSerializeTag() {
        let writer = DICOMWriter(byteOrder: .littleEndian)
        let tag = Tag(group: 0x0010, element: 0x0020)
        let data = writer.serializeTag(tag)
        
        #expect(data.count == 4)
        #expect(data[0] == 0x10)
        #expect(data[1] == 0x00)
        #expect(data[2] == 0x20)
        #expect(data[3] == 0x00)
    }
    
    // MARK: - Element Header Serialization
    
    @Test("Serialize Explicit VR element header with 16-bit length")
    func testSerializeExplicitVRHeader16Bit() {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let header = writer.serializeElementHeader(tag: .patientName, vr: .PN, length: 8)
        
        // Tag (4) + VR (2) + Length (2) = 8 bytes
        #expect(header.count == 8)
        
        // Check tag
        #expect(header[0] == 0x10 && header[1] == 0x00) // Group 0010
        #expect(header[2] == 0x10 && header[3] == 0x00) // Element 0010
        
        // Check VR
        #expect(header[4] == 0x50) // 'P'
        #expect(header[5] == 0x4E) // 'N'
        
        // Check length
        #expect(header[6] == 0x08 && header[7] == 0x00)
    }
    
    @Test("Serialize Explicit VR element header with 32-bit length")
    func testSerializeExplicitVRHeader32Bit() {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let header = writer.serializeElementHeader(tag: .pixelData, vr: .OW, length: 1000)
        
        // Tag (4) + VR (2) + Reserved (2) + Length (4) = 12 bytes
        #expect(header.count == 12)
        
        // Check reserved bytes
        #expect(header[6] == 0x00 && header[7] == 0x00)
    }
    
    @Test("Serialize Implicit VR element header")
    func testSerializeImplicitVRHeader() {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: false)
        let header = writer.serializeElementHeader(tag: .patientName, vr: .PN, length: 8)
        
        // Tag (4) + Length (4) = 8 bytes (no VR in Implicit VR)
        #expect(header.count == 8)
    }
}

@Suite("DataElement Creation Tests")
struct DataElementCreationTests {
    
    @Test("Create string element")
    func testCreateStringElement() {
        let element = DataElement.string(tag: .patientName, vr: .PN, value: "Doe^John")
        
        #expect(element.tag == .patientName)
        #expect(element.vr == .PN)
        #expect(element.stringValue == "Doe^John")
    }
    
    @Test("Create UInt16 element")
    func testCreateUInt16Element() {
        let element = DataElement.uint16(tag: .rows, value: 512)
        
        #expect(element.tag == .rows)
        #expect(element.vr == .US)
        #expect(element.uint16Value == 512)
    }
    
    @Test("Create UInt32 element")
    func testCreateUInt32Element() {
        let element = DataElement.uint32(tag: .fileMetaInformationGroupLength, value: 256)
        
        #expect(element.tag == .fileMetaInformationGroupLength)
        #expect(element.vr == .UL)
        #expect(element.uint32Value == 256)
    }
    
    @Test("Create Float32 element")
    func testCreateFloat32Element() {
        let element = DataElement.float32(tag: Tag(group: 0x0018, element: 0x0050), value: 3.14)
        
        #expect(element.vr == .FL)
        #expect(element.float32Value != nil)
        #expect(abs(element.float32Value! - 3.14) < 0.001)
    }
    
    @Test("Create Float64 element")
    func testCreateFloat64Element() {
        let element = DataElement.float64(tag: Tag(group: 0x0018, element: 0x0050), value: 3.14159265)
        
        #expect(element.vr == .FD)
        #expect(element.float64Value != nil)
        #expect(abs(element.float64Value! - 3.14159265) < 0.0000001)
    }
    
    @Test("Create binary data element with even padding")
    func testCreateBinaryDataElement() {
        let binaryData = Data([0x01, 0x02, 0x03]) // Odd length
        let element = DataElement.data(tag: .pixelData, vr: .OB, data: binaryData)
        
        #expect(element.vr == .OB)
        #expect(element.valueData.count == 4) // Padded to even
    }
}

@Suite("DataSet Writing Tests")
struct DataSetWritingTests {
    
    @Test("DataSet set and get string")
    func testDataSetSetGetString() {
        var dataSet = DataSet()
        dataSet.setString("Test Patient", for: .patientName, vr: .PN)
        
        #expect(dataSet.string(for: .patientName) == "Test Patient")
    }
    
    @Test("DataSet set and get UInt16")
    func testDataSetSetGetUInt16() {
        var dataSet = DataSet()
        dataSet.setUInt16(512, for: .rows)
        
        #expect(dataSet.uint16(for: .rows) == 512)
    }
    
    @Test("DataSet write produces valid data")
    func testDataSetWrite() {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        
        let writer = DICOMWriter()
        let data = dataSet.write(using: writer)
        
        #expect(data.count > 0)
    }
    
    @Test("DataSet write maintains tag order")
    func testDataSetWriteTagOrder() {
        var dataSet = DataSet()
        // Add elements out of order
        dataSet.setString("ID123", for: .patientID, vr: .LO)
        dataSet.setString("20250131", for: .studyDate, vr: .DA)
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        
        let writer = DICOMWriter()
        let data = dataSet.write(using: writer)
        
        // Study Date (0008,0020) should come before Patient Name (0010,0010)
        // Patient Name (0010,0010) should come before Patient ID (0010,0020)
        #expect(data.count > 0)
        
        // Parse back and verify
        let sortedTags = dataSet.tags
        #expect(sortedTags[0] == .studyDate)
        #expect(sortedTags[1] == .patientName)
        #expect(sortedTags[2] == .patientID)
    }
    
    @Test("DataSet remove element")
    func testDataSetRemoveElement() {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        
        #expect(dataSet.string(for: .patientName) != nil)
        
        dataSet.remove(tag: .patientName)
        
        #expect(dataSet.string(for: .patientName) == nil)
    }
}

@Suite("DICOMFile Writing Tests")
struct DICOMFileWritingTests {
    
    @Test("Create DICOM file with required elements")
    func testCreateDICOMFile() {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("ID123", for: .patientID, vr: .LO)
        
        let file = DICOMFile.create(dataSet: dataSet)
        
        // Verify File Meta Information was generated
        #expect(file.fileMetaInformation.count > 0)
        #expect(file.transferSyntaxUID == "1.2.840.10008.1.2.1")
        
        // Verify main data set
        #expect(file.dataSet.string(for: .patientName) == "Doe^John")
    }
    
    /// PS3.10 2026a Table 7.1-1: Implementation Class UID (0002,0012) is Type 1; PS3.5 §9.2.2
    /// requires it under a root the organisation owns. It is arc .3 of the library root, not
    /// DCMTK 3.6.5's UID under the OFFIS root as before 2026-09-29.
    @Test("Implementation Class UID is under the library's own root (PS3.5 9.2.2, PS3.10 Table 7.1-1)")
    func testImplementationClassUIDRoot() {
        #expect(DICOMFile.implementationClassUID == "1.2.826.0.1.3680043.10.511.3.0.5.0")
        #expect(!DICOMFile.implementationClassUID.hasPrefix("1.2.276.0.7230010"))
        #expect(DICOMUniqueIdentifier.parse(DICOMFile.implementationClassUID) != nil)
        let file = DICOMFile.create(dataSet: DataSet())
        #expect(file.fileMetaInformation.string(for: .implementationClassUID) == DICOMFile.implementationClassUID)
        #expect(file.fileMetaInformation.string(for: .implementationVersionName) == DICOMFile.implementationVersionName)
    }

    @Test("Create DICOM file with custom SOP Class UID")
    func testCreateDICOMFileWithCustomSOPClass() {
        let dataSet = DataSet()
        let ctImageStorageUID = "1.2.840.10008.5.1.4.1.1.2"
        
        let file = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: ctImageStorageUID
        )
        
        let mediaSOPClass = file.fileMetaInformation.string(for: .mediaStorageSOPClassUID)
        #expect(mediaSOPClass == ctImageStorageUID)
    }
    
    @Test("Write DICOM file produces valid data")
    func testWriteDICOMFile() throws {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let data = try file.write()
        
        // Check minimum size (preamble + DICM prefix)
        #expect(data.count >= 132)
        
        // Check preamble (128 zeros)
        for i in 0..<128 {
            #expect(data[i] == 0x00)
        }
        
        // Check DICM prefix
        #expect(data[128] == 0x44) // 'D'
        #expect(data[129] == 0x49) // 'I'
        #expect(data[130] == 0x43) // 'C'
        #expect(data[131] == 0x4D) // 'M'
    }
    
    @Test("Round-trip: write then read DICOM file")
    func testRoundTripDICOMFile() throws {
        // Create original file
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("ID123456", for: .patientID, vr: .LO)
        dataSet.setString("20250131", for: .studyDate, vr: .DA)
        dataSet.setUInt16(512, for: .rows)
        dataSet.setUInt16(512, for: .columns)
        
        let originalFile = DICOMFile.create(dataSet: dataSet)
        
        // Write to data
        let data = try originalFile.write()
        
        // Read back
        let readFile = try DICOMFile.read(from: data)
        
        // Verify contents match
        #expect(readFile.dataSet.string(for: .patientName) == "Doe^John")
        #expect(readFile.dataSet.string(for: .patientID) == "ID123456")
        #expect(readFile.dataSet.string(for: .studyDate) == "20250131")
        #expect(readFile.dataSet.uint16(for: .rows) == 512)
        #expect(readFile.dataSet.uint16(for: .columns) == 512)
    }
    
    @Test("Round-trip preserves Transfer Syntax UID")
    func testRoundTripPreservesTransferSyntax() throws {
        let dataSet = DataSet()
        let file = DICOMFile.create(
            dataSet: dataSet,
            transferSyntaxUID: "1.2.840.10008.1.2.1" // Explicit VR Little Endian
        )
        
        let data = try file.write()
        let readFile = try DICOMFile.read(from: data)
        
        #expect(readFile.transferSyntaxUID == "1.2.840.10008.1.2.1")
    }
    
    @Test("Round-trip with multiple data types")
    func testRoundTripMultipleDataTypes() throws {
        var dataSet = DataSet()
        
        // String values
        dataSet.setString("Smith^Jane^M", for: .patientName, vr: .PN)
        dataSet.setStrings(["ORIGINAL", "PRIMARY"], for: .imageType, vr: .CS)
        
        // Numeric values
        dataSet.setUInt16(256, for: .rows)
        dataSet.setUInt16(256, for: .columns)
        dataSet.setUInt16(16, for: .bitsAllocated)
        dataSet.setUInt16(12, for: .bitsStored)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let data = try file.write()
        let readFile = try DICOMFile.read(from: data)
        
        #expect(readFile.dataSet.string(for: .patientName) == "Smith^Jane^M")
        #expect(readFile.dataSet.uint16(for: .rows) == 256)
        #expect(readFile.dataSet.uint16(for: .bitsAllocated) == 16)
    }
}

@Suite("Sequence Writing Tests")
struct SequenceWritingTests {
    
    @Test("Write and read sequence item")
    func testWriteReadSequenceItem() throws {
        // Create a sequence item
        var item = DataSet()
        item.setString("12345", for: Tag(group: 0x0008, element: 0x0100), vr: .SH) // Code Value
        item.setString("Test Code", for: Tag(group: 0x0008, element: 0x0104), vr: .LO) // Code Meaning
        
        // Create sequence
        var dataSet = DataSet()
        dataSet.setString("Test Patient", for: .patientName, vr: .PN)
        dataSet.setSequence([SequenceItem(elements: item.allElements)], for: .procedureCodeSequence)
        
        // Write and read back
        let file = DICOMFile.create(dataSet: dataSet)
        let data = try file.write()
        let readFile = try DICOMFile.read(from: data)
        
        // Verify sequence was preserved
        #expect(readFile.dataSet.string(for: .patientName) == "Test Patient")
        
        let sequence = readFile.dataSet.sequence(for: .procedureCodeSequence)
        #expect(sequence != nil)
        #expect(sequence?.count == 1)
    }
}
