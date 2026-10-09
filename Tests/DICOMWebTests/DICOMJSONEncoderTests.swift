import Testing
import Foundation
@testable import DICOMWeb
import DICOMCore

@Suite("DICOMJSONEncoder Tests")
struct DICOMJSONEncoderTests {
    
    let encoder = DICOMJSONEncoder()
    
    // MARK: - String VR Encoding
    
    @Test("Encode simple string element")
    func testEncodeStringElement() throws {
        let element = createStringElement(tag: Tag.patientName, vr: VR.PN, value: "Doe^John")
        let result = try encoder.encodeToObject([element])
        
        let tagKey = "00100010" // Patient Name tag
        #expect(result[tagKey] != nil)
        
        if let elementDict = result[tagKey] as? [String: Any] {
            #expect(elementDict["vr"] as? String == "PN")
        }
    }
    
    @Test("Encode UI element")
    func testEncodeUIElement() throws {
        let element = createStringElement(
            tag: Tag(group: 0x0008, element: 0x0016), // SOP Class UID
            vr: VR.UI,
            value: "1.2.840.10008.5.1.4.1.1.2"
        )
        let result = try encoder.encodeToObject([element])
        
        let tagKey = "00080016"
        if let elementDict = result[tagKey] as? [String: Any],
           let values = elementDict["Value"] as? [String] {
            #expect(values.first == "1.2.840.10008.5.1.4.1.1.2")
        } else {
            #expect(Bool(false), "Expected Value array with string")
        }
    }
    
    @Test("Encode multiple value string")
    func testEncodeMultiValueString() throws {
        let element = createStringElement(
            tag: Tag(group: 0x0008, element: 0x0060),
            vr: VR.CS,
            value: "CT\\MR\\US"
        )
        let result = try encoder.encodeToObject([element])
        
        let tagKey = "00080060"
        if let elementDict = result[tagKey] as? [String: Any],
           let values = elementDict["Value"] as? [String] {
            #expect(values == ["CT", "MR", "US"])
        }
    }
    
    // MARK: - Numeric VR Encoding
    
    @Test("Encode US element")
    func testEncodeUSElement() throws {
        let element = createNumericElement(tag: Tag.rows, vr: VR.US, value: UInt16(512))
        let result = try encoder.encodeToObject([element])
        
        let tagKey = "00280010" // Rows tag
        if let elementDict = result[tagKey] as? [String: Any],
           let values = elementDict["Value"] as? [Any] {
            #expect(values.count == 1)
            #expect((values.first as? NSNumber)?.uint16Value == 512)
        }
    }
    
    @Test("Encode FL element")
    func testEncodeFLElement() throws {
        var data = Data()
        var value: Float32 = 1.5
        data.append(Data(bytes: &value, count: 4))
        
        let element = DataElement(
            tag: Tag(group: 0x0018, element: 0x0050),
            vr: VR.FL,
            length: 4,
            valueData: data
        )
        
        let result = try encoder.encodeToObject([element])
        
        if let elementDict = result["00180050"] as? [String: Any],
           let values = elementDict["Value"] as? [Any] {
            #expect((values.first as? NSNumber)?.floatValue == 1.5)
        }
    }
    
    // MARK: - Person Name Encoding
    
    @Test("Encode person name with components")
    func testEncodePersonName() throws {
        let element = createStringElement(
            tag: Tag.patientName,
            vr: VR.PN,
            value: "Doe^John^Robert^Dr.^Jr."
        )
        
        let result = try encoder.encodeToObject([element])
        
        if let elementDict = result["00100010"] as? [String: Any],
           let values = elementDict["Value"] as? [[String: Any]] {
            #expect(values.count == 1)
            let alphabetic: String? = values.first?["Alphabetic"] as? String
            #expect(alphabetic == "Doe^John^Robert^Dr.^Jr.")
        }
    }
    
    @Test("Encode person name with ideographic")
    func testEncodePersonNameIdeographic() throws {
        let element = createStringElement(
            tag: Tag.patientName,
            vr: VR.PN,
            value: "Yamada^Tarou=山田^太郎"
        )
        
        let result = try encoder.encodeToObject([element])
        
        if let elementDict = result["00100010"] as? [String: Any],
           let values = elementDict["Value"] as? [[String: Any]] {
            let alphabetic: String? = values.first?["Alphabetic"] as? String
            let ideographic: String? = values.first?["Ideographic"] as? String
            #expect(alphabetic == "Yamada^Tarou")
            #expect(ideographic == "山田^太郎")
        }
    }
    
    // MARK: - Binary Data Encoding
    
