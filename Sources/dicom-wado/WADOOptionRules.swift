import Foundation
import ArgumentParser
import DICOMWeb

// NEMA-verified: 2026a, checked 2026-10-06 — the WADO-URI, QIDO paging, --update alias and timeout rules moved to DICOMWeb (`DICOMwebOptionRules`, D265; re-read against PS3.18 2026a 9.1.2.2.1, 9.5.1.2.1, 9.5.1.2.5, 8.3.4.4, 11.7 and Tables 9.4.1-1 / 9.5.1-1 / 8.7.4-1) — this file only forwards
// NEMA-verified: 2026a, checked 2026-10-06 — the UPS Change State target rule moved to DICOMWeb (`UPSState.changeStateTargets` / `changeStateTarget(optionValue:)`, D255; re-read against PS3.18 2026a 11.7.1.4 and PS3.4 2026a Table CC.1.1-2); the deprecated members here forward to it
// NEMA-verified: 2026a, checked 2026-10-01 — WADO-URI rules read against PS3.18 2026a 9.1.2.2.1, 9.4.1.2.1-9.4.1.2.3, 9.5.1.2.1-9.5.1.2.7 and Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1 / 8.7.4-1 (15 contentType values: application/dicom + 14 Rendered Media Types; all 19 parameters reachable, D108); limit/offset against 8.3.4.4; UPS states against PS3.3 2026a Table C.30.1-1 (4 Enumerated Values) and PS3.18 11.7.1.4 (3 Change State targets)

/// Standard-derived rules for the values `dicom-wado` options accept. Kept apart from the
/// command structs so the tests can pin each rule to its clause.
enum WADOOptionRules {

    // MARK: - WADO-URI (PS3.18 Section 9)
    //
    // D265: these rules live in DICOMWeb (`DICOMwebOptionRules`) and dicom-wado calls them through
    // `cliRefusal`, so its text and exit codes are unchanged. The members below only forward.

    /// The `--content-type` values the URI service accepts: `DICOMwebOptionRules.uriContentTypes`.
    @available(*, deprecated, message: "use DICOMwebOptionRules.uriContentTypes from DICOMWeb")
    static let uriContentTypes = DICOMwebOptionRules.uriContentTypes

