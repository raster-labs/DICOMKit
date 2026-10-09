import Testing
import Foundation
@testable import DICOMCore

@Suite("DataElement Tests")
struct DataElementTests {
    
    @Test("DataElement creation")
    func testDataElementCreation() {
        let tag = Tag.patientName
        let vr = VR.PN
        let data = "DOE^JOHN".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: vr, length: UInt32(data.count), valueData: data)
        
        #expect(element.tag == tag)
        #expect(element.vr == vr)
        #expect(element.length == UInt32(data.count))
        #expect(element.valueData == data)
    }
    
    @Test("Undefined length detection")
    func testUndefinedLength() {
        let element = DataElement(
            tag: Tag.sopInstanceUID,
            vr: .UI,
            length: 0xFFFFFFFF,
            valueData: Data()
        )
        
        #expect(element.hasUndefinedLength == true)
        
        let element2 = DataElement(
            tag: Tag.sopInstanceUID,
            vr: .UI,
            length: 10,
            valueData: Data()
        )
        
        #expect(element2.hasUndefinedLength == false)
    }
    
    @Test("String value extraction")
    func testStringValue() {
        let data = "DOE^JOHN  ".data(using: .utf8)!
        let element = DataElement(tag: Tag.patientName, vr: .PN, length: UInt32(data.count), valueData: data)
        
        // Should trim whitespace
        #expect(element.stringValue == "DOE^JOHN")
    }
    
    @Test("Multiple string values")
    func testMultipleStringValues() {
        let data = "VALUE1\\VALUE2\\VALUE3".data(using: .utf8)!
        let element = DataElement(tag: Tag.sopInstanceUID, vr: .UI, length: UInt32(data.count), valueData: data)
        
        let values = element.stringValues
        #expect(values?.count == 3)
        #expect(values?[0] == "VALUE1")
        #expect(values?[1] == "VALUE2")
        #expect(values?[2] == "VALUE3")
    }
    
    @Test("Empty values of a multi-valued attribute are kept in position (PS3.5 §6.4, D25)")
    func testEmptyValuesPreserved() {
        let data = "MPG\\\\XR3".data(using: .utf8)!
        let element = DataElement(tag: Tag.imageType, vr: .CS, length: UInt32(data.count), valueData: data)
        #expect(element.stringValues == ["MPG", "", "XR3"])
        
        let trailing = "A\\B\\ ".data(using: .utf8)!
        let trailingElement = DataElement(tag: Tag.imageType, vr: .CS, length: UInt32(trailing.count), valueData: trailing)
        #expect(trailingElement.stringValues == ["A", "B", ""])
        
        let empty = DataElement(tag: Tag.imageType, vr: .CS, length: 0, valueData: Data())
        #expect(empty.stringValues == [])
        let padding = DataElement(tag: Tag.imageType, vr: .CS, length: 2, valueData: Data("  ".utf8))
        #expect(padding.stringValues == [])
    }
    
    @Test("UInt16 value extraction")
    func testUInt16Value() {
        var data = Data()
        data.append(0x34)
        data.append(0x12)
        
        let element = DataElement(tag: Tag.seriesNumber, vr: .US, length: 2, valueData: data)
        #expect(element.uint16Value == 0x1234)
    }
    
    @Test("UInt32 value extraction")
    func testUInt32Value() {
        var data = Data()
        data.append(0x78)
        data.append(0x56)
        data.append(0x34)
        data.append(0x12)
        
        let element = DataElement(tag: .fileMetaInformationGroupLength, vr: .UL, length: 4, valueData: data)
        #expect(element.uint32Value == 0x12345678)
    }
    
    @Test("UInt16 array value extraction")
    func testUInt16Values() {
        var data = Data()
        // Three UInt16 values: 100, 200, 300
        data.append(contentsOf: [0x64, 0x00]) // 100
        data.append(contentsOf: [0xC8, 0x00]) // 200
        data.append(contentsOf: [0x2C, 0x01]) // 300
        
        let element = DataElement(tag: Tag(group: 0x0028, element: 0x0010), vr: .US, length: 6, valueData: data)
        let values = element.uint16Values
        
        #expect(values?.count == 3)
        #expect(values?[0] == 100)
        #expect(values?[1] == 200)
        #expect(values?[2] == 300)
    }
    
    @Test("UInt32 array value extraction")
    func testUInt32Values() {
        var data = Data()
        // Two UInt32 values: 1000, 2000
        data.append(contentsOf: [0xE8, 0x03, 0x00, 0x00]) // 1000
        data.append(contentsOf: [0xD0, 0x07, 0x00, 0x00]) // 2000
        
        let element = DataElement(tag: Tag(group: 0x0008, element: 0x0000), vr: .UL, length: 8, valueData: data)
        let values = element.uint32Values
        
        #expect(values?.count == 2)
        #expect(values?[0] == 1000)
        #expect(values?[1] == 2000)
    }
    
    @Test("Float32 array value extraction")
    func testFloat32Values() {
        var data = Data()
        // Two Float32 values: 1.5, 2.5
        let float1: Float32 = 1.5
        let float2: Float32 = 2.5
        
        withUnsafeBytes(of: float1.bitPattern) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: float2.bitPattern) { data.append(contentsOf: $0) }
        
        let element = DataElement(tag: Tag(group: 0x0020, element: 0x0032), vr: .FL, length: 8, valueData: data)
        let values = element.float32Values
        
        #expect(values?.count == 2)
        #expect(values?[0] == 1.5)
        #expect(values?[1] == 2.5)
    }
    
    @Test("Float64 array value extraction")
    func testFloat64Values() {
        var data = Data()
        // Two Float64 values: 3.14159, 2.71828
        let double1: Float64 = 3.14159
        let double2: Float64 = 2.71828
        
        withUnsafeBytes(of: double1.bitPattern) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: double2.bitPattern) { data.append(contentsOf: $0) }
        
        let element = DataElement(tag: Tag(group: 0x0018, element: 0x0050), vr: .FD, length: 16, valueData: data)
        let values = element.float64Values
        
        #expect(values?.count == 2)
        #expect(values?[0] == 3.14159)
        #expect(values?[1] == 2.71828)
    }
    
    // MARK: - Date/Time Value Extraction
    
    @Test("DICOM Date (DA) value extraction")
    func testDateValue() {
        let data = "20250130".data(using: .utf8)!
        let element = DataElement(tag: Tag.studyDate, vr: .DA, length: UInt32(data.count), valueData: data)
        
        let date = element.dateValue
        #expect(date != nil)
        #expect(date?.year == 2025)
        #expect(date?.month == 1)
        #expect(date?.day == 30)
    }
    
    @Test("DICOM Time (TM) value extraction")
    func testTimeValue() {
        let data = "143025.123456".data(using: .utf8)!
        let element = DataElement(tag: Tag.studyTime, vr: .TM, length: UInt32(data.count), valueData: data)
        
        let time = element.timeValue
        #expect(time != nil)
        #expect(time?.hour == 14)
        #expect(time?.minute == 30)
        #expect(time?.second == 25)
        #expect(time?.microsecond == 123456)
    }
    
    @Test("DICOM DateTime (DT) value extraction")
    func testDateTimeValue() {
        let data = "20250130143025+0530".data(using: .utf8)!
        let element = DataElement(tag: Tag(group: 0x0008, element: 0x002A), vr: .DT, length: UInt32(data.count), valueData: data)
        
        let dateTime = element.dateTimeValue
        #expect(dateTime != nil)
        #expect(dateTime?.year == 2025)
        #expect(dateTime?.month == 1)
        #expect(dateTime?.day == 30)
        #expect(dateTime?.hour == 14)
        #expect(dateTime?.minute == 30)
        #expect(dateTime?.second == 25)
        #expect(dateTime?.timezoneOffsetMinutes == 330)
    }
    
    @Test("Foundation Date from DA value")
    func testFoundationDateFromDA() {
        let data = "20250130".data(using: .utf8)!
        let element = DataElement(tag: Tag.studyDate, vr: .DA, length: UInt32(data.count), valueData: data)
        
        let date = element.foundationDateValue
        #expect(date != nil)
    }
    
    @Test("Foundation Date from DT value")
    func testFoundationDateFromDT() {
        let data = "20250130143025".data(using: .utf8)!
        let element = DataElement(tag: Tag(group: 0x0008, element: 0x002A), vr: .DT, length: UInt32(data.count), valueData: data)
        
        let date = element.foundationDateValue
        #expect(date != nil)
    }
    
    @Test("Date value returns nil for wrong VR")
    func testDateValueWrongVR() {
        let data = "20250130".data(using: .utf8)!
        // Using LO (Long String) instead of DA
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.dateValue == nil)
    }
    
    @Test("Time value returns nil for wrong VR")
    func testTimeValueWrongVR() {
        let data = "143025".data(using: .utf8)!
        // Using LO (Long String) instead of TM
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.timeValue == nil)
    }
    
    // MARK: - Age String Value Extraction
    
    @Test("DICOM Age String (AS) value extraction")
    func testAgeValue() {
        let data = "018Y".data(using: .utf8)!
        let element = DataElement(tag: Tag.patientAge, vr: .AS, length: UInt32(data.count), valueData: data)
        
        let age = element.ageValue
        #expect(age != nil)
        #expect(age?.value == 18)
        #expect(age?.unit == .years)
    }
    
    @Test("Age value returns nil for wrong VR")
    func testAgeValueWrongVR() {
        let data = "018Y".data(using: .utf8)!
        // Using LO (Long String) instead of AS
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.ageValue == nil)
    }
    
    // MARK: - Decimal String Value Extraction
    
    @Test("DICOM Decimal String (DS) value extraction")
    func testDecimalStringValue() {
        let data = "3.14159".data(using: .utf8)!
        let element = DataElement(tag: Tag.sliceThickness, vr: .DS, length: UInt32(data.count), valueData: data)
        
        let ds = element.decimalStringValue
        #expect(ds != nil)
        #expect(ds?.value == 3.14159)
    }
    
    @Test("DICOM Decimal String multiple values extraction")
    func testDecimalStringValuesMultiple() {
        let data = "0.3125\\0.3125".data(using: .utf8)!
        let element = DataElement(tag: Tag.pixelSpacing, vr: .DS, length: UInt32(data.count), valueData: data)
        
        let values = element.decimalStringValues
        #expect(values != nil)
        #expect(values?.count == 2)
        #expect(values?[0].value == 0.3125)
        #expect(values?[1].value == 0.3125)
    }
    
    @Test("Decimal String value returns nil for wrong VR")
    func testDecimalStringValueWrongVR() {
        let data = "3.14159".data(using: .utf8)!
        // Using LO (Long String) instead of DS
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.decimalStringValue == nil)
        #expect(element.decimalStringValues == nil)
    }
    
    // MARK: - Integer String Value Extraction
    
    @Test("DICOM Integer String (IS) value extraction")
    func testIntegerStringValue() {
        let data = "12345".data(using: .utf8)!
        let element = DataElement(tag: Tag.instanceNumber, vr: .IS, length: UInt32(data.count), valueData: data)
        
        let is_value = element.integerStringValue
        #expect(is_value != nil)
        #expect(is_value?.value == 12345)
    }
    
    @Test("DICOM Integer String multiple values extraction")
    func testIntegerStringValuesMultiple() {
        let data = "1\\2\\3".data(using: .utf8)!
        let element = DataElement(tag: Tag(group: 0x0020, element: 0x0013), vr: .IS, length: UInt32(data.count), valueData: data)
        
        let values = element.integerStringValues
        #expect(values != nil)
        #expect(values?.count == 3)
        #expect(values?[0].value == 1)
        #expect(values?[1].value == 2)
        #expect(values?[2].value == 3)
    }
    
    @Test("Integer String value returns nil for wrong VR")
    func testIntegerStringValueWrongVR() {
        let data = "12345".data(using: .utf8)!
        // Using LO (Long String) instead of IS
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.integerStringValue == nil)
        #expect(element.integerStringValues == nil)
    }
    
    // MARK: - Person Name Value Extraction
    
    @Test("DICOM Person Name (PN) value extraction")
    func testPersonNameValue() {
        let data = "Doe^John^Robert^Dr.^Jr.".data(using: .utf8)!
        let element = DataElement(tag: Tag.patientName, vr: .PN, length: UInt32(data.count), valueData: data)
        
        let name = element.personNameValue
        #expect(name != nil)
        #expect(name?.familyName == "Doe")
        #expect(name?.givenName == "John")
        #expect(name?.middleName == "Robert")
        #expect(name?.namePrefix == "Dr.")
        #expect(name?.nameSuffix == "Jr.")
    }
    
    @Test("DICOM Person Name multiple values extraction")
    func testPersonNameValuesMultiple() {
        let data = "Doe^John\\Smith^Jane".data(using: .utf8)!
        let element = DataElement(tag: Tag.patientName, vr: .PN, length: UInt32(data.count), valueData: data)
        
        let values = element.personNameValues
        #expect(values != nil)
        #expect(values?.count == 2)
        #expect(values?[0].familyName == "Doe")
        #expect(values?[0].givenName == "John")
        #expect(values?[1].familyName == "Smith")
        #expect(values?[1].givenName == "Jane")
    }
    
    @Test("Person Name value returns nil for wrong VR")
    func testPersonNameValueWrongVR() {
        let data = "Doe^John".data(using: .utf8)!
        // Using LO (Long String) instead of PN
        let element = DataElement(tag: Tag.patientID, vr: .LO, length: UInt32(data.count), valueData: data)
        
        #expect(element.personNameValue == nil)
        #expect(element.personNameValues == nil)
    }
    
    // MARK: - Extended VR Support Tests
    
    @Test("UInt16 value extraction with SS VR")
    func testUInt16ValueWithSS() {
        var data = Data()
        data.append(0x00)  // 512 in little endian
        data.append(0x02)
        
        // SS (Signed Short) should also work for uint16Value
        let element = DataElement(tag: Tag.rows, vr: .SS, length: 2, valueData: data)
        #expect(element.uint16Value == 512)
    }
    
    @Test("UInt16 value extraction with UN VR")
    func testUInt16ValueWithUN() {
        var data = Data()
        data.append(0x00)  // 256 in little endian
        data.append(0x01)
        
        // UN (Unknown) with 2-byte data should work for uint16Value
        let element = DataElement(tag: Tag.columns, vr: .UN, length: 2, valueData: data)
        #expect(element.uint16Value == 256)
    }
    
    @Test("UInt16 value extraction with OW VR")
    func testUInt16ValueWithOW() {
        var data = Data()
        data.append(0x08)  // 2056 in little endian
        data.append(0x08)
        
        // OW (Other Word) should work for uint16Value
        let element = DataElement(tag: Tag.bitsAllocated, vr: .OW, length: 2, valueData: data)
        #expect(element.uint16Value == 2056)
    }
    
    @Test("UInt16 values extraction with SS VR")
    func testUInt16ValuesWithSS() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x02]) // 512
        data.append(contentsOf: [0x00, 0x01]) // 256
        
        // SS VR with multiple values
        let element = DataElement(tag: Tag.rows, vr: .SS, length: 4, valueData: data)
        let values = element.uint16Values
        #expect(values?.count == 2)
        #expect(values?[0] == 512)
        #expect(values?[1] == 256)
    }
    
    @Test("UInt32 value extraction with SL VR")
    func testUInt32ValueWithSL() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x10, 0x00, 0x00]) // 4096 in little endian
        
        // SL (Signed Long) should also work for uint32Value
        let element = DataElement(tag: Tag.fileMetaInformationGroupLength, vr: .SL, length: 4, valueData: data)
        #expect(element.uint32Value == 4096)
    }
    
    @Test("UInt32 value extraction with UN VR")
    func testUInt32ValueWithUN() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x04, 0x00, 0x00]) // 1024 in little endian
        
        // UN (Unknown) with 4-byte data should work for uint32Value
        let element = DataElement(tag: Tag.fileMetaInformationGroupLength, vr: .UN, length: 4, valueData: data)
        #expect(element.uint32Value == 1024)
    }
    
    @Test("UInt32 value extraction with OL VR")
    func testUInt32ValueWithOL() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x08, 0x00, 0x00]) // 2048 in little endian
        
        // OL (Other Long) should work for uint32Value
        let element = DataElement(tag: Tag.fileMetaInformationGroupLength, vr: .OL, length: 4, valueData: data)
        #expect(element.uint32Value == 2048)
    }
    
    @Test("UInt16 value returns nil for incompatible VR")
    func testUInt16ValueReturnsNilForIncompatibleVR() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x01])
        
        // UL is a 32-bit VR, not compatible with uint16Value
        let element = DataElement(tag: Tag.rows, vr: .UL, length: 2, valueData: data)
        #expect(element.uint16Value == nil)
    }
    
    @Test("UInt32 value returns nil for incompatible VR")
    func testUInt32ValueReturnsNilForIncompatibleVR() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00])
        
        // US is a 16-bit VR, not compatible with uint32Value
        let element = DataElement(tag: Tag.fileMetaInformationGroupLength, vr: .US, length: 4, valueData: data)
        #expect(element.uint32Value == nil)
    }
    
    // MARK: - OB VR Support Tests (for non-compliant DICOM files)
    
    @Test("UInt16 value extraction with OB VR (2 bytes)")
    func testUInt16ValueWithOB() {
        var data = Data()
        data.append(0x00)  // 512 in little endian
        data.append(0x02)
        
        // OB (Other Byte) with exactly 2 bytes should work for uint16Value
        // This supports non-compliant DICOM files that encode US attributes as OB
        let element = DataElement(tag: Tag.rows, vr: .OB, length: 2, valueData: data)
        #expect(element.uint16Value == 512)
    }
    
    @Test("UInt16 value extraction with OB VR returns nil for non-2-byte data")
    func testUInt16ValueWithOBReturnsNilForNonTwoBytes() {
        // OB with 3 bytes should not be interpretable as a single uint16
        var data3 = Data()
        data3.append(contentsOf: [0x00, 0x02, 0xFF])
        let element3 = DataElement(tag: Tag.rows, vr: .OB, length: 3, valueData: data3)
        #expect(element3.uint16Value == nil)
        
        // OB with 1 byte should not be interpretable as uint16
        var data1 = Data()
        data1.append(0x02)
        let element1 = DataElement(tag: Tag.rows, vr: .OB, length: 1, valueData: data1)
        #expect(element1.uint16Value == nil)
        
        // OB with 4 bytes should not be interpretable as single uint16
        var data4 = Data()
        data4.append(contentsOf: [0x00, 0x02, 0x00, 0x01])
        let element4 = DataElement(tag: Tag.rows, vr: .OB, length: 4, valueData: data4)
        #expect(element4.uint16Value == nil)
    }
    
    @Test("UInt16 values extraction with OB VR (even byte count)")
    func testUInt16ValuesWithOB() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x02]) // 512
        data.append(contentsOf: [0x00, 0x01]) // 256
        
        // OB VR with even byte count (4 bytes = 2 uint16 values)
        let element = DataElement(tag: Tag.rows, vr: .OB, length: 4, valueData: data)
        let values = element.uint16Values
        #expect(values?.count == 2)
        #expect(values?[0] == 512)
        #expect(values?[1] == 256)
    }
    
    @Test("UInt16 values extraction with OB VR returns nil for odd byte count")
    func testUInt16ValuesWithOBReturnsNilForOddByteCount() {
        // OB with odd byte count (3 bytes) cannot be evenly split into uint16 values
        var data = Data()
        data.append(contentsOf: [0x00, 0x02, 0xFF])
        
        let element = DataElement(tag: Tag.rows, vr: .OB, length: 3, valueData: data)
        #expect(element.uint16Values == nil)
    }
    
    // MARK: - IS VR Support Tests (for non-compliant DICOM files)
    
    @Test("UInt16 value extraction with IS VR")
    func testUInt16ValueWithIS() {
        // IS (Integer String) should be parseable as uint16 for non-compliant DICOM files
        // that encode pixel attributes like Rows, Columns, Bits Allocated, etc. as IS instead of US
        let data = "512".data(using: .utf8)!
        let element = DataElement(tag: Tag.rows, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 512)
    }
    
    @Test("UInt16 value extraction with IS VR and whitespace padding")
    func testUInt16ValueWithISWhitespacePadded() {
        // IS values can be padded with whitespace
        let data = "  256  ".data(using: .utf8)!
        let element = DataElement(tag: Tag.columns, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 256)
    }
    
    @Test("UInt16 value extraction with IS VR at maximum value")
    func testUInt16ValueWithISMaxValue() {
        // Maximum uint16 value (65535)
        let data = "65535".data(using: .utf8)!
        let element = DataElement(tag: Tag.rows, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 65535)
    }
    
    @Test("UInt16 value extraction with IS VR returns nil for negative values")
    func testUInt16ValueWithISReturnsNilForNegative() {
        // Negative values cannot be converted to uint16
        let data = "-1".data(using: .utf8)!
        let element = DataElement(tag: Tag.rows, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == nil)
    }
    
    @Test("UInt16 value extraction with IS VR returns nil for values exceeding uint16 range")
    func testUInt16ValueWithISReturnsNilForOverflow() {
        // Values > 65535 cannot be converted to uint16
        let data = "65536".data(using: .utf8)!
        let element = DataElement(tag: Tag.rows, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == nil)
    }
    
    @Test("UInt16 value extraction with IS VR returns nil for non-numeric string")
    func testUInt16ValueWithISReturnsNilForInvalidString() {
        // Non-numeric strings cannot be converted to uint16
        let data = "abc".data(using: .utf8)!
        let element = DataElement(tag: Tag.rows, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == nil)
    }
    
    @Test("UInt16 value extraction with IS VR for Bits Allocated")
    func testUInt16ValueWithISForBitsAllocated() {
        // Common case: Bits Allocated encoded as IS instead of US
        let data = "16".data(using: .utf8)!
        let element = DataElement(tag: Tag.bitsAllocated, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 16)
    }
    
    @Test("UInt16 value extraction with IS VR for Bits Stored")
    func testUInt16ValueWithISForBitsStored() {
        // Common case: Bits Stored encoded as IS instead of US
        let data = "12".data(using: .utf8)!
        let element = DataElement(tag: Tag.bitsStored, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 12)
    }
    
    @Test("UInt16 value extraction with IS VR for High Bit")
    func testUInt16ValueWithISForHighBit() {
        // Common case: High Bit encoded as IS instead of US
        let data = "11".data(using: .utf8)!
        let element = DataElement(tag: Tag.highBit, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 11)
    }
    
    @Test("UInt16 value extraction with IS VR for Pixel Representation")
    func testUInt16ValueWithISForPixelRepresentation() {
        // Common case: Pixel Representation encoded as IS instead of US
        let data = "0".data(using: .utf8)!
        let element = DataElement(tag: Tag.pixelRepresentation, vr: .IS, length: UInt32(data.count), valueData: data)
        #expect(element.uint16Value == 0)
    }
}
