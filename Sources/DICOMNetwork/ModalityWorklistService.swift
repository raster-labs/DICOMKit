import Foundation
import DICOMCore
import DICOMDictionary

/// SOP Class UID for Modality Worklist Information Model - FIND
/// Reference: PS3.4 Annex K - Modality Worklist Information Model
public let modalityWorklistInformationModelFindSOPClassUID = "1.2.840.10008.5.1.4.31"

/// Configuration for the Modality Worklist Service
public struct ModalityWorklistConfiguration: Sendable, Hashable {
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID for this DICOM implementation
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?

    /// Forces the Specific Character Set (0008,0005) of the C-FIND Identifier.
    ///
    /// When nil (the default) the narrowest repertoire that represents every text
    /// key is chosen: none for pure ASCII, "ISO_IR 100" for Latin-1, "ISO_IR 192"
    /// otherwise (PS3.5 6.1.2, PS3.4 C.2.2.2.1).
    public let specificCharacterSet: String?
    
    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"
    
    /// Creates a worklist configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - userIdentity: User identity for authentication (optional)
    ///   - specificCharacterSet: forced (0008,0005) for the Identifier; nil chooses automatically
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        userIdentity: UserIdentity? = nil,
        specificCharacterSet: String? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.userIdentity = userIdentity
        self.specificCharacterSet = specificCharacterSet
    }
}

/// Modality Worklist query keys
///
/// Top-level patient / study attributes are encoded directly in the query
/// identifier.  Attributes that belong to the Scheduled Procedure Step (SPS)
/// are encoded inside a `(0040,0100)` Sequence item per DICOM PS3.4 Table K.6-1.
public struct WorklistQueryKeys: Sendable {
    /// Top-level query attributes (patient, study level).
    private var keys: [Tag: String] = [:]
    /// Attributes that go inside the `(0040,0100)` SPS Sequence item.
    private var spsKeys: [Tag: String] = [:]
    /// Caller-forced Specific Character Set; nil means choose from the values.
    private var characterSetOverride: String?

    public init() {}

    // MARK: - Patient Demographics

    /// Patient's Name
    public func patientName(_ value: String) -> WorklistQueryKeys {
        var copy = self
        copy.keys[.patientName] = value
        return copy
    }

    /// Patient ID
    public func patientID(_ value: String) -> WorklistQueryKeys {
        var copy = self
        copy.keys[.patientID] = value
        return copy
    }

    /// Accession Number (SH) — top-level matching key.
    public func accessionNumber(_ value: String) -> WorklistQueryKeys {
        var copy = self
        copy.keys[.accessionNumber] = value
        return copy
    }

    // MARK: - Scheduled Procedure Step (SPS) attributes (inside (0040,0100) sequence)

    /// Scheduled Procedure Step Start Date (DA) — encoded inside the SPS sequence.
    /// - Parameter value: Date in YYYYMMDD format, or a DICOM date range such as
    ///   "20240101-20240131".  Pass "" to request all dates.
    public func scheduledDate(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0040,0002) Scheduled Procedure Step Start Date — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0040, element: 0x0002)] = value
        return copy
    }

    /// Scheduled Procedure Step Start Time (TM) — encoded inside the SPS sequence.
    /// - Parameter value: Time in HHMMSS format, or a DICOM time range such as
    ///   "1000-1800" (PS3.4 C.2.2.2.5.2). Pass "" to request all times.
    public func scheduledTime(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0040,0003) Scheduled Procedure Step Start Time — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0040, element: 0x0003)] = value
        return copy
    }

    /// Scheduled Station AE Title (AE) — encoded inside the SPS sequence.
    ///
    /// The value is validated when the Identifier is built (see
    /// ``validateScheduledStationAETitle(_:)``); use ``forQuery(date:time:station:patientName:patientID:modality:spsStatus:accession:performingPhysician:)``
    /// to have it validated up front.
    public func scheduledStationAET(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0040,0001) Scheduled Station AE Title — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0040, element: 0x0001)] = value
        return copy
    }

    /// Validates a Scheduled Station AE Title matching key.
    ///
    /// AE is 16 characters maximum from the Default Character Repertoire excluding
    /// backslash and control characters (PS3.5 Table 6.2-1). PS3.4 2026a Table K.6-1:
    /// "Scheduled Station AE Title shall be retrieved with Single Value Matching
    /// only", so the wildcard characters `*` and `?` (which would make it Wild Card
    /// Matching, C.2.2.2.4) are refused (before 2026-10-01 they were accepted, D81).
    /// An empty value is a Universal Match and is accepted.
    ///
    /// - Throws: ``WorklistDateFilterError/invalidStationAETitle(_:)``
    public static func validateScheduledStationAETitle(_ value: String) throws {
        guard !value.isEmpty else { return }
        guard value.count <= 16 else {
            throw WorklistDateFilterError.invalidStationAETitle(value)
        }
        for scalar in value.unicodeScalars {
            let v = scalar.value
            // ISO 646 graphic characters only: no control characters (0x00–0x1F,
            // 0x7F), no backslash (value delimiter), nothing outside ASCII.
            if v < 0x20 || v >= 0x7F || v == 0x5C {
                throw WorklistDateFilterError.invalidStationAETitle(value)
            }
            // Single Value Matching only (PS3.4 Table K.6-1): no wild card characters.
            if v == 0x2A || v == 0x3F {
                throw WorklistDateFilterError.invalidStationAETitle(value)
            }
        }
    }

    /// Modality (CS) — encoded inside the SPS sequence per PS3.4 Table K.6-1.
    public func modality(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0008,0060) Modality — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0008, element: 0x0060)] = value
        return copy
    }

    /// Scheduled Performing Physician's Name (PN) — encoded inside the SPS sequence.
    ///
    /// A Required Matching Key per PS3.4 Table K.6-1, which permits Single Value
    /// Matching or Wild Card Matching (e.g. "SMITH*"). Pass "" to request the
    /// attribute back without filtering on it.
    public func scheduledPerformingPhysician(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0040,0006) Scheduled Performing Physician's Name — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0040, element: 0x0006)] = value
        return copy
    }

    // MARK: - SPS status filter

    /// Scheduled Procedure Step Status (CS) — encoded inside the SPS sequence.
    /// Common values: "SCHEDULED", "IN PROGRESS", "DISCONTINUED", "COMPLETED".
    /// Pass "" to request items regardless of status.
    public func scheduledProcedureStepStatus(_ value: String) -> WorklistQueryKeys {
        var copy = self
        // (0040,0020) Scheduled Procedure Step Status — inside (0040,0100) SPS Sequence
        copy.spsKeys[Tag(group: 0x0040, element: 0x0020)] = value
        return copy
    }

    // MARK: - Generic keys (any PS3.4 Table K.6-1 attribute)

    /// Adds or replaces a top-level (root) key. Pass "" to request the attribute
    /// as a return key without matching on it. Use for the Optional matching keys
    /// that have no dedicated setter (Requested Procedure ID, Study Instance UID,
    /// Referring Physician's Name, Admission ID, …).
    public func matching(_ tag: Tag, _ value: String) -> WorklistQueryKeys {
        var copy = self
        copy.keys[tag] = value
        return copy
    }

    /// Adds or replaces a key inside the Scheduled Procedure Step Sequence item
    /// (0040,0100). Pass "" to request it as a return key.
    public func spsMatching(_ tag: Tag, _ value: String) -> WorklistQueryKeys {
        var copy = self
        copy.spsKeys[tag] = value
        return copy
    }

    /// Returns top-level query attributes.
    internal var allKeys: [Tag: String] { keys }
    /// Returns SPS-level attributes that go inside `(0040,0100)` sequence item.
    internal var allSPSKeys: [Tag: String] { spsKeys }
    /// The caller-forced Specific Character Set, if any.
    internal var specificCharacterSetOverride: String? { characterSetOverride }

    /// Specific Character Set (CS) — forces the character set used to encode the
    /// query identifier's text keys and declared in (0008,0005).
    /// Common values: "ISO_IR 100" (Latin-1), "ISO_IR 192" (UTF-8). Without it
    /// the narrowest set that represents every key is chosen (PS3.5 6.1.2).
    /// Reference: PS3.3 C.12.1.1.2
    public func specificCharacterSet(_ value: String) -> WorklistQueryKeys {
        var copy = self
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        copy.characterSetOverride = trimmed.isEmpty ? nil : trimmed
        copy.keys[.specificCharacterSet] = ""
        return copy
    }

    /// The Data Elements whose values are encoded with the Specific Character Set
    /// (PS3.5 6.1.2.3): PN, LO, SH, ST, LT, UT and UC. Every other VR is ISO 646.
    internal static let characterSetVRs: Set<VR> = [.PN, .LO, .SH, .ST, .LT, .UT, .UC]

    /// The VR an Identifier key is encoded with: the data dictionary's, with the
    /// same fallbacks the encoder uses for tags it does not know.
    internal static func vr(for tag: Tag, inSPS: Bool) -> VR {
        if let entry = DataElementDictionary.lookup(tag: tag) {
            return entry.vr.first ?? .UN
        }
        switch (tag.group, tag.element) {
        case (0x0010, 0x0010): return .PN
        case (0x0010, 0x0020): return .LO
        case (0x0020, 0x000D): return .UI
        case (0x0008, 0x0050): return .SH
        case (0x0008, 0x0060): return .CS
        case (0x0040, 0x0001): return .AE
        case (0x0040, 0x0002): return .DA
        case (0x0040, 0x0003): return .TM
        case (0x0040, 0x0006): return .PN
        case (0x0040, 0x0009), (0x0040, 0x0010): return .SH
        case (0x0040, 0x0020): return .CS
        default: return .LO
        }
    }

    /// Every text-VR value of the Identifier — the input to the character set choice.
    internal var textValues: [String] {
        var values: [String] = []
        for (tag, value) in keys where !value.isEmpty
            && Self.characterSetVRs.contains(Self.vr(for: tag, inSPS: false)) {
            values.append(value)
        }
        for (tag, value) in spsKeys where !value.isEmpty
            && Self.characterSetVRs.contains(Self.vr(for: tag, inSPS: true)) {
            values.append(value)
        }
        return values
    }

    /// Chooses the character set for this Identifier: `override` (or the keys' own
    /// override) when given, else the narrowest one that represents every text key.
    internal func chooseCharacterSet(override: String? = nil) -> DIMSECharacterSet {
        DIMSECharacterSet.choose(for: textValues, override: override ?? characterSetOverride)
    }

    /// Default worklist query keys requesting all common return attributes.
    public static func `default`() -> WorklistQueryKeys {
        var wlk = WorklistQueryKeys()
        // Specific Character Set — a Return Key (PS3.4 Table K.6-1). The value sent
        // is chosen when the Identifier is built (empty for pure-ASCII keys,
        // "ISO_IR 100" / "ISO_IR 192" when a key needs them, PS3.5 6.1.2).
        wlk.keys[.specificCharacterSet]                   = ""
        // Top-level return attributes
        wlk.keys[.patientName]                            = ""
        wlk.keys[.patientID]                             = ""
        wlk.keys[.studyInstanceUID]                      = ""
        wlk.keys[.accessionNumber]                       = ""
        wlk.keys[Tag(group: 0x0010, element: 0x0030)]    = ""  // Patient's Birth Date
        wlk.keys[Tag(group: 0x0010, element: 0x0040)]    = ""  // Patient's Sex
        wlk.keys[Tag(group: 0x0008, element: 0x0090)]    = ""  // Referring Physician's Name
        wlk.keys[Tag(group: 0x0040, element: 0x1001)]    = ""  // Requested Procedure ID
        wlk.keys[.requestedProcedureDescription]         = ""  // (0032,1060) Requested Procedure Description
        wlk.keys[Tag(group: 0x0032, element: 0x1064)]    = ""  // Requested Procedure Code Sequence (1C)
        wlk.keys[Tag(group: 0x0008, element: 0x1110)]    = ""  // Referenced Study Sequence (2)
        wlk.keys[Tag(group: 0x0040, element: 0x1003)]    = ""  // Requested Procedure Priority (2)
        wlk.keys[Tag(group: 0x0040, element: 0x1004)]    = ""  // Patient Transport Arrangements (2)
        wlk.keys[Tag(group: 0x0032, element: 0x1032)]    = ""  // Requesting Physician (2)
        wlk.keys[Tag(group: 0x0038, element: 0x0010)]    = ""  // Admission ID (2)
        wlk.keys[Tag(group: 0x0038, element: 0x0300)]    = ""  // Current Patient Location (2)
        wlk.keys[Tag(group: 0x0010, element: 0x1030)]    = ""  // Patient's Weight (2)
        wlk.keys[Tag(group: 0x0010, element: 0x1020)]    = ""  // Patient's Size (3)
        wlk.keys[Tag(group: 0x0010, element: 0x21C0)]    = ""  // Pregnancy Status (2)
        wlk.keys[Tag(group: 0x0010, element: 0x2000)]    = ""  // Medical Alerts (2)
        wlk.keys[Tag(group: 0x0010, element: 0x2110)]    = ""  // Allergies (2)
        wlk.keys[Tag(group: 0x0038, element: 0x0050)]    = ""  // Special Needs (2)
        wlk.keys[Tag(group: 0x0038, element: 0x0500)]    = ""  // Patient State (2)
        wlk.keys[Tag(group: 0x0040, element: 0x3001)]    = ""  // Confidentiality Constraint on Patient Data Description (2)
        // SPS return attributes (encoded inside (0040,0100) sequence)
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0001)] = ""  // Scheduled Station AE Title
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0002)] = ""  // Scheduled Procedure Step Start Date
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0003)] = ""  // Scheduled Procedure Step Start Time
        wlk.spsKeys[Tag(group: 0x0008, element: 0x0060)] = ""  // Modality
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0009)] = ""  // Scheduled Procedure Step ID
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0007)] = ""  // Scheduled Procedure Step Description
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0020)] = ""  // Scheduled Procedure Step Status (CS)
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0006)] = ""  // Scheduled Performing Physician's Name
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0010)] = ""  // Scheduled Station Name
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0008)] = ""  // Scheduled Protocol Code Sequence (1C)
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0011)] = ""  // Scheduled Procedure Step Location (2)
        wlk.spsKeys[Tag(group: 0x0032, element: 0x1070)] = ""  // Requested Contrast Agent (2C)
        wlk.spsKeys[Tag(group: 0x0040, element: 0x0012)] = ""  // Pre-Medication (2C)
        return wlk
    }
}

