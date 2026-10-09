// NEMA-verified: 2026a, checked 2026-10-01 — pins the deferred DICOMWeb console / client rows to the 2026a text: PS3.18 Tables I.1-1 / I.2-1 / I.2-2 (D106), PS3.18 Section 9 Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1 / 8.7.4-1 (D108), F.2 (D213), PS3.4 Table CC.2.5-3 N-GET (Retrieve Workitem UID)

import XCTest
@testable import DICOMWeb
import DICOMKit
import DICOMCore

final class WebClientDeferredRowsTests: XCTestCase {

    // MARK: - D106: STOW Failure Reason / Warning Reason (PS3.18 Tables I.2-1, I.2-2)

    func test_D106_failureReasonPrintsHexDecimalAndTableI22Meaning() {
        let f = STOWResultFormatter()
        // The 6 rows of PS3.18 2026a Table I.2-2 (ranges by a member value)
        XCTAssertEqual(f.failureReason(description: nil, code: 0xA701), "A701 (42753): Refused out of Resources")
        XCTAssertEqual(f.failureReason(description: nil, code: 0xA900), "A900 (43264): Error: Data Set does not match SOP Class")
        XCTAssertEqual(f.failureReason(description: nil, code: 0xCFFF), "CFFF (53247): Error: Cannot understand")
        XCTAssertEqual(f.failureReason(description: nil, code: 0xC122), "C122 (49442): Referenced Transfer Syntax not supported")
        XCTAssertEqual(f.failureReason(description: nil, code: 0x0110), "0110 (272): Processing failure")
        XCTAssertEqual(f.failureReason(description: nil, code: 0x0122), "0122 (290): Referenced SOP Class not supported")
        XCTAssertEqual(f.failureReason(description: nil, code: 0x1234), "1234 (4660): not defined in PS3.18 Table I.2-2")
        XCTAssertEqual(f.failureReason(description: "disk full", code: 0xA700),
                       "A700 (42752): Refused out of Resources [disk full]")
        XCTAssertEqual(f.failureReason(description: "x", code: nil), "x")
        XCTAssertEqual(f.failureReason(description: nil, code: nil), "unknown error")
    }

