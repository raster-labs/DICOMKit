// NEMA-verified: 2026a, checked 2026-10-06 — no table of its own since D248: the --iod SOP Class → IOD name map (PS3.6 2026a Table A-1 UIDs; PS3.3 2026a Annex A IODs per PS3.4 Table B.5-1) is DICOMValidator.iodNameBySOPClassUID / iodName(forIODOption:), which the tool calls; this file only forwards the pre-D248 names for the DICOMStudio copy and the tests
import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit

/// The pre-D248 name of the `--iod` value mapping. The table and the resolution now live in
/// DICOMKit (`DICOMValidator.iodNameBySOPClassUID`, `DICOMValidator.iodName(forIODOption:)`),
/// shared by `dicom-validate` and the DICOMStudio CLI Workshop; this type only forwards.
@available(*, deprecated, message: "use DICOMValidator.iodNameBySOPClassUID / DICOMValidator.iodName(forIODOption:) (D248)")
enum IODOption {

    /// Engine IOD name per SOP Class UID (PS3.6 Table A-1), as `DICOMValidator` detects it.
    static var engineNameBySOPClassUID: [String: String] { DICOMValidator.iodNameBySOPClassUID }

    /// The SOP Class UID an `--iod` value names, by Table A-1 keyword (any case) or UID.
    static func sopClassUID(for value: String) -> String? {
        DICOMValidator.sopClassUID(forIODOption: value)
    }

    /// The engine IOD name for an `--iod` value (see `DICOMValidator.iodName(forIODOption:)`).
    static func engineName(for value: String) -> String {
        DICOMValidator.iodName(forIODOption: value)
    }
}