/// Error thrown when an MWL scheduled-date or scheduled-time filter cannot be resolved.
public enum WorklistDateFilterError: Error, CustomStringConvertible, Sendable {
    /// The supplied date filter was neither `today`/`tomorrow`, a valid `YYYYMMDD`
    /// Single Value Match, nor a valid DA Range Match per PS3.4 C.2.2.2.5.1.
    case invalidDateFormat(String)
    /// The supplied time filter was neither a valid `HHMMSS` Single Value Match nor
    /// a valid TM Range Match per PS3.4 C.2.2.2.5.2.
    case invalidTimeFormat(String)
    /// The Scheduled Station AE Title filter is not a valid AE value: more than 16
    /// characters, or a backslash / control / non-ASCII character (PS3.5 Table 6.2-1).
    case invalidStationAETitle(String)

    public var description: String {
        switch self {
        case .invalidStationAETitle(let value):
            return "Invalid Scheduled Station AE Title '\(value)': an AE title is at most 16 " +
                "characters from the default repertoire, without backslash or control " +
                "characters (PS3.5 Table 6.2-1), matched by Single Value Matching only — no '*' or '?' " +
                "wildcards (PS3.4 Table K.6-1)."
        case .invalidDateFormat(let filter):
            return "Invalid date filter '\(filter)'. Use YYYYMMDD, 'today', 'tomorrow', " +
                "or a DICOM date range (YYYYMMDD-YYYYMMDD, YYYYMMDD-, or -YYYYMMDD)."
        case .invalidTimeFormat(let filter):
            return "Invalid time filter '\(filter)'. Use HHMMSS, or a DICOM time range " +
                "(HHMMSS-HHMMSS, HHMMSS-, or -HHMMSS)."
        }
    }
}

extension WorklistQueryKeys {

    /// Scheduled Procedure Step Status (0040,0020) Defined Terms, PS3.3 2026a
    /// Table C.4-10: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED. Defined Terms may be
    /// extended, so an unlisted value is sent as given — but it is almost always a
    /// Performed Procedure Step Status (IN PROGRESS / COMPLETED / DISCONTINUED, Table
    /// C.4-14) typed by mistake, which matches nothing. Formerly dicom-mwl's CLI-local
    /// copy (D264).
    public static let scheduledProcedureStepStatusDefinedTerms: [String] =
        ["SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"]

    /// The stderr warning (with its trailing newline) for a `--sps-status` value
    /// outside ``scheduledProcedureStepStatusDefinedTerms``, or nil when the value is a
    /// Defined Term, empty or absent (D264).
    public static func spsStatusWarning(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              !scheduledProcedureStepStatusDefinedTerms.contains(value) else { return nil }
        return "warning: --sps-status '\(value)' is not a Scheduled Procedure Step Status Defined Term "
            + "(PS3.3 Table C.4-10: \(scheduledProcedureStepStatusDefinedTerms.joined(separator: ", "))); "
            + "it is sent as given and will match only an SCP that uses that private term\n"
    }

    /// Formats today (or a day offset from today) as a DICOM `YYYYMMDD` date string,
    /// pinned to `en_US_POSIX` so the result is always a Gregorian calendar date
    /// regardless of the host device's locale/calendar.
    private static func formattedDate(daysFromToday offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let day = offset == 0 ? Date() : Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return formatter.string(from: day)
    }

    /// True if `value` is a valid DA (date) value per PS3.4: 8 digits `YYYYMMDD`.
    private static func isValidDAComponent(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy(\.isNumber)
    }

    /// True if `value` is a valid TM (time) component per PS3.4: `HH`, `HHMM`,
    /// `HHMMSS`, or `HHMMSS.FFFFFF`, all digits (plus one optional `.`).
    private static func isValidTMComponent(_ value: String) -> Bool {
        let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        let hhmmss = parts[0]
        guard [2, 4, 6].contains(hhmmss.count), hhmmss.allSatisfy(\.isNumber) else { return false }
        if parts.count == 2 {
            let fraction = parts[1]
            guard !fraction.isEmpty, fraction.count <= 6, fraction.allSatisfy(\.isNumber) else { return false }
        }
        return true
    }

    /// Resolves an MWL scheduled-date filter to a DICOM DA Single Value Match or
    /// Range Match string per PS3.4 C.2.2.2.5.1.
    ///
    /// This is the SINGLE source of truth shared by the `dicom-mwl` CLI, DICOMStudio's
    /// in-app worklist query, and the CLI-parity reference, so their date handling
    /// cannot drift.
    ///
    /// Accepts:
    /// - `today` / `tomorrow` (case-insensitive convenience shorthands)
    /// - A bare `YYYYMMDD` (Single Value Matching)
    /// - `YYYYMMDD-YYYYMMDD`, `YYYYMMDD-`, or `-YYYYMMDD` (Range Matching, both bounds
    ///   inclusive; `today`/`tomorrow` may be used as either bound)
    ///
    /// Anything else throws ``WorklistDateFilterError/invalidDateFormat(_:)``.
    public static func resolveScheduledDate(_ filter: String) throws -> String {
        func resolveBound(_ raw: String) -> String? {
            switch raw.lowercased() {
            case "today": return formattedDate(daysFromToday: 0)
            case "tomorrow": return formattedDate(daysFromToday: 1)
            default: return isValidDAComponent(raw) ? raw : nil
            }
        }

        if let hyphenIndex = filter.firstIndex(of: "-") {
            let fromRaw = String(filter[filter.startIndex..<hyphenIndex])
            let toRaw = String(filter[filter.index(after: hyphenIndex)...])
            guard filter[filter.index(after: hyphenIndex)...].firstIndex(of: "-") == nil else {
                throw WorklistDateFilterError.invalidDateFormat(filter)
            }
            switch (fromRaw.isEmpty, toRaw.isEmpty) {
            case (true, true):
                throw WorklistDateFilterError.invalidDateFormat(filter)
            case (true, false):
                guard let to = resolveBound(toRaw) else { throw WorklistDateFilterError.invalidDateFormat(filter) }
                return "-\(to)"
            case (false, true):
                guard let from = resolveBound(fromRaw) else { throw WorklistDateFilterError.invalidDateFormat(filter) }
                return "\(from)-"
            case (false, false):
                guard let from = resolveBound(fromRaw), let to = resolveBound(toRaw) else {
                    throw WorklistDateFilterError.invalidDateFormat(filter)
                }
                return "\(from)-\(to)"
            }
        }

        guard let resolved = resolveBound(filter) else {
            throw WorklistDateFilterError.invalidDateFormat(filter)
        }
        return resolved
    }

    /// Resolves an MWL scheduled-time filter to a DICOM TM Single Value Match or
    /// Range Match string per PS3.4 C.2.2.2.5.2.
    ///
    /// Accepts a bare `HHMMSS`-style value (Single Value Matching) or
    /// `HHMMSS-HHMMSS`, `HHMMSS-`, or `-HHMMSS` (Range Matching, both bounds
    /// inclusive). Anything else throws ``WorklistDateFilterError/invalidTimeFormat(_:)``.
    public static func resolveScheduledTime(_ filter: String) throws -> String {
        if let hyphenIndex = filter.firstIndex(of: "-") {
            let fromRaw = String(filter[filter.startIndex..<hyphenIndex])
            let toRaw = String(filter[filter.index(after: hyphenIndex)...])
            guard filter[filter.index(after: hyphenIndex)...].firstIndex(of: "-") == nil else {
                throw WorklistDateFilterError.invalidTimeFormat(filter)
            }
            switch (fromRaw.isEmpty, toRaw.isEmpty) {
            case (true, true):
                throw WorklistDateFilterError.invalidTimeFormat(filter)
            case (true, false):
                guard isValidTMComponent(toRaw) else { throw WorklistDateFilterError.invalidTimeFormat(filter) }
                return "-\(toRaw)"
            case (false, true):
                guard isValidTMComponent(fromRaw) else { throw WorklistDateFilterError.invalidTimeFormat(filter) }
                return "\(fromRaw)-"
            case (false, false):
                guard isValidTMComponent(fromRaw), isValidTMComponent(toRaw) else {
                    throw WorklistDateFilterError.invalidTimeFormat(filter)
                }
                return "\(fromRaw)-\(toRaw)"
            }
        }

        guard isValidTMComponent(filter) else {
            throw WorklistDateFilterError.invalidTimeFormat(filter)
        }
        return filter
    }

