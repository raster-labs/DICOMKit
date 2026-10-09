import Foundation

// NEMA-verified: 2026a, checked 2026-10-06 — lifted from dicom-wado WADOOptionRules (D265) and re-read: contentType against PS3.18 2026a 9.1.2.2.1 (application/dicom or a Rendered Media Type) and Table 8.7.4-1 (15 rows, 14 distinct media types; the list is `WADOURIClient.MediaType.allowed`); frameNumber against 9.5.1.2.1 (a single positive integer, starting at 1); region against 9.5.1.2.5 (four decimals xmin,ymin,xmax,ymax); annotation against 9.4.1.2.2; the parameter warnings against Table 9.4.1-1 (anonymize, annotation, transferSyntax: 3/3) and Table 9.5.1-1 (contentType, charset, frameNumber, imageAnnotation, imageQuality, rows, columns, region, windowCenter, windowWidth, presentationSeriesUID, presentationUID: 12); limit / offset against 8.3.4.4 (both uint); --update as an alias of Change Workitem State against 11.7 / 11.6

// MARK: - DICOMwebOptionRules

/// Standard-derived rules for the values a DICOMweb front end (dicom-wado, DICOM Studio's CLI
/// Workshop) accepts for its options, so both print one text. Usage errors throw a
/// `DICOMwebOptionRefusal` of kind `.usage` (exit 64), refusals of kind `.refused` (exit 1).
/// The UPS Change State target rule lives on `UPSState` (`changeStateTarget(optionValue:)`, D255).
public enum DICOMwebOptionRules {

    // MARK: WADO-URI (PS3.18 2026a Section 9)

    /// The contentType values the URI service accepts and `WADOURIClient` carries:
    /// application/dicom (Retrieve DICOM Instance, 9.4) or a Rendered Media Type of
    /// Table 8.7.4-1 (Retrieve Rendered Instance, 9.5), per PS3.18 2026a 9.1.2.2.1.
    public static let uriContentTypes: [String] = WADOURIClient.MediaType.allowed.map(\.rawValue)

    /// Maps a contentType option value to the request representation. An absent or empty
    /// value is the WADO-URI default, application/dicom. A value PS3.18 2026a 9.1.2.2.1 does
    /// not allow is refused (`.usage`) rather than silently fetched as application/dicom.
    public static func uriContentType(_ raw: String?) throws -> WADOURIClient.MediaType {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return .dicom }
        guard let mapped = WADOURIClient.MediaType.fromRequestString(raw) else {
            throw DICOMwebOptionRefusal(.usage,
                "--content-type '\(raw)' cannot be requested over WADO-URI. Use one of: "
                + uriContentTypes.joined(separator: ", ")
                + " (PS3.18 9.1.2.2.1: application/dicom or a Rendered Media Type of Table 8.7.4-1)")
        }
        return mapped
    }

    /// `annotation` / `imageAnnotation` (PS3.18 2026a 9.4.1.2.2): a comma-separated list of
    /// "patient" and/or "technique" (a server may support more; those pass through).
    public static func uriAnnotation(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `region` (PS3.18 2026a 9.5.1.2.5): `xmin,ymin,xmax,ymax`, four decimals (`.usage` otherwise).
    public static func uriRegion(_ raw: String?) throws -> WADOURIClient.Region? {
        guard let raw else { return nil }
        guard let region = WADOURIClient.Region(raw) else {
            throw DICOMwebOptionRefusal(.usage,
                "--region takes xmin,ymin,xmax,ymax, four decimal numbers (PS3.18 9.5.1.2.5); got '\(raw)'")
        }
        return region
    }

    /// `frameNumber` (PS3.18 2026a 9.5.1.2.1) names a single Frame and is a positive integer.
    /// Returns the frame to send and how many further list entries were not sent.
    public static func uriFrameNumber(_ raw: String?) throws -> (frame: Int, notSent: Int)? {
        guard let raw = raw else { return nil }
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = items.first, let frame = Int(first), frame >= 1 else {
            throw DICOMwebOptionRefusal(.usage,
                "--frames with --uri takes a positive frame number (PS3.18 9.5.1.2.1: frameNumber "
                + "is a single positive integer, starting at 1); got '\(raw)'")
        }
        return (frame, items.count - 1)
    }

    /// Warnings for parameters sent with a representation whose transaction does not
    /// define them: PS3.18 2026a Table 9.4.1-1 (application/dicom) has anonymize, annotation and
    /// transferSyntax; Table 9.5.1-1 (rendered) has frameNumber, rows, columns and others.
    public static func uriParameterWarnings(contentType: WADOURIClient.MediaType, frame: Int?,
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

    // MARK: QIDO-RS (PS3.18 2026a 8.3.4.4)

    /// `limit` and `offset` are uint (PS3.18 2026a Table 8.3.4-1, 8.3.4.4): the refusal text, or nil.
    public static func pagingProblem(limit: Int, offset: Int) -> String? {
        if limit < 0 {
            return "--limit must be 0 or more (PS3.18 8.3.4.4: limit is an unsigned integer)"
        }
        if offset < 0 {
            return "--offset must be 0 or more (PS3.18 8.3.4.4: offset is an unsigned integer)"
        }
        return nil
    }

    /// Throws `pagingProblem(limit:offset:)` as a `.usage` refusal.
    public static func validatePaging(limit: Int, offset: Int) throws {
        if let problem = pagingProblem(limit: limit, offset: offset) {
            throw DICOMwebOptionRefusal(.usage, problem)
        }
    }

    // MARK: UPS-RS (PS3.18 2026a 11.6, 11.7)

    /// The workitem whose state a front end changes: `--change-state <uid>` (canonical,
    /// PS3.18 2026a 11.7 Change Workitem State) or the deprecated alias `--update <uid>`.
    /// Both given → `.refused`.
    public static func changeStateWorkitem(changeState: String?, update: String?) throws -> String? {
        if changeState != nil && update != nil {
            throw DICOMwebOptionRefusal(.refused, "--change-state and --update are the same operation (PS3.18 2026a 11.7 "
                + "Change Workitem State); --update is a deprecated alias. Use --change-state only")
        }
        return changeState ?? update
    }

    /// The note printed (stderr) when the deprecated `--update` is used.
    public static let updateDeprecationNote =
        "Note: --update is deprecated; use --change-state (it performs Change Workitem State, "
        + "PS3.18 2026a 11.7, not Update Workitem, 11.6)"

    // MARK: Plumbing

    /// A `--timeout` of `seconds` drives the per-request timeout (URLSession
    /// timeoutIntervalForRequest, i.e. `readTimeout`); the whole-resource timeout is never
    /// shorter than it. Not a DICOM rule.
    public static func timeouts(seconds: Int) -> DICOMwebConfiguration.TimeoutConfiguration {
        let t = TimeInterval(max(1, seconds))
        let defaults = DICOMwebConfiguration.TimeoutConfiguration.default
        return DICOMwebConfiguration.TimeoutConfiguration(
            connectTimeout: t,
            readTimeout: t,
            resourceTimeout: max(defaults.resourceTimeout, t),
            operationTimeout: max(defaults.operationTimeout, t))
    }
}
