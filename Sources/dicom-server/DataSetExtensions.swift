// NEMA-verified: 2026a, checked 2026-10-01 — the VR of every element the C-FIND responses write comes from DICOMKit's data dictionary (PS3.6 2026a Table 6-1); the former hand-written switch had 6 of 19 tags wrong (Patient ID, Patient's Name, Study ID, Accession Number, Study Description, Series Description written as CS instead of LO / PN / SH / SH / LO / LO)
import Foundation
import DICOMCore
import DICOMKit

// MARK: - DataSet Helper Extension

extension DataSet {
    /// Sets a string value for a tag, with the VR that PS3.6 Table 6-1 gives the tag.
    ///
    /// The VR is taken from DICOMKit's data dictionary (`setStringFromDictionary`), so a
    /// call site cannot pick one that disagrees with the standard. Padding follows
    /// PS3.5 6.2 (NUL for UI, space for the other string VRs). A tag the dictionary does
    /// not know (private) falls back to LO.
    mutating func set(string value: String, for tag: Tag) {
        if !setStringFromDictionary(value, for: tag) {
            setString(value, for: tag, vr: .LO)
        }
    }
}