    /// Builds MWL C-FIND query keys from raw filter strings — the SINGLE source of
    /// truth shared by the `dicom-mwl` CLI, DICOMStudio's in-app worklist query, and
    /// the CLI-parity reference, so their input→C-FIND mapping cannot drift.
    ///
    /// Starts from ``default()`` (all common return keys) and adds a MATCHING key for
    /// each non-empty filter.
    ///
    /// `date` accepts `today`/`tomorrow`/`YYYYMMDD` Single Value Matching, or DA Range
    /// Matching (resolved by ``resolveScheduledDate(_:)``); an unparseable date throws
    /// ``WorklistDateFilterError/invalidDateFormat(_:)``.
    ///
    /// `time` accepts `HHMMSS` Single Value Matching, or TM Range Matching (resolved by
    /// ``resolveScheduledTime(_:)``); an unparseable time throws
    /// ``WorklistDateFilterError/invalidTimeFormat(_:)``.
    ///
    /// Per PS3.4 K.6.1, when both `date` and `time` are supplied as Range Matches, the
    /// SCP interprets the pair as one continuous date-time interval rather than two
    /// independently-matched attributes — this method emits both matching keys as-is
    /// and relies on the SCP for that combined interpretation.
    ///
    /// `patientName` and `performingPhysician` are passed through verbatim — callers add
    /// `*` wildcards explicitly, matching the `dicom-mwl --patient` semantics. Both are
    /// Required Matching Keys that permit Wild Card Matching per PS3.4 Table K.6-1.
    public static func forQuery(
        date: String = "",
        time: String = "",
        station: String = "",
        patientName: String = "",
        patientID: String = "",
        modality: String = "",
        spsStatus: String = "",
        accession: String = "",
        performingPhysician: String = ""
    ) throws -> WorklistQueryKeys {
        var keys = WorklistQueryKeys.default()
        if !date.isEmpty        { keys = keys.scheduledDate(try resolveScheduledDate(date)) }
        if !time.isEmpty        { keys = keys.scheduledTime(try resolveScheduledTime(time)) }
        if !station.isEmpty {
            try validateScheduledStationAETitle(station)
            keys = keys.scheduledStationAET(station)
        }
        if !patientName.isEmpty { keys = keys.patientName(patientName) }
        if !patientID.isEmpty   { keys = keys.patientID(patientID) }
        if !modality.isEmpty    { keys = keys.modality(modality) }
        if !spsStatus.isEmpty   { keys = keys.scheduledProcedureStepStatus(spsStatus) }
        if !accession.isEmpty   { keys = keys.accessionNumber(accession) }
        if !performingPhysician.isEmpty {
            keys = keys.scheduledPerformingPhysician(performingPhysician)
        }
        return keys
    }
}

/// A Code Sequence item (PS3.3 8.8) from a worklist response.
public struct WorklistCodedEntry: Sendable, Hashable {
    /// Code Value (0008,0100)
    public let codeValue: String
    /// Coding Scheme Designator (0008,0102)
    public let codingSchemeDesignator: String
    /// Code Meaning (0008,0104)
    public let codeMeaning: String

    public init(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}

/// A Referenced SOP Sequence item (SOP Class / SOP Instance UID pair).
public struct WorklistSOPReference: Sendable, Hashable {
    /// Referenced SOP Class UID (0008,1150)
    public let sopClassUID: String
    /// Referenced SOP Instance UID (0008,1155)
    public let sopInstanceUID: String
}

/// Modality Worklist item result.
///
/// Attributes from the top-level dataset and from the nested SPS sequence
/// `(0040,0100)` are stored in the same flat dictionary — their tag numbers
/// never collide, so direct lookup works without a second container. Every
/// other sequence (Requested Procedure Code Sequence, Scheduled Protocol Code
/// Sequence, Referenced Study Sequence, …) keeps its items separately in
/// `sequences`, because their nested Code Value / Referenced SOP UIDs would
/// otherwise overwrite one another.
///
/// String values are decoded with the response's Specific Character Set
/// (0008,0005). When it is absent the Default Character Repertoire (ISO-IR 6)
/// applies (PS3.5 6.1.2); as a deliberate leniency a value that then holds a
/// byte >= 0x80 — an SCP sending Latin-1 without declaring it — is decoded as
/// ISO 8859-1 rather than lost.
public struct WorklistItem: Sendable {
    public let attributes: [Tag: Data]
    /// Items of every non-SPS sequence, keyed by the sequence tag. Each item is a
    /// flat tag → value map; nested sequences inside an item are flattened into it.
    public let sequences: [Tag: [[Tag: Data]]]
    private let characterSet: CharacterSetHandler

    public init(attributes: [Tag: Data]) {
        self.init(attributes: attributes, sequences: [:])
    }