    @Test("Encode small binary data as inline")
    func testEncodeInlineBinary() throws {
        let binaryData = Data([0x00, 0x01, 0x02, 0x03])
        let element = DataElement(
            tag: Tag(group: 0x7FE0, element: 0x0010),
            vr: VR.OB,
            length: 4,
            valueData: binaryData
        )
        
        let config = DICOMJSONEncoder.Configuration(inlineBinaryThreshold: 1024)
        let encoder = DICOMJSONEncoder(configuration: config)
        let result = try encoder.encodeToObject([element])
        
        // PS3.18 F.2.2: InlineBinary is a sibling of vr, not an element of Value
        let elementDict = result["7FE00010"] as? [String: Any]
        #expect(elementDict?["InlineBinary"] as? String == binaryData.base64EncodedString())
        #expect(elementDict?["Value"] == nil)
    }
    
    // MARK: - Sequence Encoding
    
    @Test("Encode sequence element")
    func testEncodeSequence() throws {
        let nestedElement = createStringElement(
            tag: Tag(group: 0x0008, element: 0x0100), // Code Value
            vr: VR.SH,
            value: "T-D1100"
        )
        let sequenceItem = SequenceItem(elements: [nestedElement])
        
        let sequenceElement = DataElement(
            tag: Tag(group: 0x0040, element: 0xA730), // Content Sequence
            vr: VR.SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [sequenceItem]
        )
        
        let result = try encoder.encodeToObject([sequenceElement])
        
        if let elementDict = result["0040A730"] as? [String: Any],
           let values = elementDict["Value"] as? [[String: Any]] {
            #expect(values.count == 1)
            #expect(values.first?["00080100"] != nil)
        }
    }
    
    // MARK: - Empty Value Handling
    
    @Test("Empty attribute preserved as {vr} with no Value by default (PS3.18 F.2.5)")
    func testEmptyValuesPreserved() throws {
        let element = createStringElement(tag: Tag.patientID, vr: VR.LO, value: "")
        let result = try encoder.encodeToObject([element])
        
        let elementDict = result["00100020"] as? [String: Any]
        #expect(elementDict?["vr"] as? String == "LO")
        #expect(elementDict?["Value"] == nil)
        #expect(elementDict?.count == 1)
    }
    
    @Test("Empty attributes dropped when includeEmptyValues is false")
    func testEmptyValuesExcluded() throws {
        let config = DICOMJSONEncoder.Configuration(includeEmptyValues: false)
        let encoder = DICOMJSONEncoder(configuration: config)
        
        let element = createStringElement(tag: Tag.patientID, vr: VR.LO, value: "")
        let result = try encoder.encodeToObject([element])
        
        #expect(result["00100020"] == nil)
    }
    
    // MARK: - JSON Output
    
    @Test("Encode to JSON string")
    func testEncodeToString() throws {
        let element = createStringElement(tag: Tag.patientName, vr: VR.PN, value: "Doe^John")
        let jsonString = try encoder.encodeToString([element])
        
        #expect(jsonString.contains("00100010"))
        #expect(jsonString.contains("PN"))
    }
    
    @Test("Encode to pretty printed JSON")
    func testEncodePrettyPrinted() throws {
        let config = DICOMJSONEncoder.Configuration(prettyPrinted: true)
        let encoder = DICOMJSONEncoder(configuration: config)
        
        let element = createStringElement(tag: Tag.patientName, vr: VR.PN, value: "Doe^John")
        let jsonString = try encoder.encodeToString([element])
        
        // Pretty printed JSON contains newlines
        #expect(jsonString.contains("\n"))
    }
    
    // MARK: - Multiple Datasets
    
    @Test("Encode multiple datasets")
    func testEncodeMultiple() throws {
        let elements1 = [createStringElement(tag: Tag.patientID, vr: VR.LO, value: "ID001")]
        let elements2 = [createStringElement(tag: Tag.patientID, vr: VR.LO, value: "ID002")]
        
        let data = try encoder.encodeMultiple([elements1, elements2])
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        #expect(array?.count == 2)
    }
    
    // MARK: - Helper Functions
    
    private func createStringElement(tag: DICOMCore.Tag, vr: VR, value: String) -> DataElement {
        var data = value.data(using: .utf8) ?? Data()
        if data.count % 2 != 0 {
            data.append(vr == VR.UI ? 0x00 : 0x20)
        }
        return DataElement(tag: tag, vr: vr, length: UInt32(data.count), valueData: data)
    }
    
    private func createNumericElement(tag: DICOMCore.Tag, vr: VR, value: UInt16) -> DataElement {
        var v = value
        let data = Data(bytes: &v, count: 2)
        return DataElement(tag: tag, vr: vr, length: 2, valueData: data)
    }
}
