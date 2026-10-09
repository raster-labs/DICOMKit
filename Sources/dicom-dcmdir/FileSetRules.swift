// NEMA-verified: 2026a, checked 2026-10-06 — no rule of its own since D253: the File ID / File-set ID rules of PS3.10 2026a 8.1, 8.2, 8.5, 8.6 and the PS3.3 2026a Table F.3-2 / F.3-3 / F.4-1 citations are DICOMKit DICOMDIRFileSetRules, which the tool calls; the typealias below only forwards for the DICOMStudio copy and the tests
import Foundation
import DICOMCore
import DICOMKit

/// The pre-D253 name of `DICOMDIRFileSetRules` (the PS3.10 / PS3.3 rules `dicom-dcmdir validate`
/// checks on top of `DICOMDirectory.validate`), now shared with the DICOMStudio CLI Workshop.
@available(*, deprecated, renamed: "DICOMDIRFileSetRules")
typealias FileSetRules = DICOMDIRFileSetRules
