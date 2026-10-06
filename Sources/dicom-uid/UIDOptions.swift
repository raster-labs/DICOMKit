// NEMA-verified: 2026a, checked 2026-10-06 — --root is checked by DICOMKit UIDManager.RootRule against PS3.5 2026a 9.1 (lifted from this file's UIDRootRule, D250; the typealias below only forwards for the DICOMStudio copy and the tests); --uuid builds the UUID derived UID of PS3.5 B.2 ("2.25." + the UUID as a decimal integer, at most 39 digits); lookup --type covers all 12 UID Type values of PS3.6 2026a Table A-1 (465 rows dumped by script; "DICOM UIDs as a Coding Scheme" is folded into coding-scheme by DICOMDictionary.UIDType)
import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit

/// The pre-D250 name of `UIDManager.RootRule` (PS3.5 9.1 checks for a `--root` value and the
/// room it leaves for generated UIDs), now shared with the DICOMStudio CLI Workshop.
@available(*, deprecated, renamed: "UIDManager.RootRule")
typealias UIDRootRule = UIDManager.RootRule

/// The UUID derived UID of PS3.5 B.2: the root "2.25." followed by the 128-bit UUID
/// as an unsigned decimal integer without leading zeros (up to 39 digits).
enum UUIDDerivedUID {
    static func make(from uuid: UUID = UUID()) -> String {
        let t = uuid.uuid
        var bytes = [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15]
        var digits: [Character] = []
        // Repeated division of the big-endian 128-bit value by 10.
        while bytes.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in 0..<bytes.count {
                let value = remainder * 256 + Int(bytes[i])
                bytes[i] = UInt8(value / 10)
                remainder = value % 10
            }
            digits.append(Character(String(remainder)))
        }
        return "2.25." + (digits.isEmpty ? "0" : String(digits.reversed()))
    }
}

/// `lookup --type` values: one per UID Type of PS3.6 Table A-1 (the shared engine list,
/// `UIDConsole.lookupTypeFilters`, so the CLI and DICOMStudio accept the same values).
enum LookupTypeFilter {
    /// (option value, DICOMDictionary type, PS3.6 Table A-1 "UID Type" text)
    static var all: [(value: String, type: UIDType, tableA1: String)] { UIDConsole.lookupTypeFilters }

    static var valueList: String { all.map(\.value).joined(separator: ", ") }

    static func entries(for value: String) -> [UIDEntry]? {
        UIDConsole.entries(forTypeFilter: value)
    }
}