    func test_D106_warningReasonIsReadFromReferencedSOPSequenceAndPrinted() throws {
        let json: [String: Any] = [
            "00081199": ["vr": "SQ", "Value": [
                ["00081150": ["vr": "UI", "Value": ["1.2.840.10008.5.1.4.1.1.2"]],
                 "00081155": ["vr": "UI", "Value": ["1.2.3.4"]],
                 "00081196": ["vr": "US", "Value": [45056]]],
                ["00081155": ["vr": "UI", "Value": ["1.2.3.5"]]],
            ]],
        ]
        let response = try STOWResponse.parse(json: json)
        XCTAssertEqual(response.storedInstances.map(\.warningReason), [0xB000, nil])
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.code, "B000")
        XCTAssertEqual(response.warnings.first?.message, "1.2.3.4: B000 (45056): Coercion of Data Elements")
        XCTAssertEqual(STOWResultFormatter().warningDetail(sopInstanceUID: "1.2.3.4", code: 0xB000),
                       "    Warning: 1.2.3.4 - B000 (45056): Coercion of Data Elements")
        // The 3 rows of PS3.18 2026a Table I.2-1
        XCTAssertEqual(STOWResponse.standardMeaning(forWarningReason: 0xB006), "Elements Discarded")
        XCTAssertEqual(STOWResponse.standardMeaning(forWarningReason: 0xB007), "Data Set does not match SOP Class")
        XCTAssertNil(STOWResponse.standardMeaning(forWarningReason: 0xB001))
    }

    // MARK: - D108: WADO-URI parameters and Rendered Media Types (PS3.18 Section 9)

    private func uriClient() throws -> WADOURIClient {
        WADOURIClient(configuration: try DICOMwebConfiguration(baseURLString: "http://pacs.local/wado"))
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func test_D108_renderedMediaTypesAreTable874_1() {
        // PS3.18 2026a Table 8.7.4-1, distinct media types (gif and jxl are listed twice)
        XCTAssertEqual(WADOURIClient.MediaType.renderedMediaTypes.map(\.rawValue),
                       ["image/jpeg", "image/gif", "image/png", "image/jp2", "image/jph", "image/jxl",
                        "video/mpeg", "video/mp4", "video/H265",
                        "text/html", "text/plain", "text/xml", "text/rtf", "application/pdf"])
        XCTAssertEqual(WADOURIClient.MediaType.fromRequestString("VIDEO/h265"), .h265)
        XCTAssertEqual(WADOURIClient.MediaType.fromRequestString("image/jphc"), .jph)
        XCTAssertNil(WADOURIClient.MediaType.fromRequestString("image/bmp"))
        XCTAssertEqual(WADOURIClient.MediaType(.htj2k), .jph)
    }

    func test_D108_everyOptionalParameterIsSentUnderItsTableName() throws {
        var p = WADOURIClient.Parameters(contentType: [.jpeg])
        p.charset = ["UTF-8"]
        p.annotation = ["patient", "technique"]
        p.frameNumber = 2
        p.imageQuality = 80
        p.rows = 256
        p.columns = 512
        p.region = WADOURIClient.Region(xmin: 0.25, ymin: 0, xmax: 0.75, ymax: 1)
        p.windowCenter = 40
        p.windowWidth = 400.5
        XCTAssertEqual(p.problems(), [])
        let q = query(try uriClient().requestURL(studyUID: "1", seriesUID: "2", objectUID: "3", parameters: p))
        XCTAssertEqual(q, ["requestType": "WADO", "studyUID": "1", "seriesUID": "2", "objectUID": "3",
                           "contentType": "image/jpeg", "charset": "UTF-8", "imageAnnotation": "patient,technique",
                           "frameNumber": "2", "imageQuality": "80", "rows": "256", "columns": "512",
                           "region": "0.25,0,0.75,1", "windowCenter": "40", "windowWidth": "400.5"])

        // Table 9.4.1-1 names the parameter "annotation" for application/dicom
        let d = WADOURIClient.Parameters(anonymize: true, annotation: ["patient"], transferSyntax: "1.2.840.10008.1.2.1")
        let qd = query(try uriClient().requestURL(studyUID: "1", seriesUID: "2", objectUID: "3", parameters: d))
        XCTAssertEqual(qd["annotation"], "patient")
        XCTAssertEqual(qd["anonymize"], "yes")
        XCTAssertEqual(qd["transferSyntax"], "1.2.840.10008.1.2.1")
        XCTAssertNil(qd["imageAnnotation"])

        let ps = WADOURIClient.Parameters(contentType: [.png], presentationSeriesUID: "9.8", presentationUID: "9.8.7")
        let qp = query(try uriClient().requestURL(studyUID: "1", seriesUID: "2", objectUID: "3", parameters: ps))
        XCTAssertEqual(qp["presentationSeriesUID"], "9.8")
        XCTAssertEqual(qp["presentationUID"], "9.8.7")
    }

    func test_D108_section9RulesAreChecked() async throws {
        func problems(_ p: WADOURIClient.Parameters) -> String { p.problems().joined(separator: " | ") }
        XCTAssertTrue(problems(.init(contentType: [.jpeg], windowCenter: 40)).contains("9.5.1.2.6"))
        XCTAssertTrue(problems(.init(windowCenter: 40, windowWidth: 400)).contains("application/dicom"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], windowCenter: 1, windowWidth: 2,
                                     presentationSeriesUID: "1", presentationUID: "2")).contains("same request"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], presentationUID: "2")).contains("9.5.1.2.7"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], rows: 64)).contains("9.5.1.2.4"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], imageQuality: 0)).contains("8.3.5.1.2"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], imageQuality: 101)).contains("1 and 100"))
        XCTAssertTrue(problems(.init(contentType: [.jpeg], region: .init(xmin: 0.5, ymin: 0, xmax: 0.5, ymax: 1)))
            .contains("9.5.1.2.5"))
        XCTAssertTrue(problems(.init(contentType: [.dicom, .jpeg])).contains("9.1.2.2.1"))
        XCTAssertTrue(problems(.init(contentType: [.init(rawValue: "image/bmp")])).contains("Table 8.7.4-1"))
        XCTAssertTrue(problems(.init(frameNumber: 0)).contains("9.5.1.2.1"))
        XCTAssertNil(WADOURIClient.Region("1,2,3"))
        XCTAssertEqual(WADOURIClient.Region("0, 0.1 ,0.5,1"), .init(xmin: 0, ymin: 0.1, xmax: 0.5, ymax: 1))

        // The request is refused before anything is sent
        do {
            _ = try await uriClient().retrieve(studyUID: "1", seriesUID: "2", objectUID: "3",
                                               parameters: .init(contentType: [.jpeg], windowWidth: 400))
            XCTFail("expected WADOURIParameterError")
        } catch let error as WADOURIParameterError {
            XCTAssertEqual(error.problems.count, 1)
        }
    }

    // MARK: - D213: WorkitemResult keeps the DICOM JSON object (PS3.18 F.2)

    func test_D213_workitemResultRendersDICOMJSON() throws {
        let json: [String: Any] = [
            "00080018": ["vr": "UI", "Value": ["1.2.3"]],
            "00741000": ["vr": "CS", "Value": ["SCHEDULED"]],
            "00741204": ["vr": "LO", "Value": ["CT HEAD"]],
        ]
        let result = try XCTUnwrap(WorkitemResult.parse(json: json))
        XCTAssertEqual(result.attributes?.keys.sorted(), ["00080018", "00741000", "00741204"])
        let out = UPSResultFormatter().format([result], format: .dicomJSON)
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        XCTAssertEqual(((parsed.first?["00741204"] as? [String: Any])?["Value"] as? [String]), ["CT HEAD"])
        XCTAssertEqual(UPSOutputFormat(rawValue: "dicom-json"), .dicomJSON)
        // A result built in code has no DICOM JSON object to render
        XCTAssertEqual(UPSResultFormatter().format([WorkitemResult(workitemUID: "1")], format: .dicomJSON), "[]")
    }

    func test_retrieveWorkitemResponseWithoutSOPInstanceUIDUsesTheRequestedUID() {
        // PS3.4 2026a Table CC.2.5-3, N-GET column: SOP Instance UID (0008,0018) "Not allowed"
        let json: [String: Any] = ["00741000": ["vr": "CS", "Value": ["IN PROGRESS"]]]
        XCTAssertNil(WorkitemResult.parse(json: json))
        let result = WorkitemResult.parse(json: json, requestedUID: "1.2.9")
        XCTAssertEqual(result?.workitemUID, "1.2.9")
        XCTAssertEqual(result?.state, .inProgress)
    }
}