    @available(*, deprecated, message: "use DICOMwebOptionRules.uriContentType(_:) from DICOMWeb")
    static func uriContentType(_ raw: String?) throws -> WADOURIClient.MediaType {
        try cliRefusal { try DICOMwebOptionRules.uriContentType(raw) }
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.uriAnnotation(_:) from DICOMWeb")
    static func uriAnnotation(_ raw: String?) -> [String] {
        DICOMwebOptionRules.uriAnnotation(raw)
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.uriRegion(_:) from DICOMWeb")
    static func uriRegion(_ raw: String?) throws -> WADOURIClient.Region? {
        try cliRefusal { try DICOMwebOptionRules.uriRegion(raw) }
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.uriFrameNumber(_:) from DICOMWeb")
    static func uriFrameNumber(_ raw: String?) throws -> (frame: Int, notSent: Int)? {
        try cliRefusal { try DICOMwebOptionRules.uriFrameNumber(raw) }
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.uriParameterWarnings from DICOMWeb")
    static func uriParameterWarnings(contentType: WADOURIClient.MediaType, frame: Int?,
                                     rows: Int?, columns: Int?,
                                     transferSyntax: String?, anonymize: Bool,
                                     otherRendered: [String] = []) -> [String] {
        DICOMwebOptionRules.uriParameterWarnings(contentType: contentType, frame: frame, rows: rows, columns: columns,
                                                 transferSyntax: transferSyntax, anonymize: anonymize,
                                                 otherRendered: otherRendered)
    }

    // MARK: - QIDO-RS (PS3.18 8.3.4.4)

    @available(*, deprecated, message: "use DICOMwebOptionRules.validatePaging(limit:offset:) from DICOMWeb")
    static func validatePaging(limit: Int, offset: Int) throws {
        try cliRefusal { try DICOMwebOptionRules.validatePaging(limit: limit, offset: offset) }
    }

    // MARK: - UPS-RS

    /// Procedure Step State (0074,1000), PS3.3 Table C.30.1-1 Enumerated Values. The
    /// standard spelling "IN PROGRESS" and the CLI spellings IN_PROGRESS / INPROGRESS
    /// are accepted (case-insensitive). Forwards to `UPSState.init(optionValue:)` (D255).
    @available(*, deprecated, message: "use UPSState(optionValue:) from DICOMWeb")
    static func upsState(_ raw: String) -> UPSState? {
        UPSState(optionValue: raw)
    }

    /// The Procedure Step State values a Change State request may carry
    /// (PS3.18 11.7.1.4: "IN PROGRESS", "COMPLETED", or "CANCELED"): `UPSState.changeStateTargets`.
    @available(*, deprecated, message: "use UPSState.changeStateTargets from DICOMWeb")
    static let changeStateTargets: [UPSState] = UPSState.changeStateTargets

    /// The Procedure Step State a Change Workitem State request (`--change-state`, or the
    /// deprecated `--update`) sends. PS3.18 2026a 11.7.1.4 allows only "IN PROGRESS",
    /// "COMPLETED" or "CANCELED"; PS3.4 2026a Table CC.1.1-2 answers a change to SCHEDULED
    /// with C303H (or C307H). SCHEDULED and unknown values are refused (exit 1).
    ///
    /// The rule now lives in DICOMWeb (`UPSState.changeStateTarget(optionValue:)`, D255) and
    /// `dicom-wado` calls that. This body is kept text-identical only because
    /// `Scripts/diff_studio_g3_web.py` and DICOM Studio's `WorkshopWADOOptionRules` copy anchor
    /// on it until the Studio pass rewires them; `WADOOptionRulesTests` pins its two messages
    /// to the engine's so they cannot drift.
    @available(*, deprecated, message: "use UPSState.changeStateTarget(optionValue:) from DICOMWeb")
    static func changeStateTarget(_ raw: String) throws -> UPSState {
        guard let state = upsState(raw) else {
            throw WADORefusal("Invalid state: \(raw). Valid states: IN PROGRESS (or IN_PROGRESS), COMPLETED, "
                + "CANCELED (PS3.18 2026a 11.7.1.4)")
        }
        guard changeStateTargets.contains(state) else {
            throw WADORefusal("\(state.rawValue) is not a Change Workitem State target: PS3.18 2026a 11.7.1.4 "
                + "allows IN PROGRESS, COMPLETED or CANCELED, and PS3.4 2026a Table CC.1.1-2 refuses a change "
                + "to SCHEDULED (C303H)")
        }
        return state
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.changeStateWorkitem(changeState:update:) from DICOMWeb")
    static func changeStateWorkitem(changeState: String?, update: String?) throws -> String? {
        try cliRefusal { try DICOMwebOptionRules.changeStateWorkitem(changeState: changeState, update: update) }
    }

    @available(*, deprecated, message: "use DICOMwebOptionRules.updateDeprecationNote from DICOMWeb")
    static let updateDeprecationNote = DICOMwebOptionRules.updateDeprecationNote

    // MARK: - Plumbing

    @available(*, deprecated, message: "use DICOMwebOptionRules.timeouts(seconds:) from DICOMWeb")
    static func timeouts(seconds: Int) -> DICOMwebConfiguration.TimeoutConfiguration {
        DICOMwebOptionRules.timeouts(seconds: seconds)
    }
}

/// A refusal of an option value by the standard; ArgumentParser reports it as
/// "Error: <message>" and exits 1 (not the 64 of a usage error).
struct WADORefusal: Error, LocalizedError, CustomStringConvertible, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
    var errorDescription: String? { message }
}

/// Runs a DICOMWeb option rule and reports its `DICOMwebOptionRefusal` the way this tool
/// always has: `.usage` as an ArgumentParser `ValidationError` (exit 64, with usage),
/// `.refused` as a `WADORefusal` (exit 1). Output and exit codes stay byte-identical to the
/// CLI-local rules the engine replaced (D255, D265).
func cliRefusal<T>(_ rule: () throws -> T) throws -> T {
    do {
        return try rule()
    } catch let refusal as DICOMwebOptionRefusal {
        switch refusal.kind {
        case .usage:   throw ValidationError(refusal.message)
        case .refused: throw WADORefusal(refusal.message)
        }
    }
}
