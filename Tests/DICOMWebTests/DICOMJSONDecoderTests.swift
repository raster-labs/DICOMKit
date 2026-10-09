import Testing
import Foundation
@testable import DICOMWeb
import DICOMCore

@Suite("DICOMJSONDecoder Tests")
struct DICOMJSONDecoderTests {
    
    let decoder = DICOMJSONDecoder()
    
    // MARK: - String VR Decoding
    
    @Test("Decode simple string element")
    func testDecodeStringElement() throws {
        let json = """
        {
            "00100020": {
                "vr": "LO",
                "Value": ["Patient001"]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        #expect(elements.count == 1)
        
        let element = elements.first
        #expect(element?.tag == Tag.patientID)
        #expect(element?.vr == .LO)
        #expect(element?.stringValue == "Patient001")
    }
    
    @Test("Decode multi-value string")
    func testDecodeMultiValueString() throws {
        let json = """
        {
            "00080060": {
                "vr": "CS",
                "Value": ["CT", "MR", "US"]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.stringValues == ["CT", "MR", "US"])
    }
    
    @Test("Decode UID element")
    func testDecodeUIDElement() throws {
        let json = """
        {
            "00080016": {
                "vr": "UI",
                "Value": ["1.2.840.10008.5.1.4.1.1.2"]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .UI)
        #expect(element?.stringValue == "1.2.840.10008.5.1.4.1.1.2")
    }
    
    // MARK: - Numeric VR Decoding
    
    @Test("Decode US element")
    func testDecodeUSElement() throws {
        let json = """
        {
            "00280010": {
                "vr": "US",
                "Value": [512]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .US)
        #expect(element?.uint16Value == 512)
    }
    
    @Test("Decode multiple US values")
    func testDecodeMultipleUSValues() throws {
        let json = """
        {
            "00281050": {
                "vr": "US",
                "Value": [100, 200, 300]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.uint16Values == [100, 200, 300])
    }
    
    @Test("Decode SL element")
    func testDecodeSLElement() throws {
        let json = """
        {
            "00189310": {
                "vr": "SL",
                "Value": [-100]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .SL)
        #expect(element?.int32Value == -100)
    }
    
    @Test("Decode FL element")
    func testDecodeFLElement() throws {
        let json = """
        {
            "00180050": {
                "vr": "FL",
                "Value": [1.5]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .FL)
        #expect(element?.float32Value == 1.5)
    }
    
    @Test("Decode FD element")
    func testDecodeFDElement() throws {
        let json = """
        {
            "00181050": {
                "vr": "FD",
                "Value": [3.14159]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .FD)
        if let value = element?.float64Value {
            #expect(abs(value - 3.14159) < 0.00001)
        }
    }
    
    // MARK: - Person Name Decoding
    
    @Test("Decode person name with alphabetic")
    func testDecodePersonNameAlphabetic() throws {
        let json = """
        {
            "00100010": {
                "vr": "PN",
                "Value": [{"Alphabetic": "Doe^John"}]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .PN)
        let pn = element?.personNameValue
        #expect(pn?.familyName == "Doe")
        #expect(pn?.givenName == "John")
    }
    
    @Test("Decode person name with all components")
    func testDecodePersonNameFull() throws {
        let json = """
        {
            "00100010": {
                "vr": "PN",
                "Value": [{
                    "Alphabetic": "Doe^John^Robert^Dr.^Jr."
                }]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let pn = elements.first?.personNameValue
        
        #expect(pn?.familyName == "Doe")
        #expect(pn?.givenName == "John")
        #expect(pn?.middleName == "Robert")
        #expect(pn?.namePrefix == "Dr.")
        #expect(pn?.nameSuffix == "Jr.")
    }
    
    @Test("Decode person name with ideographic")
    func testDecodePersonNameIdeographic() throws {
        let json = """
        {
            "00100010": {
                "vr": "PN",
                "Value": [{
                    "Alphabetic": "Yamada^Tarou",
                    "Ideographic": "山田^太郎"
                }]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let pn = elements.first?.personNameValue
        
        #expect(pn?.alphabetic.familyName == "Yamada")
        #expect(pn?.ideographic.familyName == "山田")
    }
    
    // MARK: - Inline Binary Decoding
    
    @Test("Decode inline binary as a sibling of vr (PS3.18 F.2.2)")
    func testDecodeInlineBinary() throws {
        let originalData = Data([0x00, 0x01, 0x02, 0x03])
        let base64 = originalData.base64EncodedString()
        
        let json = """
        {
            "7FE00010": {
                "vr": "OB",
                "InlineBinary": "\(base64)"
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .OB)
        #expect(element?.valueData == originalData)
    }
    
    @Test("Decode inline binary in the pre-2026 DICOMKit layout (inside Value)")
    func testDecodeLegacyInlineBinaryLayout() throws {
        let originalData = Data([0x00, 0x01, 0x02, 0x03])
        let base64 = originalData.base64EncodedString()
        
        let json = """
        {
            "7FE00010": {
                "vr": "OB",
                "Value": [{"InlineBinary": "\(base64)"}]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .OB)
        #expect(element?.valueData == originalData)
    }
    
    // MARK: - Sequence Decoding
    
    @Test("Decode sequence")
    func testDecodeSequence() throws {
        let json = """
        {
            "0040A730": {
                "vr": "SQ",
                "Value": [
                    {
                        "00080100": {
                            "vr": "SH",
                            "Value": ["T-D1100"]
                        }
                    }
                ]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .SQ)
        #expect(element?.sequenceItems?.count == 1)
        
        let nestedElement = element?.sequenceItems?.first?.allElements.first
        #expect(nestedElement?.stringValue == "T-D1100")
    }
    
    @Test("Decode nested sequence")
    func testDecodeNestedSequence() throws {
        let json = """
        {
            "00081115": {
                "vr": "SQ",
                "Value": [
                    {
                        "00081199": {
                            "vr": "SQ",
                            "Value": [
                                {
                                    "00081150": {
                                        "vr": "UI",
                                        "Value": ["1.2.3.4"]
                                    }
                                }
                            ]
                        }
                    }
                ]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let outerSeq = elements.first?.sequenceItems?.first
        let innerSeq = outerSeq?.allElements.first?.sequenceItems?.first
        
        #expect(innerSeq?.allElements.first?.stringValue == "1.2.3.4")
    }
    
    // MARK: - Empty Value Decoding
    
    @Test("Decode empty value")
    func testDecodeEmptyValue() throws {
        let json = """
        {
            "00100020": {
                "vr": "LO"
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .LO)
        #expect(element?.valueData.isEmpty == true)
    }
    
    @Test("Decode empty array value")
    func testDecodeEmptyArrayValue() throws {
        let json = """
        {
            "00100020": {
                "vr": "LO",
                "Value": []
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.valueData.isEmpty == true)
    }
    
    // MARK: - Attribute Tag Decoding
    
    @Test("Decode AT element")
    func testDecodeATElement() throws {
        let json = """
        {
            "00200037": {
                "vr": "AT",
                "Value": ["00100010"]
            }
        }
        """
        
        let elements = try decoder.decode(string: json)
        let element = elements.first
        
        #expect(element?.vr == .AT)
        // AT is stored as group/element pairs
        #expect(element?.valueData.count == 4)
    }
    
    // MARK: - Multiple Datasets Decoding
    
    @Test("Decode multiple datasets")
    func testDecodeMultiple() throws {
        let json = """
        [
            {"00100020": {"vr": "LO", "Value": ["ID001"]}},
            {"00100020": {"vr": "LO", "Value": ["ID002"]}}
        ]
        """
        
        let datasets = try decoder.decodeMultiple(json.data(using: .utf8)!)
        
        #expect(datasets.count == 2)
        #expect(datasets[0].first?.stringValue == "ID001")
        #expect(datasets[1].first?.stringValue == "ID002")
    }
    
    // MARK: - Error Cases
    
    @Test("Invalid JSON throws error")
    func testInvalidJSONThrows() {
        let invalidJSON = "not valid json"
        
        #expect(throws: Error.self) {
            _ = try decoder.decode(string: invalidJSON)
        }
    }
    
    @Test("Missing VR throws error")
    func testMissingVRThrows() {
        let json = """
        {
            "00100020": {
                "Value": ["Patient001"]
            }
        }
        """
        
        #expect(throws: DICOMwebError.self) {
            _ = try decoder.decode(string: json)
        }
    }
    
    @Test("Invalid tag format throws error")
    func testInvalidTagThrows() {
        let json = """
        {
            "INVALID": {
                "vr": "LO",
                "Value": ["test"]
            }
        }
        """
        
        #expect(throws: DICOMwebError.self) {
            _ = try decoder.decode(string: json)
        }
    }
    
    // MARK: - Round Trip Tests
    
    @Test("Round trip encoding/decoding")
    func testRoundTrip() throws {
        let encoder = DICOMJSONEncoder()
        
        // Create test elements
        var patientNameData = "Doe^John".data(using: .utf8)!
        if patientNameData.count % 2 != 0 { patientNameData.append(0x20) }
        let patientName = DataElement(
            tag: .patientName,
            vr: .PN,
            length: UInt32(patientNameData.count),
            valueData: patientNameData
        )
        
        var patientIDData = "ID001".data(using: .utf8)!
        if patientIDData.count % 2 != 0 { patientIDData.append(0x20) }
        let patientID = DataElement(
            tag: .patientID,
            vr: .LO,
            length: UInt32(patientIDData.count),
            valueData: patientIDData
        )
        
        // Encode
        let jsonData = try encoder.encode([patientName, patientID])
        
        // Decode
        let decoded = try decoder.decode(jsonData)
        
        #expect(decoded.count == 2)
        
        // Verify patient name
        let decodedPN = decoded.first { $0.tag == .patientName }
        #expect(decodedPN?.personNameValue?.familyName == "Doe")
        #expect(decodedPN?.personNameValue?.givenName == "John")
        
        // Verify patient ID
        let decodedID = decoded.first { $0.tag == .patientID }
        #expect(decodedID?.stringValue == "ID001")
    }
}
