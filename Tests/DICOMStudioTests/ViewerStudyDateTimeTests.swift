// ViewerStudyDateTimeTests.swift
// DICOMStudioTests
//
// The study date-and-time line in the viewer's series pane.
//
// A patient is often scanned more than once on one day; the bare date the
// pane used to show could not tell those studies apart. The time is added
// when the file records one, and left off when it does not.

#if canImport(SwiftUI)
import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import Foundation

@MainActor
@Suite("Viewer Study Date and Time Tests")
struct ViewerStudyDateTimeTests {

    private func viewModel(_ values: [(UInt16, UInt16, String)]) -> ImageViewerViewModel {
        let elements = values.map { group, element, value -> DataElement in
            let padded = value.count % 2 == 0 ? value : value + " "
            let data = Data(padded.utf8)
            return DataElement(tag: Tag(group: group, element: element),
                               vr: .LO, length: UInt32(data.count), valueData: data)
        }
        let model = ImageViewerViewModel()
        model.dicomFile = DICOMFile(fileMetaInformation: DataSet(),
                                    dataSet: DataSet(elements: elements))
        return model
    }

    @Test("Study Date and Study Time are shown together")
    func testDateAndTime() {
        let model = viewModel([(0x0008, 0x0020, "20260530"),
                               (0x0008, 0x0030, "185008.123")])
        #expect(model.studyDateForOverlay == "2026-05-30")
        #expect(model.studyTimeForOverlay == "18:50:08")
        #expect(model.studyDateTimeForOverlay == "2026-05-30 18:50:08")
    }

    @Test("A time without seconds is shown as hours and minutes")
    func testShortTime() {
        let model = viewModel([(0x0008, 0x0020, "20260530"),
                               (0x0008, 0x0030, "1850")])
        #expect(model.studyDateTimeForOverlay == "2026-05-30 18:50")
    }

    @Test("A file with no Study Time shows the date alone")
    func testDateOnly() {
        let model = viewModel([(0x0008, 0x0020, "20260530")])
        #expect(model.studyTimeForOverlay == nil)
        #expect(model.studyDateTimeForOverlay == "2026-05-30")
    }

    @Test("A blank Study Time counts as missing")
    func testBlankTime() {
        let model = viewModel([(0x0008, 0x0020, "20260530"),
                               (0x0008, 0x0030, "  ")])
        #expect(model.studyDateTimeForOverlay == "2026-05-30")
    }

    @Test("With neither tag there is no line at all")
    func testNeither() {
        let model = viewModel([(0x0010, 0x0020, "711794")])
        #expect(model.studyDateTimeForOverlay == nil)
    }
}
#endif
