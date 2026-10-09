// NEMA-verified: 2026a, checked 2026-10-01 — PS3.10 2026a Table 7.1-1: (0002,0002)/(0002,0003) of a file reverse-converted from DICOM JSON / XML equal the data set's (0008,0016)/(0008,0018)
//
// D112: `DataExchangeWorkflow.decode` (dicom-json / dicom-xml `--reverse`) wrote Secondary
// Capture and a fresh UID into the File Meta whatever the data set carried (root cause D175).

import XCTest
@testable import DICOMWeb
import DICOMKit
import DICOMCore

final class DataExchangeFileMetaTests: XCTestCase {

    func test_decodeJSON_fileMetaEqualsDataSetUIDs() throws {
        let json = """
        {
          "00080016": {"vr": "UI", "Value": ["1.2.840.10008.5.1.4.1.1.2"]},
          "00080018": {"vr": "UI", "Value": ["1.2.826.0.1.3680043.10.511.99.42"]},
          "00100010": {"vr": "PN", "Value": [{"Alphabetic": "DOE^JOHN"}]}
        }
        """
        let (data, _) = try DataExchangeWorkflow.decode(
            textData: Data(json.utf8), format: .json, options: .init(reverse: true))
        let file = try DICOMFile.read(from: data)
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID), "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.826.0.1.3680043.10.511.99.42")
        XCTAssertEqual(file.dataSet.string(for: .sopInstanceUID), "1.2.826.0.1.3680043.10.511.99.42")
    }
}
