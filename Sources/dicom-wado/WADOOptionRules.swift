import Foundation
import ArgumentParser
import DICOMWeb

// NEMA-verified: 2026a, checked 2026-10-06 — the UPS Change State target rule moved to DICOMWeb (`UPSState.changeStateTargets` / `changeStateTarget(optionValue:)`, D255; re-read against PS3.18 2026a 11.7.1.4 and PS3.4 2026a Table CC.1.1-2); the deprecated members here forward to it
// NEMA-verified: 2026a, checked 2026-10-01 — WADO-URI rules read against PS3.18 2026a 9.1.2.2.1, 9.4.1.2.1-9.4.1.2.3, 9.5.1.2.1-9.5.1.2.7 and Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1 / 8.7.4-1 (15 contentType values: application/dicom + 14 Rendered Media Types; all 19 parameters reachable, D108); limit/offset against 8.3.4.4; UPS states against PS3.3 2026a Table C.30.1-1 (4 Enumerated Values) and PS3.18 11.7.1.4 (3 Change State targets)

/// Standard-derived rules for the values `dicom-wado` options accept. Kept apart from the
/// command structs so the tests can pin each rule to its clause.
enum WADOOptionRules {

    // MARK: - WADO-URI (PS3.18 Section 9)

    /// The `--content-type` values the URI service accepts and `WADOURIClient` carries:
    /// application/dicom (Retrieve DICOM Instance, 9.4) or a Rendered Media Type of
    /// Table 8.7.4-1 (Retrieve Rendered Instance, 9.5), per 9.1.2.2.1.
    static let uriContentTypes = WADOURIClient.MediaType.allowed.map(\.rawValue)

    /// Maps `--content-type` to the request representation. An absent value is the
    /// WADO-URI default, application/dicom. A value 9.1.2.2.1 does not allow is
    /// rejected rather than silently fetched as application/dicom.
    static func uriContentType(_ raw: String?) throws -> WADOURIClient.MediaType {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return .dicom }
        guard let mapped = WADOURIClient.MediaType.fromRequestString(raw) else {
            throw ValidationError(
                "--content-type '\(raw)' cannot be requested over WADO-URI. Use one of: "
                + uriContentTypes.joined(separator: ", ")
                + " (PS3.18 9.1.2.2.1: application/dicom or a Rendered Media Type of Table 8.7.4-1)")
        }
        return mapped
    }

    /// `annotation` / `imageAnnotation` (PS3.18 9.4.1.2.2): a comma-separated list of
    /// "patient" and/or "technique" (a server may support more; those pass through).
    static func uriAnnotation(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `region` (PS3.18 9.5.1.2.5): `xmin,ymin,xmax,ymax`, four decimals.
    static func uriRegion(_ raw: String?) throws -> WADOURIClient.Region? {
        guard let raw else { return nil }
        guard let region = WADOURIClient.Region(raw) else {
            throw ValidationError("--region takes xmin,ymin,xmax,ymax, four decimal numbers (PS3.18 9.5.1.2.5); got '\(raw)'")
        }
        return region
    }

    /// `frameNumber` (PS3.18 9.5.1.2.1) names a single Frame and is a positive integer.
    /// Returns the frame to send and how many further list entries were not sent.
    static func uriFrameNumber(_ raw: String?) throws -> (frame: Int, notSent: Int)? {
        guard let raw = raw else { return nil }
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = items.first, let frame = Int(first), frame >= 1 else {
            throw ValidationError(
                "--frames with --uri takes a positive frame number (PS3.18 9.5.1.2.1: frameNumber "
                + "is a single positive integer, starting at 1); got '\(raw)'")
        }
        return (frame, items.count - 1)
    }

    /// Warnings for parameters sent with a representation whose transaction does not
    /// define them: Table 9.4.1-1 (application/dicom) has anonymize, annotation and
    /// transferSyntax; Table 9.5.1-1 (rendered) has frameNumber, rows, columns and others.
    static func uriParameterWarnings(contentType: WADOURIClient.MediaType, frame: Int?,
                                     rows: Int?, columns: Int?,
                                     transferSyntax: String?, anonymize: Bool,
                                     otherRendered: [String] = []) -> [String] {
        var out: [String] = []
        if contentType == .dicom {
            var rendered: [String] = []
            if frame != nil { rendered.append("frameNumber (--frames)") }
            if rows != nil { rendered.append("rows (--rows)") }
            if columns != nil { rendered.append("columns (--columns)") }
            rendered += otherRendered
            if !rendered.isEmpty {
                out.append("\(rendered.joined(separator: ", ")) \(rendered.count == 1 ? "is a" : "are") "
                    + "Retrieve Rendered Instance parameter\(rendered.count == 1 ? "" : "s") (PS3.18 Table 9.5.1-1), "
                    + "not defined for application/dicom (Table 9.4.1-1); the server may ignore "
                    + "\(rendered.count == 1 ? "it" : "them")")
            }
        } else {
            var dicomOnly: [String] = []
            if transferSyntax != nil { dicomOnly.append("transferSyntax (--transfer-syntax)") }
            if anonymize { dicomOnly.append("anonymize (--anonymize)") }
            if !dicomOnly.isEmpty {
                out.append("\(dicomOnly.joined(separator: ", ")) \(dicomOnly.count == 1 ? "is a" : "are") "
                    + "Retrieve DICOM Instance parameter\(dicomOnly.count == 1 ? "" : "s") (PS3.18 Table 9.4.1-1), "
                    + "not defined for \(contentType.rawValue) (Table 9.5.1-1); the server may ignore "
                    + "\(dicomOnly.count == 1 ? "it" : "them")")
            }
        }
        return out
    }

    // MARK: - QIDO-RS (PS3.18 8.3.4.4)

    /// `limit` and `offset` are uint (PS3.18 Table 8.3.4-1, 8.3.4.4).
    static func validatePaging(limit: Int, offset: Int) throws {
        if limit < 0 {
            throw ValidationError("--limit must be 0 or more (PS3.18 8.3.4.4: limit is an unsigned integer)")
        }
        if offset < 0 {
            throw ValidationError("--offset must be 0 or more (PS3.18 8.3.4.4: offset is an unsigned integer)")
        }
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

    /// The workitem whose state `ups` changes: `--change-state <uid>` (canonical, PS3.18
    /// 11.7 Change Workitem State) or the deprecated alias `--update <uid>`. Both → refused.
    static func changeStateWorkitem(changeState: String?, update: String?) throws -> String? {
        if changeState != nil && update != nil {
            throw WADORefusal("--change-state and --update are the same operation (PS3.18 2026a 11.7 "
                + "Change Workitem State); --update is a deprecated alias. Use --change-state only")
        }
        return changeState ?? update
    }

    /// Stderr note printed when the deprecated `--update` is used.
    static let updateDeprecationNote =
        "Note: --update is deprecated; use --change-state (it performs Change Workitem State, "
        + "PS3.18 2026a 11.7, not Update Workitem, 11.6)"

    // MARK: - Plumbing

    /// `--timeout` drives the per-request timeout (URLSession timeoutIntervalForRequest,
    /// i.e. `readTimeout`); the whole-resource timeout is never shorter than it.
    static func timeouts(seconds: Int) -> DICOMwebConfiguration.TimeoutConfiguration {
        let t = TimeInterval(max(1, seconds))
        let defaults = DICOMwebConfiguration.TimeoutConfiguration.default
        return DICOMwebConfiguration.TimeoutConfiguration(
            connectTimeout: t,
            readTimeout: t,
            resourceTimeout: max(defaults.resourceTimeout, t),
            operationTimeout: max(defaults.operationTimeout, t))
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
