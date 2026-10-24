import Foundation
import DICOMCore

/// Information-entity scope of a matching attribute, distinct from stored VR validation.
public enum QIDOAttributeLevel: Sendable {
    case patient, study, series, instance
}

/// The six Search resources of PS3.18 2026a Table 10.6.1-1.
public enum QIDOResource: String, CaseIterable, Sendable {
    case allStudies, studySeries, studyInstances, allSeries, studySeriesInstances, allInstances

    /// Attribute/Value Pair Requirements, PS3.18 10.6.1.2.1. Patient IE
    /// attributes remain permitted even where study attributes are not.
    public func allows(_ level: QIDOAttributeLevel) -> Bool {
        switch level {
        case .patient: return true
        case .study: return [.allStudies, .allSeries, .allInstances].contains(self)
        case .series: return [.studySeries, .allSeries, .studyInstances, .allInstances].contains(self)
        case .instance: return [.studyInstances, .studySeriesInstances, .allInstances].contains(self)
        }
    }

    public var pathTemplate: String {
        switch self {
        case .allStudies: return "/studies"
        case .studySeries: return "/studies/{study}/series"
        case .studyInstances: return "/studies/{study}/instances"
        case .allSeries: return "/series"
        case .studySeriesInstances: return "/studies/{study}/series/{series}/instances"
        case .allInstances: return "/instances"
        }
    }

    /// Selects the existing CLI resource form. A UID list is a query predicate,
    /// never a single path component (PS3.18 8.3.4.1 / PS3.4 C.2.2.2.2).
    public static func resolve(level: String, studyUID: String?, seriesUID: String?) throws -> Self {
        let studyScope = studyUID.map { !$0.isEmpty && !$0.contains(",") } ?? false
        let seriesScope = seriesUID.map { !$0.isEmpty && !$0.contains(",") } ?? false
        switch level {
        case "study": return .allStudies
        case "series": return studyScope ? .studySeries : .allSeries
        case "instance":
            if studyScope && seriesScope { return .studySeriesInstances }
            return studyScope ? .studyInstances : .allInstances
        default: throw DICOMwebOptionRefusal(.usage, "--level must be study, series or instance")
        }
    }

    /// Classifies canonical tag paths used by the supported matching surface.
    /// Unknown keys return nil; callers must not interpret nil as a matched key.
    public static func matchingLevel(for canonicalPath: String) -> QIDOAttributeLevel? {
        switch canonicalPath.uppercased() {
        case "00100010", "00100020", "00100030", "00100040": return .patient
        case "00080020", "00080030", "00080050", "00080061", "00080090",
             "00081030", "0020000D", "00200010": return .study
        case "00080060", "0008103E", "00180015", "0020000E", "00200011",
             "00400244", "00400245", "00400275", "00400275.00400009", "00400275.00401001": return .series
        case "00080016", "00080018", "00200013", "00280008", "00280010", "00280011": return .instance
        default: return nil
        }
    }
}

/// A resource and its effective parameters built together, before HTTP dispatch.
/// Both CLI and Workshop use this policy; matching expressions are preserved
/// verbatim instead of being fed through stored scalar DA/TM/PN validation.
public struct QIDORequest: Sendable, Equatable {
    public let resource: QIDOResource
    /// Only path-scoping UIDs; matching UID lists remain in `query`.
    public let studyUID: String?
    public let seriesUID: String?
    public let query: QIDOQuery

    public var path: String {
        resource.pathTemplate
            .replacingOccurrences(of: "{study}", with: studyUID ?? "")
            .replacingOccurrences(of: "{series}", with: seriesUID ?? "")
    }

    public init(level: String, studyUID: String? = nil, seriesUID: String? = nil,
                query: QIDOQuery = QIDOQuery(), modality: String? = nil) throws {
        let study = studyUID.flatMap { $0.isEmpty ? nil : $0 }
        let series = seriesUID.flatMap { $0.isEmpty ? nil : $0 }
        for (flag, value) in [("--study", study), ("--series", series)] {
            if let value, !value.components(separatedBy: ",").allSatisfy(DICOMValueRules.isValidUID) {
                throw DICOMwebOptionRefusal(.usage, "\(flag) requires a DICOM UID or comma-separated UID list (PS3.18 8.3.4.1)")
            }
        }
        resource = try QIDOResource.resolve(level: level, studyUID: study, seriesUID: series)
        let scopedStudy = [.studySeries, .studyInstances, .studySeriesInstances].contains(resource)
        self.studyUID = scopedStudy ? study : nil
        self.seriesUID = resource == .studySeriesInstances ? series : nil
        var parameters = query.toParameters()
        // A path UID already determines the resource. Do not duplicate it as a
        // prohibited parent-level matching key on a scoped resource.
        if let study, !scopedStudy { parameters[QIDOQueryAttribute.studyInstanceUID] = study }
        if let series, resource != .studySeriesInstances { parameters[QIDOQueryAttribute.seriesInstanceUID] = series }
        if let modality, !modality.isEmpty {
            let key = resource == .allStudies ? QIDOQueryAttribute.modalitiesInStudy : QIDOQueryAttribute.modality
            parameters[key] = modality
        }
        for key in parameters.keys.sorted() {
            guard let attributeLevel = QIDOResource.matchingLevel(for: key) else { continue }
            if !resource.allows(attributeLevel) {
                let option = Self.optionNames[key] ?? key
                throw DICOMwebOptionRefusal(.usage,
                    "\(option) is not permitted for \(resource.pathTemplate) (PS3.18 10.6.1.2.1). Remove the filter or select an allowed unscoped resource.")
            }
        }
        self.query = QIDOQuery(parameters: parameters)
    }

    private static let optionNames = [
        "00100010": "--patient-name", "00100020": "--patient-id", "00080020": "--study-date",
        "0020000D": "--study", "0020000E": "--series", "00080050": "--accession-number",
        "00080060": "--modality", "00080061": "--modality", "00081030": "--study-description",
        "00400244": "--pps-start-date", "00400245": "--pps-start-time",
        "00400275.00400009": "--sps-id", "00400275.00401001": "--requested-procedure-id",
    ]
}
