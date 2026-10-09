import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_info

/// `--tag` accepts PS3.6 2026a keywords exactly (the help example `--tag PatientName
/// --tag StudyDate` used to select nothing, because the shared presenter matched names
/// such as "Patient's Name" and tag text only). Since D148 the shared MetadataPresenter
/// matches the keyword itself, so the CLI passes its filters through unchanged.
final class InfoTagFilterTests: XCTestCase {

    private func file() -> DICOMFile {
        var ds = DataSet()
        ds.setString("DOE^JOHN", for: Tag(group: 0x0010, element: 0x0010), vr: .PN)
        ds.setString("20200101", for: Tag(group: 0x0008, element: 0x0020), vr: .DA)
        ds.setString("CT", for: Tag(group: 0x0008, element: 0x0060), vr: .CS)
        return DICOMFile(fileMetaInformation: DataSet(), dataSet: ds)
    }

    func testHelpExampleSelectsBothAttributes() throws {
        let out = try MetadataPresenter(file: file(), filterTags: ["PatientName", "StudyDate"])
            .render(format: .csv)
        XCTAssertEqual(out, """
            Tag,Name,VR,Value
            "(0008,0020)","Study Date","DA","20200101"
            "(0010,0010)","Patient's Name","PN","DOE^JOHN"

            """)
    }

    func testKeywordsAreExact() throws {
        let out = try MetadataPresenter(file: file(), filterTags: ["patientname"]).render(format: .csv)
        XCTAssertEqual(out, "Tag,Name,VR,Value\n", "PS3.6 keywords are matched exactly")
    }
}
