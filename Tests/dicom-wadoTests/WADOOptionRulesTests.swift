import XCTest
import ArgumentParser
import DICOMWeb
@testable import dicom_wado

/// Pins the `dicom-wado` option values to the DICOM 2026a text:
/// PS3.18 Section 9 (WADO-URI), 8.3.4 (QIDO-RS query parameters), 11.7.1.4 (UPS Change
/// State) and PS3.3 Tables C.30.1-1 / C.30.2-1 / C.7-1.
final class WADOOptionRulesTests: XCTestCase {

    // MARK: - WADO-URI contentType (PS3.18 9.1.2.2.1, Table 8.7.4-1)

    func testURIContentTypesAreApplicationDicomOrRenderedMediaTypes() throws {
        // application/dicom plus the 14 distinct Rendered Media Types of Table 8.7.4-1 (D108).
        XCTAssertEqual(WADOOptionRules.uriContentTypes,
                       ["application/dicom", "image/jpeg", "image/gif", "image/png", "image/jp2", "image/jph", "image/jxl",
                        "video/mpeg", "video/mp4", "video/H265",
                        "text/html", "text/plain", "text/xml", "text/rtf", "application/pdf"])
        for value in WADOOptionRules.uriContentTypes {
            XCTAssertEqual(try WADOOptionRules.uriContentType(value).rawValue, value)
        }
    }

    func testAbsentContentTypeIsApplicationDicom() throws {
        XCTAssertEqual(try WADOOptionRules.uriContentType(nil), .dicom)
        XCTAssertEqual(try WADOOptionRules.uriContentType(""), .dicom)
        XCTAssertEqual(try WADOOptionRules.uriContentType("jpeg"), .jpeg)  // short alias kept
    }

