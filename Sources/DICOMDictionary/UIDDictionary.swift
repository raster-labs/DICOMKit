/// Standard DICOM UID Dictionary
///
/// Provides lookup for every UID registered in PS3.6 Table A-1: Transfer Syntaxes,
/// SOP Classes, Meta SOP Classes, Well-known SOP Instances, Coding Schemes,
/// Application Context Names, Service Classes, LDAP OIDs and the rest.
/// Reference: DICOM PS3.6 2026a - Registry of DICOM unique identifiers (UIDs)
///
/// The entries themselves are in `UIDDictionaryEntries.swift`, generated from the
/// PS3.6 DocBook by `Scripts/generate_uid_dictionary.py`.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — lookup API only; the 465 registry rows
/// are generated (see UIDDictionaryEntries.swift). The two entries in
/// `unregisteredEntries` are the Fragmentable HEVC syntaxes that DICOMCore supports
/// by decision (DICOMCore report P2); no PS3.6 edition (2023b, 2026a, 2026d checked)
/// registers them, and they carry `registered: false`.
public struct UIDDictionary {
    /// UIDs that DICOMKit supports but PS3.6 does not register. They are kept so
    /// that a file written with them can still be named; `registered` is `false`.
    public static let unregisteredEntries: [UIDEntry] = [
        UIDEntry(uid: "1.2.840.10008.1.2.4.107.1",
                 name: "Fragmentable HEVC/H.265 Main Profile / Level 5.1 (not registered in PS3.6)",
                 keyword: "HEVCMP51F", type: .transferSyntax, registered: false),
        UIDEntry(uid: "1.2.840.10008.1.2.4.108.1",
                 name: "Fragmentable HEVC/H.265 Main 10 Profile / Level 5.1 (not registered in PS3.6)",
                 keyword: "HEVCM10P51F", type: .transferSyntax, registered: false),
    ]

    private static let entries: [String: UIDEntry] = {
        var dict = [String: UIDEntry](minimumCapacity: registryEntries.count + unregisteredEntries.count)
        for entry in registryEntries { dict[entry.uid] = entry }
        for entry in unregisteredEntries where dict[entry.uid] == nil { dict[entry.uid] = entry }
        return dict
    }()

    /// Looks up a UID entry by UID value
    /// - Parameter uid: The UID to look up
    /// - Returns: The UID entry, or nil if not found
    public static func lookup(uid: String) -> UIDEntry? {
        return entries[uid]
    }

    /// Looks up a UID entry by keyword
    /// - Parameter keyword: The keyword to look up
    /// - Returns: The UID entry, or nil if not found
    public static func lookup(keyword: String) -> UIDEntry? {
        guard !keyword.isEmpty else { return nil }
        return entries.values.first { $0.keyword == keyword }
    }

    /// All UID entries (registered and unregistered), sorted by UID
    public static var allEntries: [UIDEntry] {
        return Array(entries.values).sorted { $0.uid < $1.uid }
    }

    /// Transfer Syntax UIDs only
    public static var transferSyntaxes: [UIDEntry] {
        return entries.values.filter { $0.type == .transferSyntax }.sorted { $0.uid < $1.uid }
    }

    /// SOP Class UIDs only
    public static var sopClasses: [UIDEntry] {
        return entries.values.filter { $0.type == .sopClass }.sorted { $0.uid < $1.uid }
    }
}
