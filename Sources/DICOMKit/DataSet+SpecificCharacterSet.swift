// NEMA-verified: 2026a, checked 2026-10-01 — Specific Character Set (0008,0005) Type 1C "Required if an expanded or replacement character set is used" (PS3.3 2026a Table C.12-1), Defined Term "ISO_IR 192" = Unicode in UTF-8 (Table C.12-5); the VRs it affects are SH, LO, ST, LT, PN, UC, UT (PS3.5 2026a 6.1.2.3) — dumped from the DocBook by script
import Foundation
import DICOMCore

extension DataSet {

    /// Specific Character Set (0008,0005) Defined Term for Unicode in UTF-8
    /// (PS3.3 2026a Table C.12-5).
    static let utf8SpecificCharacterSet = "ISO_IR 192"

    /// The string VRs whose repertoire Specific Character Set extends (PS3.5 6.1.2.3).
    static let characterSetDependentVRs: Set<VR> = [.SH, .LO, .ST, .LT, .PN, .UC, .UT]

    /// Whether any SH, LO, ST, LT, PN, UC or UT value in this data set, or in an
    /// Item of one of its Sequences, holds a byte outside the Default Character
    /// Repertoire (a byte of 0x80 or more).
    func containsNonASCIIText() -> Bool {
        Self.containsNonASCIIText(in: Array(self))
    }

    private static func containsNonASCIIText(in elements: [DataElement]) -> Bool {
        for element in elements {
            if let items = element.sequenceItems {
                for item in items where containsNonASCIIText(in: Array(item.elements.values)) {
                    return true
                }
            } else if characterSetDependentVRs.contains(element.vr),
                      element.valueData.contains(where: { $0 >= 0x80 }) {
                return true
            }
        }
        return false
    }

    /// Sets Specific Character Set (0008,0005) to `ISO_IR 192` when it is absent and a
    /// text value is not ASCII. DICOMKit encodes string values as UTF-8, and the
    /// attribute is Type 1C, "Required if an expanded or replacement character set is
    /// used" (PS3.3 2026a Table C.12-1). An existing value is left alone.
    mutating func setUTF8SpecificCharacterSetIfNeeded() {
        guard self[.specificCharacterSet] == nil, containsNonASCIIText() else { return }
        setString(Self.utf8SpecificCharacterSet, for: .specificCharacterSet, vr: .CS)
    }
}