    public init(attributes: [Tag: Data], sequences: [Tag: [[Tag: Data]]]) {
        self.attributes = attributes
        self.sequences = sequences
        let declared = attributes[.specificCharacterSet]
            .flatMap { String(data: $0, encoding: .ascii) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        // No (0008,0005) means the Default Character Repertoire, ISO-IR 6
        // (PS3.5 6.1.2); `decode` adds the undeclared-Latin-1 leniency.
        self.characterSet = CharacterSetHandler.from(
            specificCharacterSet: (declared?.isEmpty ?? true) ? nil : declared)
    }

    // MARK: - Private helpers

    /// Decodes with the declared set (or ISO-IR 6 when none was declared).
    /// Leniency: bytes the declared/default set cannot decode — typically an
    /// undeclared ISO 8859-1 value — fall back to Latin-1, which accepts any
    /// byte, so the value is never lost.
    private func decode(_ data: Data) -> String? {
        let s = (characterSet.decode(data) ?? String(data: data, encoding: .isoLatin1))?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        return s.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func stringValue(group: UInt16, element: UInt16) -> String? {
        guard let data = attributes[Tag(group: group, element: element)] else { return nil }
        return decode(data)
    }

    private func codedEntries(group: UInt16, element: UInt16) -> [WorklistCodedEntry] {
        (sequences[Tag(group: group, element: element)] ?? []).compactMap { item in
            guard let value = item[Tag(group: 0x0008, element: 0x0100)].flatMap(decode) else { return nil }
            return WorklistCodedEntry(
                codeValue: value,
                codingSchemeDesignator: item[Tag(group: 0x0008, element: 0x0102)].flatMap(decode) ?? "",
                codeMeaning: item[Tag(group: 0x0008, element: 0x0104)].flatMap(decode) ?? "")
        }
    }

    private func sopReferences(group: UInt16, element: UInt16) -> [WorklistSOPReference] {
        (sequences[Tag(group: group, element: element)] ?? []).compactMap { item in
            guard let instance = item[Tag(group: 0x0008, element: 0x1155)].flatMap(decode) else { return nil }
            return WorklistSOPReference(
                sopClassUID: item[Tag(group: 0x0008, element: 0x1150)].flatMap(decode) ?? "",
                sopInstanceUID: instance)
        }
    }

    // MARK: - Patient Demographics

    /// Patient's Name (0010,0010)
    public var patientName: String? { stringValue(group: 0x0010, element: 0x0010) }

    /// Patient ID (0010,0020)
    public var patientID: String? { stringValue(group: 0x0010, element: 0x0020) }

    /// Patient's Birth Date (0010,0030) in YYYYMMDD format.
    public var patientBirthDate: String? { stringValue(group: 0x0010, element: 0x0030) }

    /// Patient's Sex (0010,0040) — "M", "F", or "O".
    public var patientSex: String? { stringValue(group: 0x0010, element: 0x0040) }

    /// Patient's Weight (0010,1030) in kg (DS)
    public var patientWeight: String? { stringValue(group: 0x0010, element: 0x1030) }

    /// Patient's Size (0010,1020) in m (DS)
    public var patientSize: String? { stringValue(group: 0x0010, element: 0x1020) }

    /// Pregnancy Status (0010,21C0): 1 not pregnant, 2 possibly, 3 definitely, 4 unknown.
    public var pregnancyStatus: UInt16? {
        guard let data = attributes[Tag(group: 0x0010, element: 0x21C0)], data.count >= 2 else { return nil }
        return UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    /// Medical Alerts (0010,2000)
    public var medicalAlerts: String? { stringValue(group: 0x0010, element: 0x2000) }

    /// Allergies (0010,2110)
    public var allergies: String? { stringValue(group: 0x0010, element: 0x2110) }

    /// Special Needs (0038,0050)
    public var specialNeeds: String? { stringValue(group: 0x0038, element: 0x0050) }

    /// Patient State (0038,0500)
    public var patientState: String? { stringValue(group: 0x0038, element: 0x0500) }

    /// Confidentiality Constraint on Patient Data Description (0040,3001)
    public var confidentialityConstraint: String? { stringValue(group: 0x0040, element: 0x3001) }

    // MARK: - Visit / Order

    /// Admission ID (0038,0010)
    public var admissionID: String? { stringValue(group: 0x0038, element: 0x0010) }

    /// Current Patient Location (0038,0300)
    public var currentPatientLocation: String? { stringValue(group: 0x0038, element: 0x0300) }

    /// Requesting Physician (0032,1032)
    public var requestingPhysician: String? { stringValue(group: 0x0032, element: 0x1032) }

    /// Patient Transport Arrangements (0040,1004)
    public var patientTransportArrangements: String? { stringValue(group: 0x0040, element: 0x1004) }

    /// Requested Procedure Priority (0040,1003) — STAT, HIGH, ROUTINE, MEDIUM, LOW
    public var requestedProcedurePriority: String? { stringValue(group: 0x0040, element: 0x1003) }

    // MARK: - Study Level

    /// Study Instance UID (0020,000D)
    public var studyInstanceUID: String? { stringValue(group: 0x0020, element: 0x000D) }

    /// Accession Number (0008,0050)
    public var accessionNumber: String? { stringValue(group: 0x0008, element: 0x0050) }

    /// Referring Physician's Name (0008,0090)
    public var referringPhysicianName: String? { stringValue(group: 0x0008, element: 0x0090) }

    /// Requested Procedure ID (0040,1001)
    public var requestedProcedureID: String? { stringValue(group: 0x0040, element: 0x1001) }

    /// Requested Procedure Description (0032,1060)
    public var requestedProcedureDescription: String? { stringValue(group: 0x0032, element: 0x1060) }

    /// Requested Procedure Code Sequence (0032,1064) — first item
    public var requestedProcedureCode: WorklistCodedEntry? { codedEntries(group: 0x0032, element: 0x1064).first }

    /// Referenced Study Sequence (0008,1110) items
    public var referencedStudies: [WorklistSOPReference] { sopReferences(group: 0x0008, element: 0x1110) }

    // MARK: - Scheduled Procedure Step (SPS) attributes — from (0040,0100) sequence

    /// Scheduled Station AE Title (0040,0001)
    public var scheduledStationAETitle: String? { stringValue(group: 0x0040, element: 0x0001) }

    /// Scheduled Procedure Step Start Date (0040,0002) in YYYYMMDD format.
    public var scheduledProcedureStepStartDate: String? { stringValue(group: 0x0040, element: 0x0002) }

    /// Scheduled Procedure Step Start Time (0040,0003) in HHMMSS.FFFFFF format.
    public var scheduledProcedureStepStartTime: String? { stringValue(group: 0x0040, element: 0x0003) }

    /// Scheduled Procedure Step Status (0040,0020) — e.g. "SCHEDULED", "IN PROGRESS", "COMPLETED".
    public var scheduledProcedureStepStatus: String? { stringValue(group: 0x0040, element: 0x0020) }

    /// Scheduled Performing Physician's Name (0040,0006)
    public var scheduledPerformingPhysicianName: String? { stringValue(group: 0x0040, element: 0x0006) }

    /// Scheduled Procedure Step Description (0040,0007)
    public var scheduledProcedureStepDescription: String? { stringValue(group: 0x0040, element: 0x0007) }

    /// Scheduled Protocol Code Sequence (0040,0008) items
    public var scheduledProtocolCodes: [WorklistCodedEntry] { codedEntries(group: 0x0040, element: 0x0008) }

    /// Scheduled Procedure Step ID (0040,0009)
    public var scheduledProcedureStepID: String? { stringValue(group: 0x0040, element: 0x0009) }

    /// Scheduled Station Name (0040,0010)
    public var scheduledStationName: String? { stringValue(group: 0x0040, element: 0x0010) }

    /// Scheduled Procedure Step Location (0040,0011)
    public var scheduledProcedureStepLocation: String? { stringValue(group: 0x0040, element: 0x0011) }

    /// Pre-Medication (0040,0012)
    public var preMedication: String? { stringValue(group: 0x0040, element: 0x0012) }

    /// Requested Contrast Agent (0032,1070)
    public var requestedContrastAgent: String? { stringValue(group: 0x0032, element: 0x1070) }

    /// Modality (0008,0060) — e.g. "CT", "MR", "US".
    public var modality: String? { stringValue(group: 0x0008, element: 0x0060) }
}

#if canImport(Network)
import Network
// NEMA-verified: 2026a, checked 2026-10-06 — Scheduled Procedure Step Status (0040,0020) Defined Terms re-read from PS3.3 2026a Table C.4-10 (5: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED) for WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms / spsStatusWarning (D264); MWL FIND UID per PS3.4 2026a Table K.6.1.4-1; identifier keys and (0008,0005) rule per Tables K.6-1/K.6-1a, K.4.1.1.3.1 and C.2.2.2; response decoding per PS3.5 §6.1.2; Scheduled Station AE Title (0040,0001) Single Value Matching only per Table K.6-1 (wild cards refused, D81, 2026-10-01)

// MARK: - DICOM Modality Worklist Service

/// DICOM Modality Worklist Service (MWL C-FIND SCU)
///
/// Implements the DICOM Modality Worklist Information Model for querying
/// scheduled procedure steps from a worklist SCP.
///
/// Reference: PS3.4 Annex K - Modality Worklist Information Model
///
/// ## Usage
///
/// ```swift
/// // Query worklist for today
/// let items = try await DICOMModalityWorklistService.find(
///     host: "worklist.hospital.com",
///     port: 11112,
///     callingAE: "MODALITY",
///     calledAE: "WORKLIST_SCP",
///     matching: WorklistQueryKeys()
///         .scheduledDate("20240315")
///         .scheduledStationAET("CT1")
/// )
/// ```
public enum DICOMModalityWorklistService {
    
    /// Finds worklist items matching the specified query keys
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - matching: Query keys specifying match criteria (optional)
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - specificCharacterSet: forces (0008,0005) of the Identifier; nil (default)
    ///     chooses the narrowest set that represents every text key
    /// - Returns: Array of worklist items
    /// - Throws: `DICOMNetworkError` for connection or protocol errors,
    ///   ``WorklistDateFilterError/invalidStationAETitle(_:)`` for a bad station filter
    public static func find(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        matching: WorklistQueryKeys? = nil,
        timeout: TimeInterval = 60,
        specificCharacterSet: String? = nil
    ) async throws -> [WorklistItem] {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = ModalityWorklistConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            specificCharacterSet: specificCharacterSet
        )
        
        let queryKeys = matching ?? WorklistQueryKeys.default()
        
        return try await performFind(
            host: host,
            port: port,
            configuration: config,
            queryKeys: queryKeys
        )
    }
    
    // MARK: - Private Implementation
    
    /// Performs the C-FIND operation for worklist
    private static func performFind(
        host: String,
        port: UInt16,
        configuration: ModalityWorklistConfiguration,
        queryKeys: WorklistQueryKeys
    ) async throws -> [WorklistItem] {
        // Reject a malformed Scheduled Station AE Title before opening a connection.
        if let station = queryKeys.allSPSKeys[Tag(group: 0x0040, element: 0x0001)] {
            try WorklistQueryKeys.validateScheduledStationAETitle(station)
        }

        // Create association configuration
        let associationConfig = AssociationConfiguration(
            callingAETitle: configuration.callingAETitle,
            calledAETitle: configuration.calledAETitle,
            host: host,
            port: port,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            timeout: configuration.timeout,
            userIdentity: configuration.userIdentity
        )
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        // Create presentation context for MWL C-FIND
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: modalityWorklistInformationModelFindSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: [presentationContext])
            
            // Verify that the SOP Class was accepted
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(modalityWorklistInformationModelFindSOPClassUID)
            }
            
            // Get the accepted transfer syntax
            let acceptedTransferSyntax = negotiated.acceptedTransferSyntax(forContextID: 1) 
                ?? implicitVRLittleEndianTransferSyntaxUID
            
            // Perform the C-FIND query
            let results = try await performCFind(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                queryKeys: queryKeys,
                transferSyntax: acceptedTransferSyntax,
                specificCharacterSet: configuration.specificCharacterSet
            )
            
            // Release association gracefully
            try await association.release()
            
            return results
            
        } catch {
            // Attempt to abort the association on error
            try? await association.abort()
            throw error
        }
    }
    
    /// Performs the C-FIND request/response exchange
    private static func performCFind(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        queryKeys: WorklistQueryKeys,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) async throws -> [WorklistItem] {
        // Build the query identifier data set
        let identifierData = buildQueryIdentifier(
            queryKeys: queryKeys, transferSyntax: transferSyntax, specificCharacterSet: specificCharacterSet)
        
        // Create C-FIND request
        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: modalityWorklistInformationModelFindSOPClassUID,
            priority: .medium,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive responses
        var results: [WorklistItem] = []
        let assembler = MessageAssembler()
        
        while true {
            let responsePDU = try await association.receive()
            
            if let message = try assembler.addPDVs(from: responsePDU) {
                guard let findResponse = message.asCFindResponse() else {
                    throw DICOMNetworkError.decodingFailed(
                        "Expected C-FIND-RSP, got \(message.command?.description ?? "unknown")"
                    )
                }
                
                // Check the status
                let status = findResponse.status
                
                if status.isPending {
                    // Pending - parse the data set and add to results
                    if let dataSetData = message.dataSet {
                        let parsed = parseQueryResponse(data: dataSetData, transferSyntax: transferSyntax)
                        results.append(WorklistItem(attributes: parsed.attributes, sequences: parsed.sequences))
                    }
                } else if status.isSuccess {
                    // Success - query complete
                    break
                } else if status.isCancel {
                    // Cancelled - return what we have
                    break
                } else if status.isFailure {
                    // Failure
                    throw DICOMNetworkError.queryFailed(status)
                } else {
                    // Unknown status - treat as completion
                    break
                }
            }
        }
        
        return results
    }
    
    /// Builds the query identifier data set.
    ///
    /// The Specific Character Set (0008,0005) is chosen with
    /// `DIMSECharacterSet.choose(for:override:)` over every text-VR key
    /// (`specificCharacterSet` wins when given, then the keys' own override).
    /// It is emitted only when an expanded or replacement repertoire is used
    /// (PS3.4 K.4.1.1.3.1: "It shall not be included otherwise"; C.2.2.2:
    /// "Specific Character Set (0008,0005) shall not have a zero length
    /// value"), so with ISO 646 keys no (0008,0005) is written even if the key
    /// set carries it as an empty return key. Every PN / LO / SH / ST / LT /
    /// UT / UC value is encoded in the chosen set (PS3.5 6.1.2,
    /// PS3.4 C.2.2.2.1, K.6.1.2.2). Other VRs stay ISO 646.
    internal static func buildQueryIdentifier(
        queryKeys: WorklistQueryKeys,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) -> Data {
        var data = Data()
        let isExplicitVR = transferSyntax == explicitVRLittleEndianTransferSyntaxUID
        let charset = queryKeys.chooseCharacterSet(override: specificCharacterSet)

        // Determine which tags go at the top level and which go in the SPS sequence.
        // The SPS sequence tag (0040,0100) must appear in tag-number order relative to
        // the surrounding top-level attributes.
        var topKeys = queryKeys.allKeys
        if let chosen = charset.specificCharacterSet {
            topKeys[.specificCharacterSet] = chosen
        } else {
            // Default repertoire: (0008,0005) shall not be included, and never
            // with a zero-length value (PS3.4 C.2.2.2, K.4.1.1.3.1).
            topKeys.removeValue(forKey: .specificCharacterSet)
        }
        let topSorted   = topKeys.sorted { $0.key < $1.key }
        let spsSorted   = queryKeys.allSPSKeys.sorted { $0.key < $1.key }
        let spsSeqTag   = Tag(group: 0x0040, element: 0x0100)

        // Merge: emit top-level tags before (0040,0100), then the SPS sequence, then the rest.
        for (tag, value) in topSorted where tag < spsSeqTag {
            data.append(encodeElement(tag: tag, vr: determineVR(for: tag),
                                      value: value, explicit: isExplicitVR, charset: charset))
        }

        // Encode the SPS Sequence (0040,0100) with one item containing all SPS attributes.
        // Each PACS (including dcm4chee2) expects the SPS attributes nested here per PS3.4 Annex K.
        if !spsSorted.isEmpty {
            data.append(encodeSPSSequence(spsKeys: spsSorted, explicit: isExplicitVR, charset: charset))
        }

        // Remaining top-level tags after (0040,0100)
        for (tag, value) in topSorted where tag > spsSeqTag {
            data.append(encodeElement(tag: tag, vr: determineVR(for: tag),
                                      value: value, explicit: isExplicitVR, charset: charset))
        }

        return data
    }

