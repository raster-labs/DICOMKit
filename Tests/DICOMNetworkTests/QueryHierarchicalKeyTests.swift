import XCTest
import DICOMCore
@testable import DICOMNetwork

/// PS3.4 C.4.1.2.1 — a baseline hierarchical C-FIND identifier must carry a single
/// value in the Unique Key of every level above the query level. DICOMKit checks
/// this before opening the association (DICOM_TAG_AUDIT_PHASE2_FINDINGS.md P15).
final class QueryHierarchicalKeyTests: XCTestCase {

    private func missing(_ keys: QueryKeys, model: QueryRetrieveInformationModel = .studyRoot) -> String? {
        DICOMQueryService.missingHigherLevelUniqueKey(level: keys.level, queryKeys: keys, informationModel: model)
    }

    func test_studyLevelUnderStudyRootNeedsNothing() {
        XCTAssertNil(missing(QueryKeys.defaultStudyKeys()))
    }

    func test_seriesLevelRequiresStudyUID() {
        XCTAssertNotNil(missing(QueryKeys.defaultSeriesKeys()))
        XCTAssertNil(missing(QueryKeys.defaultSeriesKeys().studyInstanceUID("1.2.3")))
    }

    func test_seriesLevelRejectsWildcardOrEmptyStudyUID() {
        XCTAssertNotNil(missing(QueryKeys.defaultSeriesKeys().studyInstanceUID("")))
        XCTAssertNotNil(missing(QueryKeys.defaultSeriesKeys().studyInstanceUID("*")))
        XCTAssertNotNil(missing(QueryKeys.defaultSeriesKeys().studyInstanceUID("1.2\\1.3")), "UID list is not a single value")
    }

    func test_imageLevelRequiresStudyAndSeriesUID() {
        XCTAssertNotNil(missing(QueryKeys.defaultInstanceKeys().studyInstanceUID("1.2.3")))
        XCTAssertNil(missing(QueryKeys.defaultInstanceKeys().studyInstanceUID("1.2.3").seriesInstanceUID("1.2.3.4")))
    }

    func test_patientRootStudyLevelRequiresPatientID() {
        XCTAssertNotNil(missing(QueryKeys.defaultStudyKeys(), model: .patientRoot))
        XCTAssertNil(missing(QueryKeys.defaultStudyKeys().patientID("P1"), model: .patientRoot))
    }

    func test_messageNamesTheKeyAndTheSection() throws {
        let message = try XCTUnwrap(missing(QueryKeys.defaultSeriesKeys()))
        XCTAssertTrue(message.contains("Study Instance UID (0020,000D)"))
        XCTAssertTrue(message.contains("C.4.1.2.1"))
    }
}

// MARK: - Hierarchical identifier content (PS3.4 C.4.1.2.1, C.4.1.3.2.1)

final class QueryParentLevelKeyTests: XCTestCase {

    private let parentTags: [Tag] = [.patientName, .patientID, .studyDate, .studyDescription, .accessionNumber]

    func test_seriesLevelOmitsParentLevelKeysByDefault() {
        let keys = DICOMQueryService.buildQueryKeys(level: .series, studyUID: "1.2.3")
        for tag in parentTags {
            XCTAssertFalse(keys.keys.contains { $0.tag == tag }, "\(tag) is a Patient/Study attribute (PS3.4 C.4.1.2.1)")
        }
        XCTAssertTrue(keys.keys.contains { $0.tag == .studyInstanceUID && $0.value == "1.2.3" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .modality })
    }

    func test_imageLevelOmitsParentLevelKeysByDefault() {
        let keys = DICOMQueryService.buildQueryKeys(level: .image, studyUID: "1.2.3", seriesUID: "1.2.3.4")
        for tag in parentTags + [.modality, .seriesNumber, .seriesDescription] {
            XCTAssertFalse(keys.keys.contains { $0.tag == tag }, "\(tag) belongs to a level above IMAGE")
        }
        XCTAssertTrue(keys.keys.contains { $0.tag == .sopInstanceUID })
    }

    func test_includeParentLevelReturnKeysReaddsThemAsReturnKeys() {
        let series = DICOMQueryService.buildQueryKeys(level: .series, patientName: "DOE*", studyUID: "1.2.3",
                                                      includeParentLevelReturnKeys: true)
        for tag in parentTags {
            let key = series.keys.first { $0.tag == tag }
            XCTAssertNotNil(key, "\(tag) requested with the non-baseline flag")
            XCTAssertEqual(key?.value, "", "parent keys are return keys only, never matching keys")
        }
        let image = DICOMQueryService.buildQueryKeys(level: .image, studyUID: "1.2.3", seriesUID: "1.2.3.4",
                                                     includeParentLevelReturnKeys: true)
        for tag in parentTags + [.modality, .seriesNumber, .seriesDescription] {
            XCTAssertTrue(image.keys.contains { $0.tag == tag && $0.value.isEmpty })
        }
    }

    func test_studyLevelStillMatchesPatientAndStudyAttributes() {
        let keys = DICOMQueryService.buildQueryKeys(level: .study, patientName: "DOE*", accession: "A1")
        XCTAssertTrue(keys.keys.contains { $0.tag == .patientName && $0.value == "DOE*" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .accessionNumber && $0.value == "A1" })
        XCTAssertTrue(DICOMQueryService.ignoredParentLevelFilters(level: .study, patientName: "DOE*").isEmpty)
    }

    func test_ignoredParentLevelFiltersNamesTheDroppedFilters() {
        let ignored = DICOMQueryService.ignoredParentLevelFilters(
            level: .series, patientName: "DOE*", studyDate: "20240101", referringPhysician: "SMITH")
        XCTAssertEqual(ignored, ["Patient Name", "Study Date", "Referring Physician"])
        XCTAssertTrue(DICOMQueryService.ignoredParentLevelFilters(level: .image).isEmpty)
    }
}
