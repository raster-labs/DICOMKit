import DICOMCore

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data of its own:
// `DataElementEntry` mirrors the columns of PS3.6 Table 6-1 (Tag, Name, Keyword, VR, VM,
// Retired) and `UIDEntry` the columns of Table A-1 (UID Value, Name, Keyword, Type);
// `UIDType` has a case for each of the 12 distinct values of the A-1 "UID Type" column
// (the mapping is in Scripts/generate_uid_dictionary.py).

/// Data Element Dictionary Entry
///
/// Represents a standard DICOM data element definition from the Data Element Dictionary.
/// Reference: DICOM PS3.6 - Data Dictionary
public struct DataElementEntry: Sendable, Hashable {
    /// Data element tag
    public let tag: Tag

    /// Human-readable name. Empty for the few retired elements whose PS3.6 row is blank.
    public let name: String

    /// Keyword identifier. Empty for the few elements whose PS3.6 row has no keyword.
    public let keyword: String

    /// Value Representation(s) - some elements support multiple VRs
    public let vr: [VR]

    /// Value Multiplicity, verbatim from PS3.6 (e.g., "1", "1-n", "3", "1-3", "1-n or 1")
    public let vm: String

    /// Indicates if this element is retired
    public let retired: Bool

    /// Creates a data element entry
    /// - Parameters:
    ///   - tag: Data element tag
    ///   - name: Human-readable name
    ///   - keyword: Keyword identifier
    ///   - vr: Value Representation(s)
    ///   - vm: Value Multiplicity
    ///   - retired: Whether this element is retired
    public init(tag: Tag, name: String, keyword: String, vr: [VR], vm: String, retired: Bool = false) {
        self.tag = tag
        self.name = name
        self.keyword = keyword
        self.vr = vr
        self.vm = vm
        self.retired = retired
    }

    /// Convenience initializer for single VR elements
    public init(tag: Tag, name: String, keyword: String, vr: VR, vm: String, retired: Bool = false) {
        self.init(tag: tag, name: name, keyword: keyword, vr: [vr], vm: vm, retired: retired)
    }
}

/// UID Dictionary Entry
///
/// Represents a standard DICOM UID definition.
/// Reference: DICOM PS3.6 - Registry of DICOM unique identifiers (UIDs)
public struct UIDEntry: Sendable, Hashable {
    /// UID value
    public let uid: String

    /// Human-readable name, verbatim from PS3.6 Table A-1 (retired UIDs end in "(Retired)")
    public let name: String

    /// Keyword identifier
    public let keyword: String

    /// UID type classification
    public let type: UIDType

    /// `true` when PS3.6 lists the UID as retired
    public let retired: Bool

    /// `false` for a UID that DICOMKit supports but no PS3.6 edition registers
    /// (see `UIDDictionary.unregisteredEntries`)
    public let registered: Bool

    /// Creates a UID entry
    /// - Parameters:
    ///   - uid: UID value
    ///   - name: Human-readable name
    ///   - keyword: Keyword identifier
    ///   - type: UID type
    ///   - retired: Whether PS3.6 lists the UID as retired
    ///   - registered: Whether PS3.6 registers the UID at all
    public init(uid: String, name: String, keyword: String, type: UIDType,
                retired: Bool = false, registered: Bool = true) {
        self.uid = uid
        self.name = name
        self.keyword = keyword
        self.type = type
        self.retired = retired
        self.registered = registered
    }
}

/// UID Type Classification — the "UID Type" column of PS3.6 Table A-1
public enum UIDType: Sendable, Hashable {
    /// Transfer Syntax UID
    case transferSyntax
    /// SOP Class UID
    case sopClass
    /// Meta SOP Class UID
    case metaSOPClass
    /// Well-known SOP Instance UID
    case wellKnown
    /// LDAP OID
    case ldap
    /// Coding Scheme (including "DICOM UIDs as a Coding Scheme")
    case codingScheme
    /// Application Context Name
    case applicationContext
    /// Service Class UID (e.g. Storage Service Class)
    case serviceClass
    /// Application Hosting Model (PS3.19)
    case applicationHostingModel
    /// Mapping Resource (PS3.16)
    case mappingResource
    /// Synchronization Frame of Reference (PS3.3)
    case synchronizationFrameOfReference
}