    /// Encodes the Scheduled Procedure Step Sequence (0040,0100) with a single item.
    ///
    /// Uses undefined-length encoding for both the sequence and its item, terminated
    /// by explicit delimiter tags per PS3.5 §7.5.  This is the most widely supported
    /// format across PACS vendors including dcm4chee2.
    private static func encodeSPSSequence(spsKeys: [(key: Tag, value: String)],
                                           explicit: Bool,
                                           charset: DIMSECharacterSet) -> Data {
        // Build the item's attribute bytes first
        var itemData = Data()
        for (tag, value) in spsKeys {
            itemData.append(encodeElement(
                tag: tag,
                vr: determineSPSVR(for: tag),
                value: value,
                explicit: explicit,
                charset: charset
            ))
        }

        var data = Data()
        // (0040,0100) Scheduled Procedure Step Sequence — SQ
        data.append(le16mwl(0x0040)); data.append(le16mwl(0x0100))
        if explicit {
            data.append(contentsOf: [0x53, 0x51])   // "SQ"
            data.append(contentsOf: [0x00, 0x00])   // reserved
        }
        data.append(le32mwl(0xFFFFFFFF))             // undefined sequence length

        // Item (FFFE,E000) with undefined length
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])  // item tag LE
        data.append(le32mwl(0xFFFFFFFF))
        data.append(itemData)
        // Item delimiter (FFFE,E00D)
        data.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0])
        data.append(le32mwl(0x00000000))

        // Sequence delimiter (FFFE,E0DD)
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        data.append(le32mwl(0x00000000))

        return data
    }

    // MARK: - MWL little-endian helpers (file-private to avoid name collision)

    private static func le16mwl(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
    private static func le32mwl(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    /// Determines the VR for a top-level MWL query tag.
    private static func determineVR(for tag: Tag) -> VR {
        // First, try to look up the tag in the DICOM Dictionary
        if let entry = DataElementDictionary.lookup(tag: tag) {
            return entry.vr.first ?? .UN
        }
        // Fallback for common MWL tags not yet in dictionary
        switch tag {
        case .patientName:     return .PN
        case .patientID:       return .LO
        case .studyInstanceUID: return .UI
        case .accessionNumber: return .SH
        default:               return .LO
        }
    }

    /// Determines the VR for an attribute inside the SPS Sequence item.
    private static func determineSPSVR(for tag: Tag) -> VR {
        if let entry = DataElementDictionary.lookup(tag: tag) {
            return entry.vr.first ?? .UN
        }
        switch (tag.group, tag.element) {
        case (0x0008, 0x0060): return .CS  // Modality
        case (0x0040, 0x0001): return .AE  // Scheduled Station AE Title
        case (0x0040, 0x0002): return .DA  // Scheduled Procedure Step Start Date
        case (0x0040, 0x0003): return .TM  // Scheduled Procedure Step Start Time
        case (0x0040, 0x0006): return .PN  // Scheduled Performing Physician Name
        case (0x0040, 0x0007): return .LO  // Scheduled Procedure Step Description
        case (0x0040, 0x0009): return .SH  // Scheduled Procedure Step ID
        case (0x0040, 0x0010): return .SH  // Scheduled Station Name
        case (0x0040, 0x0020): return .CS  // Scheduled Procedure Step Status
        default:               return .LO
        }
    }
    
    /// Encodes a single data element for the query identifier.
    ///
    /// Text VRs (PN, LO, SH, ST, LT, UT, UC) are encoded with `charset`; every
    /// other VR is ISO 646. A value is never silently reduced to zero length: a
    /// non-ASCII character in a non-text VR falls back to UTF-8 bytes rather than
    /// turning the key into a Universal Match.
    private static func encodeElement(tag: Tag, vr: VR, value: String, explicit: Bool,
                                      charset: DIMSECharacterSet = DIMSECharacterSet(specificCharacterSet: nil)) -> Data {
        var data = Data()
        
        // Tag (4 bytes, little endian)
        var group = tag.group.littleEndian
        var element = tag.element.littleEndian
        data.append(Data(bytes: &group, count: 2))
        data.append(Data(bytes: &element, count: 2))
        
        // Prepare value data with padding
        var valueData: Data
        if WorklistQueryKeys.characterSetVRs.contains(vr) {
            valueData = charset.encode(value)
        } else {
            valueData = value.data(using: .ascii) ?? Data(value.utf8)
        }
        
        // Pad to even length per DICOM rules (PS3.5 Section 6.2)
        // DICOM requires all Value Fields to have even length
        if valueData.count % 2 != 0 {
            // Use space (0x20) padding for text VRs, null (0x00) for binary VRs
            // This is a DICOM-specific requirement to maintain alignment
            let paddingChar: UInt8 = (vr == .UI) ? 0x00 : (vr.isStringVR ? 0x20 : 0x00)
            valueData.append(paddingChar)
        }
        
        if explicit {
            // Explicit VR encoding
            // VR (2 bytes)
            if let vrBytes = vr.rawValue.data(using: .ascii) {
                data.append(vrBytes)
            } else {
                data.append(Data([0x55, 0x4E])) // "UN" fallback
            }
            
            // Check if VR uses 4-byte length
            if vr.uses32BitLength {
                // Reserved (2 bytes)
                data.append(Data([0x00, 0x00]))
                // Value Length (4 bytes)
                var length = UInt32(valueData.count).littleEndian
                data.append(Data(bytes: &length, count: 4))
            } else {
                // Value Length (2 bytes)
                var length = UInt16(valueData.count).littleEndian
                data.append(Data(bytes: &length, count: 2))
            }
        } else {
            // Implicit VR encoding
            // Value Length (4 bytes)
            var length = UInt32(valueData.count).littleEndian
            data.append(Data(bytes: &length, count: 4))
        }
        
        // Value
        data.append(valueData)
        
        return data
    }
    
    /// A parsed C-FIND response: root + SPS attributes flattened into `attributes`,
    /// every other sequence's items kept apart in `sequences`.
    internal struct MWLParsedDataSet {
        var attributes: [Tag: Data] = [:]
        var sequences: [Tag: [[Tag: Data]]] = [:]
    }

    /// The SPS sequence, whose single item is flattened into the root map.
    private static let spsSequenceTag = Tag(group: 0x0040, element: 0x0100)

    /// Parses the query response dataset. SPS-level attributes (from the `(0040,0100)`
    /// sequence) are merged into `attributes` because their tag numbers do not collide
    /// with top-level MWL attributes; any other sequence's items go to `sequences`.
    private static func parseQueryResponse(data: Data, transferSyntax: String) -> MWLParsedDataSet {
        var parsed = MWLParsedDataSet()
        var offset = 0
        let isExplicitVR = transferSyntax == explicitVRLittleEndianTransferSyntaxUID
        parseMWLDataSet(data: data, offset: &offset, end: data.count,
                        isExplicitVR: isExplicitVR, into: &parsed)
        return parsed
    }

    /// Flat-map variant kept for callers (and tests) that only need root + SPS attributes.
    internal static func parseMWLDataSet(
        data rawData: Data,
        offset: inout Int,
        end: Int,
        isExplicitVR: Bool,
        into out: inout [Tag: Data]
    ) {
        var parsed = MWLParsedDataSet(attributes: out)
        parseMWLDataSet(data: rawData, offset: &offset, end: end, isExplicitVR: isExplicitVR, into: &parsed)
        out = parsed.attributes
    }

    /// Recursively parses DICOM tags from `data[offset..<end]`, merging every root and
    /// SPS attribute into `out.attributes` and collecting other sequences' items into
    /// `out.sequences`. Returns early on `(FFFE,E00D)` / `(FFFE,E0DD)`.
    internal static func parseMWLDataSet(
        data rawData: Data,
        offset: inout Int,
        end: Int,
        isExplicitVR: Bool,
        into out: inout MWLParsedDataSet
    ) {
        // Indexing below is zero-based, which a Data slice (startIndex != 0) would
        // trap on, so rebase before parsing.
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        while offset + 4 <= end {
            let group   = UInt16(data[offset])     | (UInt16(data[offset + 1]) << 8)
            let element = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            let tag = Tag(group: group, element: element)
            offset += 4

            // Delimiter tags (sequence/item): 4-byte length field (always 0x00000000).
            if group == 0xFFFE {
                if offset + 4 <= data.count { offset += 4 }
                if element == 0xE00D || element == 0xE0DD { return }  // bubble up
                continue
            }

            var valueLength: UInt32
            var isSequence = false

            if isExplicitVR {
                guard offset + 2 <= data.count else { return }
                let vr = VR(rawValue: String(bytes: [data[offset], data[offset + 1]],
                                             encoding: .ascii) ?? "UN") ?? .UN
                isSequence = (vr == .SQ)
                offset += 2
                if vr.uses32BitLength {
                    guard offset + 6 <= data.count else { return }
                    offset += 2  // skip reserved 2 bytes
                    valueLength = UInt32(data[offset])     | (UInt32(data[offset + 1]) << 8)
                                | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
                    offset += 4
                } else {
                    guard offset + 2 <= data.count else { return }
                    valueLength = UInt32(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                    offset += 2
                }
            } else {
                guard offset + 4 <= data.count else { return }
                valueLength = UInt32(data[offset])     | (UInt32(data[offset + 1]) << 8)
                            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
                offset += 4
                // Implicit VR: the SPS sequence is always SQ; anything else the
                // dictionary says is SQ (code sequences, Referenced Study Sequence).
                isSequence = tag == spsSequenceTag
                    || (DataElementDictionary.lookup(tag: tag)?.vr.contains(.SQ) ?? false)
            }

            if isSequence {
                // The SPS item flattens into the root map; other sequences keep their
                // items apart so nested Code Values cannot overwrite each other.
                if tag == spsSequenceTag {
                    parseMWLSequenceItems(data: data, offset: &offset, isExplicitVR: isExplicitVR,
                                          into: &out, boundedEnd: valueLength == 0xFFFFFFFF ? nil
                                              : min(offset + Int(valueLength), data.count))
                } else {
                    var items: [[Tag: Data]] = []
                    parseMWLSequenceItemsSeparately(data: data, offset: &offset, isExplicitVR: isExplicitVR,
                                                    into: &items, boundedEnd: valueLength == 0xFFFFFFFF ? nil
                                                        : min(offset + Int(valueLength), data.count))
                    if !items.isEmpty { out.sequences[tag, default: []].append(contentsOf: items) }
                }
                continue
            }

            if valueLength == 0xFFFFFFFF {
                // Non-sequence undefined-length item: scan forward to next delimiter pair
                skipMWLUndefinedItem(data: data, offset: &offset)
            } else {
                guard offset + Int(valueLength) <= data.count else { return }
                out.attributes[tag] = data.subdata(in: offset ..< (offset + Int(valueLength)))
                offset += Int(valueLength)
            }
        }
    }

    /// Parses items within a sequence, recursing into each item's dataset and merging tags into `out`.
    /// Stops at `(FFFE,E0DD)` (sequence delimiter) or when `boundedEnd` is reached.
    private static func parseMWLSequenceItems(
        data: Data,
        offset: inout Int,
        isExplicitVR: Bool,
        into out: inout MWLParsedDataSet,
        boundedEnd: Int? = nil
    ) {
        let limit = boundedEnd ?? data.count
        while offset + 8 <= limit {
            let group      = UInt16(data[offset])     | (UInt16(data[offset + 1]) << 8)
            let element    = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            let itemLength = UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8)
                           | (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24)
            offset += 8

            guard group == 0xFFFE else { continue }
            if element == 0xE0DD { return }                            // sequence delimiter
            guard element == 0xE000 else { continue }                  // item tag
            if itemLength == 0xFFFFFFFF {
                // Undefined-length item — parse until (FFFE,E00D)
                parseMWLDataSet(data: data, offset: &offset, end: data.count,
                                isExplicitVR: isExplicitVR, into: &out)
            } else {
                let itemEnd = min(offset + Int(itemLength), data.count)
                parseMWLDataSet(data: data, offset: &offset, end: itemEnd,
                                isExplicitVR: isExplicitVR, into: &out)
                offset = itemEnd
            }
        }
        if let boundedEnd { offset = max(offset, boundedEnd) }
    }

    /// Like `parseMWLSequenceItems`, but each item becomes its own flat map (with
    /// its nested sequences flattened into it) instead of merging into the root.
    private static func parseMWLSequenceItemsSeparately(
        data: Data,
        offset: inout Int,
        isExplicitVR: Bool,
        into items: inout [[Tag: Data]],
        boundedEnd: Int? = nil
    ) {
        let limit = boundedEnd ?? data.count
        while offset + 8 <= limit {
            let group      = UInt16(data[offset])     | (UInt16(data[offset + 1]) << 8)
            let element    = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            let itemLength = UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8)
                           | (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24)
            offset += 8

            guard group == 0xFFFE else { continue }
            if element == 0xE0DD { return }
            guard element == 0xE000 else { continue }
            var item = MWLParsedDataSet()
            if itemLength == 0xFFFFFFFF {
                parseMWLDataSet(data: data, offset: &offset, end: data.count,
                                isExplicitVR: isExplicitVR, into: &item)
            } else {
                let itemEnd = min(offset + Int(itemLength), data.count)
                parseMWLDataSet(data: data, offset: &offset, end: itemEnd,
                                isExplicitVR: isExplicitVR, into: &item)
                offset = itemEnd
            }
            // Flatten the item's own nested sequences (e.g. a code's Context Group
            // Sequence) into the item map so nothing is lost.
            var flat = item.attributes
            for (_, nested) in item.sequences { for n in nested { flat.merge(n) { cur, _ in cur } } }
            items.append(flat)
        }
        if let boundedEnd { offset = max(offset, boundedEnd) }
    }

    /// Scans forward over an undefined-length non-sequence item to safely skip it.
    private static func skipMWLUndefinedItem(data: Data, offset: inout Int) {
        while offset + 8 <= data.count {
            let group   = UInt16(data[offset])     | (UInt16(data[offset + 1]) << 8)
            let element = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            offset += 8  // consume tag (4) + length (4)
            if group == 0xFFFE && (element == 0xE00D || element == 0xE0DD) { return }
        }
    }

    // MARK: - Create Worklist Item (REST API)

    /// Creates a new worklist item on a remote Worklist server via REST API.
    ///
    /// The DICOM standard (PS3.4 Annex K) defines the Modality Worklist
    /// Information Model as C-FIND only; N-CREATE is not supported for the
    /// MWL FIND SOP Class.  Modern PACS (dcm4chee-arc, Orthanc, etc.)
    /// expose REST endpoints for MWL item management instead.
    ///
    /// This method builds a DICOM JSON payload (PS3.18 Annex F) and POSTs
    /// it to the server's MWL management REST endpoint.
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104) — used only when no `restBaseURL` is given
    ///   - callingAE: The local AE title (informational for REST)
    ///   - calledAE: The remote AE title — used to construct the REST path when no explicit URL is given
    ///   - patientName: Patient's Name (0010,0010)
    ///   - patientID: Patient ID (0010,0020)
    ///   - patientBirthDate: Patient's Birth Date in YYYYMMDD (0010,0030)
    ///   - patientSex: Patient's Sex — M, F, O (0010,0040)
    ///   - accessionNumber: Accession Number (0008,0050)
    ///   - referringPhysicianName: Referring Physician's Name (0008,0090)
    ///   - requestedProcedureID: Requested Procedure ID (0040,1001)
    ///   - requestedProcedureDescription: Requested Procedure Description (0032,1060)
    ///   - studyInstanceUID: Study Instance UID (0020,000D) — auto-generated if nil
    ///   - modality: Modality, e.g. "CT", "MR" (0008,0060)
    ///   - scheduledStationAETitle: Scheduled Station AE Title (0040,0001)
    ///   - scheduledStationName: Scheduled Station Name (0040,0010)
    ///   - scheduledStartDate: Scheduled start date in YYYYMMDD (0040,0002)
    ///   - scheduledStartTime: Scheduled start time in HHMMSS (0040,0003)
    ///   - scheduledProcedureStepID: Scheduled Procedure Step ID (0040,0009)
    ///   - scheduledProcedureStepDescription: SPS Description (0040,0007)
    ///   - scheduledPerformingPhysicianName: Scheduled Performing Physician (0040,0006)
    ///   - restBaseURL: Full REST base URL, e.g. `http://host:8080/dcm4chee-arc`.
    ///     When nil, defaults to `http://{host}:8080/dcm4chee-arc`.
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: The SOP Instance UID of the created worklist item
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    ///
    /// Reference: PS3.4 Annex K — Modality Worklist Information Model
    public static func create(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        patientName: String,
        patientID: String,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        requestedProcedureID: String? = nil,
        requestedProcedureDescription: String? = nil,
        studyInstanceUID: String? = nil,
        modality: String? = nil,
        scheduledStationAETitle: String? = nil,
        scheduledStationName: String? = nil,
        scheduledStartDate: String? = nil,
        scheduledStartTime: String? = nil,
        scheduledProcedureStepID: String? = nil,
        scheduledProcedureStepDescription: String? = nil,
        scheduledPerformingPhysicianName: String? = nil,
        restBaseURL: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> String {
        let sopInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value

        // Build REST endpoint URL
        let baseURL = restBaseURL ?? "http://\(host):8080/dcm4chee-arc"
        let endpointString = "\(baseURL)/aets/\(calledAE)/rs/mwlitems"

        guard let endpointURL = URL(string: endpointString) else {
            throw DICOMNetworkError.connectionFailed(
                "Invalid MWL REST endpoint URL: \(endpointString)")
        }

        try await performRESTCreate(
            endpointURL: endpointURL,
            sopInstanceUID: sopInstanceUID,
            patientName: patientName,
            patientID: patientID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            accessionNumber: accessionNumber,
            referringPhysicianName: referringPhysicianName,
            requestedProcedureID: requestedProcedureID,
            requestedProcedureDescription: requestedProcedureDescription,
            modality: modality,
            scheduledStationAETitle: scheduledStationAETitle,
            scheduledStationName: scheduledStationName,
            scheduledStartDate: scheduledStartDate,
            scheduledStartTime: scheduledStartTime,
            scheduledProcedureStepID: scheduledProcedureStepID,
            scheduledProcedureStepDescription: scheduledProcedureStepDescription,
            scheduledPerformingPhysicianName: scheduledPerformingPhysicianName,
            timeout: timeout
        )

        return sopInstanceUID
    }

    // MARK: - REST Create Private Implementation

    /// Posts a DICOM JSON MWL item to the server's REST endpoint.
    private static func performRESTCreate(
        endpointURL: URL,
        sopInstanceUID: String,
        patientName: String,
        patientID: String,
        patientBirthDate: String?,
        patientSex: String?,
        accessionNumber: String?,
        referringPhysicianName: String?,
        requestedProcedureID: String?,
        requestedProcedureDescription: String?,
        modality: String?,
        scheduledStationAETitle: String?,
        scheduledStationName: String?,
        scheduledStartDate: String?,
        scheduledStartTime: String?,
        scheduledProcedureStepID: String?,
        scheduledProcedureStepDescription: String?,
        scheduledPerformingPhysicianName: String?,
        timeout: TimeInterval
    ) async throws {
        // Build DICOM JSON payload (PS3.18 Annex F)
        let jsonPayload = buildMWLCreateJSON(
            studyInstanceUID: sopInstanceUID,
            patientName: patientName,
            patientID: patientID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            accessionNumber: accessionNumber,
            referringPhysicianName: referringPhysicianName,
            requestedProcedureID: requestedProcedureID,
            requestedProcedureDescription: requestedProcedureDescription,
            modality: modality,
            scheduledStationAETitle: scheduledStationAETitle,
            scheduledStationName: scheduledStationName,
            scheduledStartDate: scheduledStartDate,
            scheduledStartTime: scheduledStartTime,
            scheduledProcedureStepID: scheduledProcedureStepID,
            scheduledProcedureStepDescription: scheduledProcedureStepDescription,
            scheduledPerformingPhysicianName: scheduledPerformingPhysicianName
        )

        let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMNetworkError.connectionFailed(
                "MWL REST create received non-HTTP response")
        }

        switch httpResponse.statusCode {
        case 200, 201, 202:
            return // Success
        case 401, 403:
            throw DICOMNetworkError.connectionFailed(
                "MWL REST create failed: Authentication required (HTTP \(httpResponse.statusCode)). " +
                "Configure credentials for the server's REST API.")
        case 404:
            throw DICOMNetworkError.connectionFailed(
                "MWL REST endpoint not found (HTTP 404). " +
                "Verify the REST base URL — default pattern is " +
                "http://<host>:8080/dcm4chee-arc/aets/<AET>/rs/mwlitems")
        case 409:
            throw DICOMNetworkError.connectionFailed(
                "MWL REST create conflict (HTTP 409): A worklist item with this UID may already exist.")
        default:
            throw DICOMNetworkError.connectionFailed(
                "MWL REST create failed with HTTP \(httpResponse.statusCode)")
        }
    }

    /// Builds a DICOM JSON dictionary (PS3.18 Annex F) for MWL item creation.
    internal static func buildMWLCreateJSON(
        studyInstanceUID: String,
        patientName: String,
        patientID: String,
        patientBirthDate: String?,
        patientSex: String?,
        accessionNumber: String?,
        referringPhysicianName: String?,
        requestedProcedureID: String?,
        requestedProcedureDescription: String?,
        modality: String?,
        scheduledStationAETitle: String?,
        scheduledStationName: String?,
        scheduledStartDate: String?,
        scheduledStartTime: String?,
        scheduledProcedureStepID: String?,
        scheduledProcedureStepDescription: String?,
        scheduledPerformingPhysicianName: String?
    ) -> [String: Any] {
        var json: [String: Any] = [:]

        // Specific Character Set (0008,0005)
        json["00080005"] = ["vr": "CS", "Value": ["ISO_IR 100"]]

        // Accession Number (0008,0050) — Type 2
        json["00080050"] = ["vr": "SH", "Value": [accessionNumber ?? ""]]

        // Referring Physician's Name (0008,0090) — Type 2
        if let ref = referringPhysicianName, !ref.isEmpty {
            json["00080090"] = ["vr": "PN", "Value": [["Alphabetic": ref]]]
        } else {
            json["00080090"] = ["vr": "PN"]
        }

        // Patient's Name (0010,0010) — Type 1
        json["00100010"] = ["vr": "PN", "Value": [["Alphabetic": patientName]]]

        // Patient ID (0010,0020) — Type 1
        json["00100020"] = ["vr": "LO", "Value": [patientID]]

        // Patient's Birth Date (0010,0030) — Type 2
        json["00100030"] = ["vr": "DA", "Value": [patientBirthDate ?? ""]]

        // Patient's Sex (0010,0040) — Type 2
        json["00100040"] = ["vr": "CS", "Value": [patientSex ?? ""]]

        // Study Instance UID (0020,000D) — Type 1
        json["0020000D"] = ["vr": "UI", "Value": [studyInstanceUID]]

        // Requested Procedure Description (0032,1060) — Type 2
        json["00321060"] = ["vr": "LO", "Value": [requestedProcedureDescription ?? ""]]

        // --- Scheduled Procedure Step Sequence (0040,0100) ---
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let defaultDate = dateFormatter.string(from: Date())

        var spsItem: [String: Any] = [:]

        // Scheduled Station AE Title (0040,0001)
        spsItem["00400001"] = ["vr": "AE", "Value": [scheduledStationAETitle ?? ""]]

        // Scheduled Procedure Step Start Date (0040,0002) — Type 1
        spsItem["00400002"] = ["vr": "DA", "Value": [scheduledStartDate ?? defaultDate]]

        // Scheduled Procedure Step Start Time (0040,0003)
        if let time = scheduledStartTime, !time.isEmpty {
            spsItem["00400003"] = ["vr": "TM", "Value": [time]]
        }

        // Scheduled Performing Physician's Name (0040,0006) — Type 2
        if let perf = scheduledPerformingPhysicianName, !perf.isEmpty {
            spsItem["00400006"] = ["vr": "PN", "Value": [["Alphabetic": perf]]]
        } else {
            spsItem["00400006"] = ["vr": "PN"]
        }

        // Scheduled Procedure Step Description (0040,0007) — Type 2
        spsItem["00400007"] = ["vr": "LO", "Value": [scheduledProcedureStepDescription ?? ""]]

        // Modality (0008,0060) within SPS — Type 1
        spsItem["00080060"] = ["vr": "CS", "Value": [modality ?? "OT"]]

        // Scheduled Procedure Step ID (0040,0009) — Type 1
        spsItem["00400009"] = ["vr": "SH", "Value": [scheduledProcedureStepID ?? "SPS001"]]

        // Scheduled Station Name (0040,0010) — Type 2
        spsItem["00400010"] = ["vr": "SH", "Value": [scheduledStationName ?? ""]]

        // Scheduled Procedure Step Status (0040,0020) — default SCHEDULED
        spsItem["00400020"] = ["vr": "CS", "Value": ["SCHEDULED"]]

        json["00400100"] = ["vr": "SQ", "Value": [spsItem]]

        // Requested Procedure ID (0040,1001) — Type 1
        json["00401001"] = ["vr": "SH", "Value": [requestedProcedureID ?? ""]]

        return json
    }

    // MARK: - Create Worklist Item via HL7 (ORM^O01 over MLLP)

    /// Creates a new worklist item by sending an HL7 ORM^O01 order message
    /// to the server via MLLP (Minimum Lower Layer Protocol).
    ///
    /// Unlike REST-based creation, the HL7 ORM^O01 message causes the
    /// receiving system (e.g. dcm4chee-arc, Mirth Connect) to **automatically
    /// create the patient record and the worklist item** in one step.
    ///
    /// - Parameters:
    ///   - host: The HL7 server hostname or IP address
    ///   - hl7Port: The HL7 MLLP port (default: 2575)
    ///   - sendingApplication: MSH-3 Sending Application (default: "DICOMSTUDIO")
    ///   - sendingFacility: MSH-4 Sending Facility (default: "IMAGING")
    ///   - receivingApplication: MSH-5 Receiving Application (default: "DCM4CHEE")
    ///   - receivingFacility: MSH-6 Receiving Facility (default: "HOSPITAL")
    ///   - patientName: Patient's Name in HL7 format (Last^First)
    ///   - patientID: Patient ID
    ///   - patientBirthDate: Patient's Birth Date in YYYYMMDD
    ///   - patientSex: Patient's Sex — M, F, O
    ///   - accessionNumber: Accession Number
    ///   - referringPhysicianName: Referring Physician's Name (Last^First)
    ///   - requestedProcedureID: Requested Procedure ID
    ///   - requestedProcedureDescription: Requested Procedure Description
    ///   - studyInstanceUID: Study Instance UID — auto-generated if nil
    ///   - modality: Modality, e.g. "CT", "MR"
    ///   - scheduledStationAETitle: Scheduled Station AE Title
    ///   - scheduledStationName: Scheduled Station Name
    ///   - scheduledStartDate: Scheduled start date in YYYYMMDD
    ///   - scheduledStartTime: Scheduled start time in HHMMSS
    ///   - scheduledProcedureStepID: Scheduled Procedure Step ID
    ///   - scheduledProcedureStepDescription: SPS Description
    ///   - scheduledPerformingPhysicianName: Scheduled Performing Physician (Last^First)
    ///   - timeout: Connection timeout in seconds (default: 30)
    /// - Returns: The message control ID of the sent HL7 message
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func createViaHL7(
        host: String,
        hl7Port: UInt16 = 2575,
        sendingApplication: String = "DICOMSTUDIO",
        sendingFacility: String = "IMAGING",
        receivingApplication: String = "DCM4CHEE",
        receivingFacility: String = "HOSPITAL",
        patientName: String,
        patientID: String,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        requestedProcedureID: String? = nil,
        requestedProcedureDescription: String? = nil,
        studyInstanceUID: String? = nil,
        modality: String? = nil,
        scheduledStationAETitle: String? = nil,
        scheduledStationName: String? = nil,
        scheduledStartDate: String? = nil,
        scheduledStartTime: String? = nil,
        scheduledProcedureStepID: String? = nil,
        scheduledProcedureStepDescription: String? = nil,
        scheduledPerformingPhysicianName: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let messageControlID = generateHL7MessageControlID()
        let studyUID = studyInstanceUID ?? UIDGenerator.generateUID().value

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let resolvedDate = scheduledStartDate ?? dateFormatter.string(from: Date())

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMddHHmmss"
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = timestampFormatter.string(from: Date())

        let resolvedTime = scheduledStartTime ?? ""
        let scheduledDateTime = resolvedTime.isEmpty ? resolvedDate : "\(resolvedDate)\(resolvedTime)"

        // Build HL7 ORM^O01 message
        let ormMessage = buildHL7ORM(
            messageControlID: messageControlID,
            timestamp: timestamp,
            sendingApplication: sendingApplication,
            sendingFacility: sendingFacility,
            receivingApplication: receivingApplication,
            receivingFacility: receivingFacility,
            patientName: patientName,
            patientID: patientID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            accessionNumber: accessionNumber ?? "",
            referringPhysicianName: referringPhysicianName,
            requestedProcedureID: requestedProcedureID ?? "RP001",
            requestedProcedureDescription: requestedProcedureDescription ?? "",
            studyInstanceUID: studyUID,
            modality: modality ?? "OT",
            scheduledStationAETitle: scheduledStationAETitle ?? "",
            scheduledStationName: scheduledStationName ?? "",
            scheduledDateTime: scheduledDateTime,
            scheduledProcedureStepID: scheduledProcedureStepID ?? "SPS001",
            scheduledProcedureStepDescription: scheduledProcedureStepDescription ?? "",
            scheduledPerformingPhysicianName: scheduledPerformingPhysicianName
        )

        // Send via MLLP and receive ACK
        let ack = try await sendHL7ViaMLLP(
            message: ormMessage,
            host: host,
            port: hl7Port,
            timeout: timeout
        )

        // Parse ACK — expect MSA|AA or MSA|CA for success
        guard let ackCode = parseHL7AckCode(ack) else {
            throw DICOMNetworkError.connectionFailed(
                "HL7 response missing MSA segment or unreadable")
        }

        switch ackCode {
        case "AA", "CA":
            return messageControlID
        case "AE":
            let errorText = parseHL7AckErrorText(ack) ?? "Application error"
            throw DICOMNetworkError.connectionFailed(
                "HL7 ORM rejected (AE): \(errorText)")
        case "AR":
            let errorText = parseHL7AckErrorText(ack) ?? "Application reject"
            throw DICOMNetworkError.connectionFailed(
                "HL7 ORM rejected (AR): \(errorText)")
        default:
            throw DICOMNetworkError.connectionFailed(
                "HL7 unexpected ACK code: \(ackCode)")
        }
    }

    // MARK: - HL7 ORM^O01 Message Builder

    /// Builds an HL7 v2.5 ORM^O01 order message for MWL creation.
    ///
    /// Segments: MSH, PID, PV1, ORC, OBR, IPC, ZDS
    ///
    /// Field placement follows dcm4chee-arc's DEFAULT inbound order stylesheet
    /// `hl7-order2dcm.xsl` (the modern successor to `hl7-orm2dcm.xsl`), which builds the
    /// Scheduled Procedure Step Sequence (0040,0100) along one of two mutually-exclusive
    /// paths:
    ///
    /// * **IPC path** — when an `IPC` (Imaging Procedure Control, dcm4che private) segment
    ///   is present, every SPS attribute is read directly from a dedicated IPC field
    ///   (SPS ID ← IPC-4, Modality ← IPC-5, SPS Description ← IPC-6, Station Name ← IPC-7,
    ///   **Station AE Title ← IPC-9**), and Accession/Requested-Procedure-ID/Study-UID come
    ///   from IPC-1/IPC-2/IPC-3. This is the only path that can carry Scheduled Station AE
    ///   Title and Scheduled Station Name, and it does so independent of server config.
    /// * **ZDS/OBR fallback** — with no IPC segment, the SPS item is built from the OBR:
    ///   **SPS ID ← OBR-20** (Filler Field 1, `$obr/field[20]`), Modality ← OBR-24,
    ///   Accession ← OBR-18, Requested Procedure ID ← OBR-19. (Earlier revisions wrote the
    ///   Station AE Title into OBR-20, so the server ingested it as the SPS ID — fixed here.)
    ///
    /// We emit BOTH: the `IPC` segment so a default dcm4chee-arc maps every field correctly,
    /// and a correctly-aligned OBR as the fallback for receivers that key off the OBR/ZDS
    /// path. The `ZDS` segment carries the Study Instance UID for DICOM-aware receivers.
    ///
    /// - Note: `internal` (not `private`) so the field-placement regression test can assert
    ///   each value lands at its exact HL7 position without a live MLLP server.
    static func buildHL7ORM(
        messageControlID: String,
        timestamp: String,
        sendingApplication: String,
        sendingFacility: String,
        receivingApplication: String,
        receivingFacility: String,
        patientName: String,
        patientID: String,
        patientBirthDate: String?,
        patientSex: String?,
        accessionNumber: String,
        referringPhysicianName: String?,
        requestedProcedureID: String,
        requestedProcedureDescription: String,
        studyInstanceUID: String,
        modality: String,
        scheduledStationAETitle: String,
        scheduledStationName: String,
        scheduledDateTime: String,
        scheduledProcedureStepID: String,
        scheduledProcedureStepDescription: String,
        scheduledPerformingPhysicianName: String?
    ) -> String {
        let cr = "\r"

        // MSH — Message Header
        var msg = "MSH|^~\\&"
        msg += "|\(sendingApplication)"
        msg += "|\(sendingFacility)"
        msg += "|\(receivingApplication)"
        msg += "|\(receivingFacility)"
        msg += "|\(timestamp)"
        msg += "|"                        // Security
        msg += "|ORM^O01^ORM_O01"         // Message Type
        msg += "|\(messageControlID)"     // Message Control ID
        msg += "|P"                       // Processing ID
        msg += "|2.5"                     // Version ID
        msg += cr

        // PID — Patient Identification
        msg += "PID"
        msg += "||"                       // PID-1: Set ID (empty)
        msg += "\(patientID)"             // PID-2: Patient ID (External)
        msg += "|\(patientID)"            // PID-3: Patient Identifier List
        msg += "|"                        // PID-4: Alternate Patient ID
        msg += "|\(patientName)"          // PID-5: Patient Name (Last^First)
        msg += "|"                        // PID-6: Mother's Maiden Name
        msg += "|\(patientBirthDate ?? "")" // PID-7: Date of Birth
        msg += "|\(patientSex ?? "")"     // PID-8: Sex
        msg += cr

        // PV1 — Patient Visit
        msg += "PV1"
        msg += "||O"                      // PV1-2: Patient Class (O=Outpatient)
        msg += cr

        // ORC — Common Order
        msg += "ORC"
        msg += "|NW"                      // ORC-1: Order Control (NW = New order)
        msg += "|\(accessionNumber)"      // ORC-2: Placer Order Number
        msg += "|"                        // ORC-3: Filler Order Number
        msg += "|"                        // ORC-4: Placer Group Number
        msg += "|SC"                      // ORC-5: Order Status (SC = Scheduled)
        msg += cr

        // OBR — Observation Request. Built from an explicit field-index→value map so each
        // value lands at its exact HL7 position (manual pipe-counting is what previously
        // shifted Station AET into the SPS-ID slot). Indices match dcm4chee-arc's default
        // `hl7-order2dcm.xsl` ZDS/OBR fallback path:
        //   OBR-18 → Accession Number (0008,0050)         [Placer Field 1]
        //   OBR-19 → Requested Procedure ID (0040,1001)    [Placer Field 2]
        //   OBR-20 → Scheduled Procedure Step ID (0040,0009) [Filler Field 1, $obr/field[20]]
        //   OBR-24 → Modality (0008,0060)
        //   OBR-27 → Scheduled Procedure Step Start Date/Time (4th component, $obr/field[27]/component[3])
        //   OBR-34 → Scheduled Performing Physician's Name (0040,0006)
        //   OBR-44 → Requested Procedure Description (0032,1060) via the procedure code's text component
        // Scheduled Station AE Title / Station Name have NO OBR slot in this default — they
        // travel in the IPC segment below.
        var obrFields: [Int: String] = [
            1: "1",                                                          // Set ID
            2: accessionNumber,                                             // Placer Order Number
            4: "\(requestedProcedureID)^\(requestedProcedureDescription)",  // Universal Service Identifier (code^text)
            7: scheduledDateTime,                                           // Observation Date/Time (informational)
            16: referringPhysicianName ?? "",                               // Ordering Provider → Requesting Physician (0032,1032)
            18: accessionNumber,                                            // Placer Field 1 → Accession Number (0008,0050)
            19: requestedProcedureID,                                       // Placer Field 2 → Requested Procedure ID (0040,1001)
            20: scheduledProcedureStepID,                                   // Filler Field 1 → Scheduled Procedure Step ID (0040,0009)
            24: modality,                                                   // Diagnostic Serv Sect ID → Modality (0008,0060)
            27: "^^^\(scheduledDateTime)",                                  // Quantity/Timing, 4th comp → SPS Start Date/Time (0040,0002/0003)
            44: "\(requestedProcedureID)^\(requestedProcedureDescription)"  // Procedure Code → Requested Procedure Description (0032,1060)
        ]
        if let performer = scheduledPerformingPhysicianName, !performer.isEmpty {
            obrFields[34] = performer                                       // Technician slot → Scheduled Performing Physician's Name (0040,0006)
        }
        msg += hl7Segment("OBR", fields: obrFields) + cr

        // IPC — Imaging Procedure Control (dcm4che private segment). When present, dcm4chee-arc's
        // default stylesheet builds the Scheduled Procedure Step Sequence directly from IPC fields,
        // giving every SPS attribute an unambiguous, configuration-independent slot — including the
        // Scheduled Station AE Title (IPC-9) and Scheduled Station Name (IPC-7), which the bare
        // ORM/OBR path cannot carry. IPC-1/2/3 also override Accession / Requested Procedure ID /
        // Study Instance UID, so the worklist item matches the OBR fallback exactly.
        var ipcFields: [Int: String] = [
            1: accessionNumber,            // Accession Number (0008,0050)
            2: requestedProcedureID,       // Requested Procedure ID (0040,1001)
            3: studyInstanceUID,           // Study Instance UID (0020,000D)
            4: scheduledProcedureStepID,   // Scheduled Procedure Step ID (0040,0009)
            5: modality,                   // Modality (0008,0060)
            7: scheduledStationName,       // Scheduled Station Name (0040,0010)
            9: scheduledStationAETitle     // Scheduled Station AE Title (0040,0001)
        ]
        if !scheduledProcedureStepDescription.isEmpty {
            // SPS Description (0040,0007) is read from IPC-6's text component (2nd component);
            // leave the code (1st component) empty so no spurious protocol code is created.
            ipcFields[6] = "^\(scheduledProcedureStepDescription)"
        }
        msg += hl7Segment("IPC", fields: ipcFields) + cr

        // ZDS — Study Instance UID (custom Z-segment, dcm4chee convention)
        msg += "ZDS"
        msg += "|\(studyInstanceUID)^100^Application^DICOM"
        msg += cr

        return msg
    }

    /// Builds an HL7 segment string from a 1-based field-index→value map.
    ///
    /// The segment name is followed by fields `1...maxIndex` joined by the field separator
    /// `|`; any index absent from `fields` is emitted as an empty field. Placing each value
    /// by explicit index (rather than counting pipe separators by hand) keeps high-numbered
    /// fields — e.g. OBR-20, OBR-44, IPC-9 — at exactly their intended HL7 position.
    /// MSH is built separately because MSH-1 *is* the field separator.
    private static func hl7Segment(_ name: String, fields: [Int: String]) -> String {
        guard let maxIndex = fields.keys.max(), maxIndex >= 1 else { return name }
        var parts = [name]
        parts.reserveCapacity(maxIndex + 1)
        for i in 1...maxIndex { parts.append(fields[i] ?? "") }
        return parts.joined(separator: "|")
    }

    // MARK: - MLLP Transport

    /// Sends an HL7 message via MLLP and returns the ACK response.
    ///
    /// MLLP framing:
    ///   - Start block: 0x0B (VT)
    ///   - End block:   0x1C 0x0D (FS + CR)
    static func sendHL7ViaMLLP(
        message: String,
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) async throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw DICOMNetworkError.connectionFailed("Failed to encode HL7 message as UTF-8")
        }

        // Frame the message in MLLP: 0x0B + message + 0x1C 0x0D
        let framedData = Data([0x0B]) + messageData + Data([0x1C, 0x0D])

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DICOMNetworkError.connectionFailed("Invalid HL7 port: \(port)")
        }

        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = MLLPContinuationGuard(continuation)

            // Timeout
            nonisolated(unsafe) let timeoutTask = DispatchWorkItem { [weak connection] in
                guard !resumed.hasResumed else { return }
                connection?.cancel()
                resumed.resume(with: .failure(
                    DICOMNetworkError.timeout))
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutTask
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Connected — send the MLLP-framed message
                    connection.send(content: framedData, completion: .contentProcessed { error in
                        if let error = error {
                            timeoutTask.cancel()
                            resumed.resume(with: .failure(
                                DICOMNetworkError.connectionFailed(
                                    "HL7 MLLP send failed: \(error.localizedDescription)")))
                            connection.cancel()
                            return
                        }

                        // Receive the ACK response
                        connection.receive(minimumIncompleteLength: 1,
                                           maximumLength: 65536) { data, _, _, recvError in
                            timeoutTask.cancel()
                            defer { connection.cancel() }

                            if let recvError = recvError {
                                resumed.resume(with: .failure(
                                    DICOMNetworkError.connectionFailed(
                                        "HL7 MLLP receive failed: \(recvError.localizedDescription)")))
                                return
                            }

                            guard let data = data, !data.isEmpty else {
                                resumed.resume(with: .failure(
                                    DICOMNetworkError.connectionClosed))
                                return
                            }

                            // Strip MLLP framing from the response
                            var responseData = data
                            if responseData.first == 0x0B {
                                responseData = responseData.dropFirst()
                            }
                            if responseData.count >= 2,
                               responseData[responseData.endIndex - 2] == 0x1C,
                               responseData[responseData.endIndex - 1] == 0x0D {
                                responseData = responseData.dropLast(2)
                            }

                            guard let ackString = String(data: responseData, encoding: .utf8) else {
                                resumed.resume(with: .failure(
                                    DICOMNetworkError.connectionFailed(
                                        "HL7 ACK response not valid UTF-8")))
                                return
                            }

                            resumed.resume(with: .success(ackString))
                        }
                    })

                case .failed(let error):
                    timeoutTask.cancel()
                    resumed.resume(with: .failure(
                        DICOMNetworkError.connectionFailed(
                            "HL7 MLLP connection failed: \(error.localizedDescription)")))

                case .cancelled:
                    timeoutTask.cancel()
                    resumed.resume(with: .failure(
                        DICOMNetworkError.connectionClosed))

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - HL7 ACK Parsing Helpers

    /// Extracts the ACK code from an HL7 ACK/NAK message (MSA-1).
    /// Returns "AA", "AE", "AR", "CA", "CE", "CR", or nil if not found.
    static func parseHL7AckCode(_ ack: String) -> String? {
        for line in ack.split(separator: "\r") {
            let str = String(line)
            if str.hasPrefix("MSA|") || str.hasPrefix("MSA\u{7C}") {
                let fields = str.split(separator: "|", omittingEmptySubsequences: false)
                if fields.count >= 2 {
                    return String(fields[1])
                }
            }
        }
        return nil
    }

    /// Extracts the error text from an HL7 ACK message (MSA-3 or ERR segment).
    static func parseHL7AckErrorText(_ ack: String) -> String? {
        for line in ack.split(separator: "\r") {
            let str = String(line)
            if str.hasPrefix("MSA|") {
                let fields = str.split(separator: "|", omittingEmptySubsequences: false)
                if fields.count >= 4 {
                    let text = String(fields[3])
                    if !text.isEmpty { return text }
                }
            }
            if str.hasPrefix("ERR|") {
                let fields = str.split(separator: "|", omittingEmptySubsequences: false)
                if fields.count >= 2 {
                    return String(fields[1])
                }
            }
        }
        return nil
    }

    /// Generates a unique HL7 message control ID.
    static func generateHL7MessageControlID() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = UInt32.random(in: 1000...9999)
        return "MSG\(timestamp)\(random)"
    }
}

/// Thread-safe continuation guard to ensure the continuation is resumed exactly once.
private final class MLLPContinuationGuard: @unchecked Sendable {
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()
    private(set) var hasResumed = false

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed, let cont = continuation else { return }
        hasResumed = true
        continuation = nil
        cont.resume(with: result)
    }
}

#endif
