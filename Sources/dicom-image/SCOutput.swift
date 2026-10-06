// NEMA-verified: 2026a, checked 2026-10-06 — no rule of its own since D274: the Conversion Type terms (PS3.3 2026a Table C.8-24), the P-IMAGE-VR refusals (PS3.5 2026a Table 6.2-1, 9.1), Media Storage SOP Instance UID (0002,0003) = SOP Instance UID (PS3.10 Table 7.1-1) and Specific Character Set ISO_IR 192 for non-ASCII text (PS3.3 Table C.12-1, C.12-5) are DICOMKit ImageConverter.OutputRules, which the tool calls; the typealias below only forwards for the tests and DICOMStudio's copy
import Foundation
import DICOMCore
import DICOMKit

/// The pre-D274 name of ``ImageConverter/OutputRules`` (the checks and post-processing
/// dicom-image applied around the shared `ImageConverter` engine), now shared with the
/// DICOMStudio CLI Workshop.
@available(*, deprecated, renamed: "ImageConverter.OutputRules", message: "lifted into DICOMKit (D274)")
typealias SCOutput = ImageConverter.OutputRules