    func testUnrequestableContentTypeIsRejectedNotFetchedAsDicom() {
        // image/jxl, text/html, application/pdf are Rendered Media Types (D108: now requestable);
        // a value outside Table 8.7.4-1 is still refused rather than fetched as application/dicom.
        XCTAssertEqual(try WADOOptionRules.uriContentType("image/jxl"), .jxl)
        XCTAssertEqual(try WADOOptionRules.uriContentType("text/html"), .html)
        XCTAssertEqual(try WADOOptionRules.uriContentType("application/pdf").fileExtension, "pdf")
        XCTAssertThrowsError(try WADOOptionRules.uriContentType("image/bmp"))
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1",
                                                        "--content-type", "image/bmp"]))
    }

    // MARK: - D108: the 9 further optional WADO-URI parameters (Tables 9.1.2-2, 9.4.1-1, 9.5.1-1)

    func testAllOptionalURIParametersAreReachable() throws {
        let cmd = try RetrieveCommand.parse([
            "http://h/wado", "--uri", "--study", "1", "--series", "2", "--instance", "3",
            "--content-type", "image/jpeg", "--charset", "UTF-8", "--annotation", "patient,technique",
            "--image-quality", "75", "--region", "0,0,0.5,0.5", "--rows", "128", "--columns", "128",
            "--presentation-uid", "9.8.7", "--presentation-series-uid", "9.8"])
        let p = try cmd.uriParameters(frame: nil)
        XCTAssertEqual(p.charset, ["UTF-8"])
        XCTAssertEqual(p.annotation, ["patient", "technique"])
        XCTAssertEqual(p.imageQuality, 75)
        XCTAssertEqual(p.region, WADOURIClient.Region(xmin: 0, ymin: 0, xmax: 0.5, ymax: 0.5))
        XCTAssertEqual(p.presentationUID, "9.8.7")
        XCTAssertEqual(p.presentationSeriesUID, "9.8")
        XCTAssertNoThrow(try RetrieveCommand.parse([
            "http://h/wado", "--uri", "--study", "1", "--content-type", "image/png",
            "--window-center", "40", "--window-width", "400"]))
    }

    func testSection9RulesRefuseTheCommand() {
        let base = ["http://h/wado", "--uri", "--study", "1", "--content-type", "image/jpeg"]
        for extra in [["--window-center", "40"],                                         // 9.5.1.2.6 pair
                      ["--presentation-uid", "1.2"],                                      // 9.5.1.2.7 pair
                      ["--window-center", "1", "--window-width", "2",
                       "--presentation-uid", "1", "--presentation-series-uid", "2"],     // 9.5.1.2.6 exclusion
                      ["--image-quality", "0"], ["--image-quality", "101"],               // 8.3.5.1.2
                      ["--region", "0.5,0,0.4,1"], ["--region", "a,b,c,d"],               // 9.5.1.2.5
                      ["--rows", "64"]] {                                                 // 9.5.1.2.4 pair
            XCTAssertThrowsError(try RetrieveCommand.parse(base + extra), extra.joined(separator: " "))
        }
        // windowing with application/dicom (9.5.1.2.6)
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1",
                                                        "--window-center", "40", "--window-width", "400"]))
        // WADO-URI-only options without --uri
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/rs", "--study", "1", "--charset", "UTF-8"]))
    }

    // MARK: - WADO-URI frameNumber / rows / columns (9.5.1.2.1, 9.5.1.2.4)

    func testFrameNumberIsASinglePositiveInteger() throws {
        XCTAssertNil(try WADOOptionRules.uriFrameNumber(nil))
        XCTAssertEqual(try WADOOptionRules.uriFrameNumber("3")?.frame, 3)
        XCTAssertEqual(try WADOOptionRules.uriFrameNumber("3")?.notSent, 0)
        let list = try WADOOptionRules.uriFrameNumber("2, 4,6")
        XCTAssertEqual(list?.frame, 2)
        XCTAssertEqual(list?.notSent, 2)
        XCTAssertThrowsError(try WADOOptionRules.uriFrameNumber("0"))   // starts at 1, not 0
        XCTAssertThrowsError(try WADOOptionRules.uriFrameNumber("-1"))
        XCTAssertThrowsError(try WADOOptionRules.uriFrameNumber("abc"))
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1", "--frames", "0"]))
    }

    func testRowsAndColumnsArePositiveAndNeedURI() throws {
        XCTAssertNoThrow(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1",
                                                    "--content-type", "image/jpeg", "--rows", "256", "--columns", "256"]))
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1", "--rows", "0"]))
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/wado", "--uri", "--study", "1", "--columns", "0"]))
        // WADO-URI query parameters (PS3.18 Section 9) without --uri
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/rs", "--study", "1", "--anonymize"]))
        XCTAssertThrowsError(try RetrieveCommand.parse(["http://h/rs", "--study", "1", "--transfer-syntax", "1.2.840.10008.1.2.1"]))
    }

    func testParametersOutsideTheirTransactionWarn() {
        // Table 9.4.1-1 (application/dicom): anonymize, annotation, transferSyntax.
        // Table 9.5.1-1 (rendered): frameNumber, rows, columns, ...
        XCTAssertEqual(WADOOptionRules.uriParameterWarnings(contentType: .dicom, frame: 2, rows: nil, columns: nil,
                                                            transferSyntax: "1.2.840.10008.1.2.1", anonymize: true).count, 1)
        XCTAssertTrue(WADOOptionRules.uriParameterWarnings(contentType: .dicom, frame: nil, rows: nil, columns: nil,
                                                           transferSyntax: "1.2.840.10008.1.2.1", anonymize: true).isEmpty)
        XCTAssertTrue(WADOOptionRules.uriParameterWarnings(contentType: .jpeg, frame: 2, rows: 64, columns: 64,
                                                           transferSyntax: nil, anonymize: false).isEmpty)
        let w = WADOOptionRules.uriParameterWarnings(contentType: .jpeg, frame: nil, rows: nil, columns: nil,
                                                     transferSyntax: nil, anonymize: true)
        XCTAssertEqual(w.count, 1)
        XCTAssertTrue(w[0].contains("Table 9.4.1-1"))
    }

    // MARK: - QIDO-RS (PS3.18 8.3.4)

    func testLimitAndOffsetAreUnsigned() {
        XCTAssertNoThrow(try QueryCommand.parse(["http://h/rs", "--limit", "0", "--offset", "0"]))
        XCTAssertThrowsError(try QueryCommand.parse(["http://h/rs", "--limit=-1"]))
        XCTAssertThrowsError(try QueryCommand.parse(["http://h/rs", "--offset=-5"]))
    }

    func testFuzzyMatchingSendsTheStandardParameter() throws {
        let on = try QueryCommand.parse(["http://h/rs", "--fuzzy-matching", "--patient-name", "DOE*"]).buildQuery()
        XCTAssertEqual(on.toParameters()["fuzzymatching"], "true")
        let off = try QueryCommand.parse(["http://h/rs"]).buildQuery()
        XCTAssertNil(off.toParameters()["fuzzymatching"])
        XCTAssertEqual(off.toParameters()["limit"], "100")
        XCTAssertEqual(off.toParameters()["offset"], "0")
    }

    func testModalityKeyFollowsTheQueryLevel() throws {
        // Table 10.6.1-5: Modalities In Study (0008,0061) at study level, Modality (0008,0060) at series level.
        let study = try QueryCommand.parse(["http://h/rs", "--modality", "CT"]).buildQuery().toParameters()
        XCTAssertEqual(study["00080061"], "CT")
        XCTAssertNil(study["00080060"])
        let series = try QueryCommand.parse(["http://h/rs", "--level", "series", "--modality", "CT"]).buildQuery().toParameters()
        XCTAssertEqual(series["00080060"], "CT")
    }

    // MARK: - UPS-RS (PS3.3 Table C.30.1-1, PS3.18 11.7.1.4)

    func testProcedureStepStateAcceptsTheStandardSpelling() {
        XCTAssertEqual(WADOOptionRules.upsState("IN PROGRESS"), .inProgress)
        XCTAssertEqual(WADOOptionRules.upsState("in progress"), .inProgress)
        XCTAssertEqual(WADOOptionRules.upsState("IN_PROGRESS"), .inProgress)
        XCTAssertEqual(WADOOptionRules.upsState("INPROGRESS"), .inProgress)
        XCTAssertEqual(WADOOptionRules.upsState("SCHEDULED"), .scheduled)
        XCTAssertEqual(WADOOptionRules.upsState("COMPLETED"), .completed)
        XCTAssertEqual(WADOOptionRules.upsState("CANCELED"), .canceled)
        XCTAssertNil(WADOOptionRules.upsState("CANCELLED"))
        XCTAssertEqual(UPSState.inProgress.rawValue, "IN PROGRESS")  // the value sent
        XCTAssertNoThrow(try UPSCommand.parse(["http://h/rs", "--update", "1.2.3", "--state", "IN PROGRESS"]))
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--update", "1.2.3", "--state", "DONE"]))
    }

    func testChangeStateTargetsAreTheThreeOf11_7_1_4() {
        XCTAssertEqual(WADOOptionRules.changeStateTargets.map(\.rawValue), ["IN PROGRESS", "COMPLETED", "CANCELED"])
        XCTAssertFalse(WADOOptionRules.changeStateTargets.contains(.scheduled))
        XCTAssertEqual(WADOOptionRules.changeStateTargets, UPSState.changeStateTargets)   // D255: one source
    }

    // MARK: - D255: the CLI prints the engine's refusal; the deprecated local copy cannot drift

    func testChangeStateRefusalIsTheEngineText() {
        // UPSCommand.validate calls UPSState.changeStateTarget(optionValue:) through cliRefusal.
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--change-state", "1.2.3", "--state", "SCHEDULED"])) { error in
            XCTAssertEqual(UPSCommand.exitCode(for: error), .failure)
            XCTAssertEqual(UPSCommand.message(for: error), UPSState.scheduled.changeStateRefusal)
        }
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--change-state", "1.2.3", "--state", "DONE"])) { error in
            XCTAssertEqual(UPSCommand.message(for: error), UPSState.unknownStateRefusal("DONE"))
        }
        // The deprecated WADOOptionRules.changeStateTarget body is kept text-identical for
        // Scripts/diff_studio_g3_web.py until the Studio pass; its two messages must equal the engine's.
        XCTAssertThrowsError(try WADOOptionRules.changeStateTarget("SCHEDULED")) {
            XCTAssertEqual(($0 as? WADORefusal)?.message, UPSState.scheduled.changeStateRefusal)
        }
        XCTAssertThrowsError(try WADOOptionRules.changeStateTarget("DONE")) {
            XCTAssertEqual(($0 as? WADORefusal)?.message, UPSState.unknownStateRefusal("DONE"))
        }
        XCTAssertEqual(WADOOptionRules.upsState("IN_PROGRESS"), UPSState(optionValue: "IN_PROGRESS"))
        // cliRefusal keeps the two exit paths: .usage -> ValidationError (64), .refused -> WADORefusal (1)
        XCTAssertThrowsError(try cliRefusal { throw DICOMwebOptionRefusal(.usage, "u") }) { XCTAssertTrue($0 is ValidationError) }
        XCTAssertThrowsError(try cliRefusal { throw DICOMwebOptionRefusal(.refused, "r") }) { XCTAssertEqual($0 as? WADORefusal, WADORefusal("r")) }
    }

    // MARK: - P-WADO-UPS-STATE: SCHEDULED refused (PS3.18 2026a 11.7.1.4; PS3.4 Table CC.1.1-2 C303H)

    func testChangeToScheduledIsRefusedWithExit1() {
        XCTAssertThrowsError(try WADOOptionRules.changeStateTarget("SCHEDULED")) { error in
            XCTAssertTrue(error is WADORefusal)                      // exit 1, not the 64 of a usage error
            XCTAssertTrue("\(error)".contains("PS3.18 2026a 11.7.1.4"))
            XCTAssertTrue("\(error)".contains("Table CC.1.1-2"))
        }
        XCTAssertThrowsError(try WADOOptionRules.changeStateTarget("DONE")) { XCTAssertTrue($0 is WADORefusal) }
        XCTAssertEqual(try WADOOptionRules.changeStateTarget("IN PROGRESS"), .inProgress)
        XCTAssertEqual(try WADOOptionRules.changeStateTarget("completed"), .completed)
        XCTAssertEqual(try WADOOptionRules.changeStateTarget("CANCELED"), .canceled)
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--change-state", "1.2.3", "--state", "SCHEDULED"]))
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--update", "1.2.3", "--state", "SCHEDULED"]))
        // ArgumentParser maps a non-ValidationError thrown from validate() to exit 1.
        do {
            _ = try UPSCommand.parse(["http://h/rs", "--change-state", "1.2.3", "--state", "SCHEDULED"])
            XCTFail("SCHEDULED accepted")
        } catch {
            XCTAssertEqual(UPSCommand.exitCode(for: error), .failure)
        }
    }

    // MARK: - P-WADO-UPS-UPDATE: --change-state canonical, --update deprecated alias (PS3.18 11.7)

    func testChangeStateIsCanonicalAndUpdateIsADeprecatedAlias() throws {
        let canonical = try UPSCommand.parse(["http://h/rs", "--change-state", "1.2.3", "--state", "IN PROGRESS"])
        XCTAssertEqual(canonical.changeState, "1.2.3")
        XCTAssertEqual(try WADOOptionRules.changeStateWorkitem(changeState: canonical.changeState,
                                                               update: canonical.update), "1.2.3")
        let alias = try UPSCommand.parse(["http://h/rs", "--update", "1.2.3", "--state", "IN PROGRESS"])
        XCTAssertEqual(try WADOOptionRules.changeStateWorkitem(changeState: alias.changeState, update: alias.update), "1.2.3")
        XCTAssertThrowsError(try UPSCommand.parse(["http://h/rs", "--change-state", "1", "--update", "1",
                                                   "--state", "COMPLETED"])) { error in
            XCTAssertEqual(UPSCommand.exitCode(for: error), .failure)
        }
        XCTAssertTrue(WADOOptionRules.updateDeprecationNote.contains("deprecated"))
        let help = UPSCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("--change-state <change-state>"))
        XCTAssertTrue(help.contains("Deprecated alias of --change-state"))
    }

    // MARK: - P-QUERY-JSON for dicom-wado: --format dicom-json (PS3.18 2026a F.2)

    func testDICOMJSONFormatIsAcceptedByQueryAndUPS() throws {
        XCTAssertEqual(try QueryCommand.parse(["http://h/rs", "--format", "dicom-json"]).format, .dicomJSON)
        XCTAssertEqual(try UPSCommand.parse(["http://h/rs", "--search", "--format", "dicom-json"]).format, .dicomJSON)
        XCTAssertEqual(OutputFormat.dicomJSON.asQIDO, .dicomJSON)
        XCTAssertEqual(try QueryCommand.parse(["http://h/rs", "--format", "json"]).format, .json)  // unchanged
    }

    func testDICOMJSONModelIsTheRawResultSortedWithoutGroupLength() throws {
        let study = QIDOStudyResult(attributes: [
            "0020000D": ["vr": "UI", "Value": ["1.2.3"]],
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "DOE^JANE"]]],
            "00080000": ["vr": "UL", "Value": [12]],              // Group Length: excluded (F.2.2)
            "00081110": ["vr": "SQ", "Value": [["00080000": ["vr": "UL", "Value": [4]],
                                                  "00081150": ["vr": "UI", "Value": ["1.2.840.10008.3.1.2.3.1"]]]]],
        ])
        let text = QIDOResultFormatter().formatStudies([study], format: .dicomJSON)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(parsed.count, 1)                                         // F.2.1 top-level array
        XCTAssertEqual(Set(parsed[0].keys), ["0020000D", "00100010", "00081110"])
        let pn = (parsed[0]["00100010"] as? [String: Any])?["Value"] as? [[String: String]]
        XCTAssertEqual(pn?.first?["Alphabetic"], "DOE^JANE")                    // PN component object
        let item = ((parsed[0]["00081110"] as? [String: Any])?["Value"] as? [[String: Any]])?.first
        XCTAssertEqual(item.map { Set($0.keys) }, ["00081150"])
        // F.2.2: ascending lexicographic order of the tag names
        let order = ["\"00081110\"", "\"00100010\"", "\"0020000D\""].compactMap { text.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order, order.sorted())
        XCTAssertEqual(DICOMJSONModelFormatter.format([]), "[]")
    }

    func testFilterStateInProgressReachesTheSharedSearchBuilder() throws {
        // D107: the shared builder takes the PS3.3 Table C.30.1-1 term itself.
        let params = try UPSQuery.workitemSearch(filterState: "IN PROGRESS", scheduledStation: nil).toParameters()
        XCTAssertEqual(params, ["00741000": "IN PROGRESS"])
    }

    func testUPSHelpNamesTheStandardTerms() {
        let help = UPSCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("HIGH, MEDIUM, LOW (PS3.3 Table C.30.2-1"))
        XCTAssertTrue(help.contains("IN PROGRESS, COMPLETED, CANCELED (PS3.18 11.7.1.4)"))
        XCTAssertTrue(help.contains("M, F, O (PS3.3 Table C.7-1)"))
        XCTAssertTrue(help.contains("table, json, csv, dicom-json"))
    }

    // MARK: - Store exit status, --timeout

    func testStoreFailsWhenAnyInstanceWasNotStored() {
        XCTAssertNil(StoreCommand.exitCode(failed: 0))
        XCTAssertEqual(StoreCommand.exitCode(failed: 1), .failure)
    }

    func testTimeoutDrivesTheRequestTimeout() {
        let t = WADOOptionRules.timeouts(seconds: 600)
        XCTAssertEqual(t.readTimeout, 600)
        XCTAssertGreaterThanOrEqual(t.resourceTimeout, 600)
        XCTAssertEqual(WADOOptionRules.timeouts(seconds: 60).readTimeout, 60)
    }
}
