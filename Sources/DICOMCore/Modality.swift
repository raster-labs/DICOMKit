import Foundation

/// DICOM Modality (0008,0060) — the equipment or technique that produced the data.
///
/// Reference: DICOM PS3.3 C.7.3.1.1.1 (Modality, General Series Module) and
/// PS3.16 CID 29 (Acquisition Modality), 2026a.
///
/// ## Why a struct and not an enum
///
/// Modality is a *Defined Term*, not an Enumerated Value: PS3.3 permits values
/// outside the published list, and real-world data contains private and
/// vendor-specific codes. An enum would force every parse site to either drop
/// an unrecognized code or trap on it. ``init(unchecked:)`` instead round-trips
/// any legal CS value losslessly while ``isStandard`` reports the truth about it.
///
/// ```swift
/// Modality("CT")?.name            // "Computed Tomography"
/// Modality("ST")?.isRetired       // true  — SPECT, retired by the standard
/// Modality(unchecked: "ACME").isStandard  // false — private code, preserved
/// Modality.normalized("MRI")      // Modality.mr — alias resolution
/// ```
public struct Modality: RawRepresentable, Hashable, Sendable, Codable,
                        CustomStringConvertible, ExpressibleByStringLiteral {

    /// The Code String value as it appears in (0008,0060), uppercased and trimmed.
    public let rawValue: String

    /// Creates a modality from a known code, or returns `nil`.
    ///
    /// The value is uppercased and trimmed before lookup, so `" ct "` yields
    /// ``Modality/ct``. Aliases are *not* resolved here — use ``normalized(_:)``
    /// for that. Retired codes succeed: they are known, just not current.
    ///
    /// - Parameter rawValue: A DICOM modality code, e.g. `"CT"`.
    public init?(rawValue: String) {
        let code = Self.canonicalize(rawValue)
        guard Self.definitions[code] != nil else { return nil }
        self.rawValue = code
    }

    /// Creates a modality from any value, including codes not in the standard.
    ///
    /// Use this on the parse path, where dropping an unrecognized private code
    /// would lose data. ``isStandard`` returns `false` for such values and
    /// ``name`` falls back to the code itself.
    ///
    /// - Parameter rawValue: Any Code String value from (0008,0060).
    public init(unchecked rawValue: String) {
        self.rawValue = Self.canonicalize(rawValue)
    }

    /// Creates a modality from a string literal, without validation.
    ///
    /// Literals are written by us, not parsed from data, so an unknown code here
    /// is a typo to be caught by tests rather than a runtime condition to handle.
    public init(stringLiteral value: String) {
        self.init(unchecked: value)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(unchecked: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Uppercases and trims a raw value to its canonical CS form.
    ///
    /// PS3.5 6.2 makes leading and trailing spaces non-significant in a CS, and
    /// the defined terms are uppercase, so this is the comparison form.
    private static func canonicalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - Attributes

    /// The human-readable meaning, e.g. `"Computed Tomography"`.
    ///
    /// Falls back to ``rawValue`` for codes outside the standard, so unknown
    /// private codes display as themselves rather than as "Unknown".
    public var name: String {
        Self.definitions[rawValue]?.name ?? rawValue
    }

    /// Whether the standard has retired this code.
    ///
    /// Retired codes still appear in legacy data, so they parse and display
    /// normally; they are excluded from pickers and flagged by validation.
    public var isRetired: Bool {
        Self.definitions[rawValue]?.isRetired ?? false
    }

    /// Whether this is a Defined Term in PS3.3 C.7.3.1.1.1.
    ///
    /// `false` for private codes and for the conventional-but-undefined codes
    /// ``sc`` and ``vl`` (see ``Category/nonStandard``).
    public var isStandard: Bool {
        guard let definition = Self.definitions[rawValue] else { return false }
        return definition.category != .nonStandard
    }

    /// Whether this code is current: standard and not retired.
    public var isCurrent: Bool { isStandard && !isRetired }

    /// The broad family this modality belongs to.
    ///
    /// Grouping is what lets UI handle 80 codes without 80 hand-picked icons,
    /// and lets presets and colors fall back per family rather than per code.
    public var category: Category {
        Self.definitions[rawValue]?.category ?? .other
    }

    // MARK: - Category

    /// Broad families of modality, for grouping and fallback behavior.
    public enum Category: String, CaseIterable, Sendable, Hashable, Codable {
        /// Cross-sectional tomographic imaging: CT, MR, PT, NM.
        case crossSectional
        /// Projection X-ray: CR, DX, RG, MG, PX, IO, XA, RF, BMD.
        case radiography
        /// Ultrasound, including intravascular and bone densitometry.
        case ultrasound
        /// Visible-light and endoscopic imaging: ES, GM, SM, XC, DMS.
        case visibleLight
        /// Ophthalmic imaging and measurement: OP, OPT, OCT, KER, LEN, …
        case ophthalmic
        /// Physiological waveforms: ECG, EEG, EMG, EPS, HD, RESP, AU.
        case waveform
        /// Radiotherapy objects: RTPLAN, RTDOSE, RTSTRUCT, RTIMAGE, …
        case radiotherapy
        /// Derived, secondary and non-image objects: SR, PR, KO, SEG, REG, DOC, …
        case derived
        /// In use but not a Defined Term: SC, VL.
        case nonStandard
        /// Everything else, including unrecognized private codes.
        case other

        /// A display label for the category.
        public var name: String {
            switch self {
            case .crossSectional: return "Cross-Sectional"
            case .radiography: return "Radiography"
            case .ultrasound: return "Ultrasound"
            case .visibleLight: return "Visible Light"
            case .ophthalmic: return "Ophthalmic"
            case .waveform: return "Waveform"
            case .radiotherapy: return "Radiotherapy"
            case .derived: return "Derived / Non-Image"
            case .nonStandard: return "Non-Standard"
            case .other: return "Other"
            }
        }
    }

    // MARK: - Definition table

    private struct Definition {
        let name: String
        let category: Category
        var isRetired: Bool = false
    }

    /// Every code this type recognizes, keyed by canonical Code String.
    private static let definitions: [String: Definition] = {
        var table: [String: Definition] = [:]
        for entry in currentEntries {
            table[entry.0] = Definition(name: entry.1, category: entry.2)
        }
        for entry in retiredEntries {
            table[entry.0] = Definition(name: entry.1, category: entry.2, isRetired: true)
        }
        return table
    }()

    /// Current Defined Terms, plus the two conventional non-standard codes,
    /// in the order pickers should display them.
    ///
    /// Source: PS3.3 C.7.3.1.1.1, 2026a.
    ///
    /// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed: codes match PS3.3 2026a C.7.3.1.1.1
    /// exactly (79 Defined Terms, 18 Retired); every code in PS3.16 CID 29 and CID 32 is
    /// present. SC and VL appear in neither. Display names are ours, not the standard's.
    private static let currentEntries: [(String, String, Category)] = [
        // Cross-sectional
        ("CT", "Computed Tomography", .crossSectional),
        ("MR", "Magnetic Resonance", .crossSectional),
        ("NM", "Nuclear Medicine", .crossSectional),
        ("PT", "Positron Emission Tomography", .crossSectional),
        ("CTPROTOCOL", "CT Protocol (Performed)", .crossSectional),

        // Radiography
        ("CR", "Computed Radiography", .radiography),
        ("DX", "Digital Radiography", .radiography),
        ("RG", "Radiographic Imaging", .radiography),
        ("MG", "Mammography", .radiography),
        ("PX", "Panoramic X-Ray", .radiography),
        ("IO", "Intra-Oral Radiography", .radiography),
        ("XA", "X-Ray Angiography", .radiography),
        ("RF", "Radiofluoroscopy", .radiography),
        ("BMD", "Bone Densitometry (X-Ray)", .radiography),
        ("XAPROTOCOL", "XA Protocol (Performed)", .radiography),

        // Ultrasound
        ("US", "Ultrasound", .ultrasound),
        ("IVUS", "Intravascular Ultrasound", .ultrasound),
        ("BDUS", "Bone Densitometry (Ultrasound)", .ultrasound),

        // Visible light / microscopy
        ("ES", "Endoscopy", .visibleLight),
        ("GM", "General Microscopy", .visibleLight),
        ("SM", "Slide Microscopy", .visibleLight),
        ("CFM", "Confocal Microscopy", .visibleLight),
        ("XC", "External-Camera Photography", .visibleLight),
        ("DMS", "Dermoscopy", .visibleLight),
        ("STAIN", "Automated Slide Stainer", .visibleLight),

        // Ophthalmic
        ("OP", "Ophthalmic Photography", .ophthalmic),
        ("OPT", "Ophthalmic Tomography", .ophthalmic),
        ("OPTENF", "Ophthalmic Tomography En Face", .ophthalmic),
        ("OPTBSV", "Ophthalmic Tomography B-scan Volume Analysis", .ophthalmic),
        ("OPM", "Ophthalmic Mapping", .ophthalmic),
        ("OAM", "Ophthalmic Axial Measurements", .ophthalmic),
        ("OPV", "Ophthalmic Visual Field", .ophthalmic),
        ("OCT", "Optical Coherence Tomography (non-Ophthalmic)", .ophthalmic),
        ("IVOCT", "Intravascular Optical Coherence Tomography", .ophthalmic),
        ("AR", "Autorefraction", .ophthalmic),
        ("KER", "Keratometry", .ophthalmic),
        ("LEN", "Lensometry", .ophthalmic),
        ("SRF", "Subjective Refraction", .ophthalmic),
        ("VA", "Visual Acuity", .ophthalmic),
        ("IOL", "Intraocular Lens Data", .ophthalmic),

        // Waveform
        ("ECG", "Electrocardiography", .waveform),
        ("EEG", "Electroencephalography", .waveform),
        ("EMG", "Electromyography", .waveform),
        ("EOG", "Electrooculography", .waveform),
        ("EPS", "Cardiac Electrophysiology", .waveform),
        ("HD", "Hemodynamic Waveform", .waveform),
        ("RESP", "Respiratory Waveform", .waveform),
        ("AU", "Audio", .waveform),

        // Radiotherapy
        ("RTIMAGE", "Radiotherapy Image", .radiotherapy),
        ("RTDOSE", "Radiotherapy Dose", .radiotherapy),
        ("RTSTRUCT", "Radiotherapy Structure Set", .radiotherapy),
        ("RTPLAN", "Radiotherapy Plan", .radiotherapy),
        ("RTRECORD", "RT Treatment Record", .radiotherapy),
        ("RTINTENT", "Radiotherapy Intent", .radiotherapy),
        ("RTRAD", "RT Radiation", .radiotherapy),
        ("RTSEGANN", "Radiotherapy Segment Annotation", .radiotherapy),

        // Derived / non-image
        ("SR", "SR Document", .derived),
        ("PR", "Presentation State", .derived),
        ("KO", "Key Object Selection", .derived),
        ("SEG", "Segmentation", .derived),
        ("REG", "Registration", .derived),
        ("RWV", "Real World Value Map", .derived),
        ("ANN", "Annotation", .derived),
        ("FID", "Fiducials", .derived),
        ("DOC", "Document", .derived),
        ("M3D", "Model for 3D Manufacturing", .derived),
        ("PLAN", "Plan", .derived),
        ("ASMT", "Content Assessment Results", .derived),
        ("SMR", "Stereometric Relationship", .derived),
        ("TEXTUREMAP", "Texture Map", .derived),
        ("HC", "Hard Copy", .derived),
        ("POS", "Position Sensor", .derived),

        // Other current defined terms
        ("OT", "Other", .other),
        ("BI", "Biomagnetic Imaging", .other),
        ("DG", "Diaphanography", .other),
        ("LS", "Laser Surface Scan", .other),
        ("OSS", "Optical Surface Scan", .other),
        ("PA", "Photoacoustic", .other),
        ("TG", "Thermography", .other),

        // In widespread use, but NOT Defined Terms — see Category.nonStandard.
        //
        // "SC" is not merely unlisted: PS3.3 C.8.6.1 makes Modality Type 3 on the
        // Secondary Capture IOD and says the value "is intended to describe the
        // equipment that originally created or generated the data, not the
        // equipment performing the digitization or capture" — so a digitized film
        // radiograph should carry CR/XA, not SC. Verified absent from PS3.3
        // C.7.3.1.1.1 and from CID 32 (Non-Acquisition Modality), 2026a.
        //
        // "VL" names the Visible Light SOP class family, not a modality; the real
        // codes are ES, GM, SM, XC and friends.
        //
        // Both are recognized so existing files still parse and display, and both
        // are kept out of allCases so nothing new is written with them.
        ("SC", "Secondary Capture", .nonStandard),
        ("VL", "Visible Light", .nonStandard),
    ]

    /// Codes the standard has retired. Recognized for legacy data, never offered.
    private static let retiredEntries: [(String, String, Category)] = [
        ("AS", "Angioscopy", .visibleLight),
        ("CD", "Color Flow Doppler", .ultrasound),
        ("CF", "Cinefluorography", .radiography),
        ("CP", "Culposcopy", .visibleLight),
        ("CS", "Cystoscopy", .visibleLight),
        ("DD", "Duplex Doppler", .ultrasound),
        ("DF", "Digital Fluoroscopy", .radiography),
        ("DM", "Digital Microscopy", .visibleLight),
        ("DS", "Digital Subtraction Angiography", .radiography),
        ("EC", "Echocardiography", .ultrasound),
        ("FA", "Fluorescein Angiography", .ophthalmic),
        ("FS", "Fundoscopy", .ophthalmic),
        ("LP", "Laparoscopy", .visibleLight),
        ("MA", "Magnetic Resonance Angiography", .crossSectional),
        ("MS", "Magnetic Resonance Spectroscopy", .crossSectional),
        ("OPR", "Ophthalmic Refraction", .ophthalmic),
        ("ST", "Single-Photon Emission Computed Tomography", .crossSectional),
        ("VF", "Videofluorography", .radiography),
    ]

    // MARK: - Collections

    /// Every current code — standard and not retired — in display order.
    ///
    /// This excludes ``sc`` and ``vl``, which are recognized but not offered.
    public static let allCases: [Modality] = currentEntries
        .filter { $0.2 != .nonStandard }
        .map { Modality(unchecked: $0.0) }

    /// Every recognized code: current, non-standard conventional, and retired.
    public static let allIncludingRetired: [Modality] =
        currentEntries.map { Modality(unchecked: $0.0) }
        + retiredEntries.map { Modality(unchecked: $0.0) }

    /// Current codes grouped by category, in display order.
    ///
    /// Pickers use this so an 80-item list stays navigable.
    public static let groupedByCategory: [(category: Category, modalities: [Modality])] = {
        var order: [Category] = []
        var groups: [Category: [Modality]] = [:]
        for modality in allCases {
            let category = modality.category
            if groups[category] == nil { order.append(category) }
            groups[category, default: []].append(modality)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }()

    // MARK: - Alias resolution

    /// Non-standard spellings mapped onto the code they mean.
    ///
    /// This is the single alias table for the whole project. `RT` is here
    /// because it was never a DICOM code — it stood in for the eight real
    /// `RT*` codes, and resolves to ``rtimage`` for continuity with data
    /// written before those were distinguished.
    private static let aliases: [String: String] = [
        "MRI": "MR",
        "PET": "PT",
        "PDF": "DOC",
        "RT": "RTIMAGE",
        "XR": "DX",
        "DR": "DX",
        "SPECT": "NM",
    ]

    /// Resolves a raw value — including aliases — to a recognized modality.
    ///
    /// Use this wherever a value arrives from outside: user input, HL7, a
    /// filename. Returns `nil` only when the value is neither a known code
    /// nor a known alias.
    ///
    /// - Parameter raw: Any modality spelling, e.g. `"mri"`, `"PET"`, `"CT"`.
    public static func normalized(_ raw: String) -> Modality? {
        let code = canonicalize(raw)
        if let modality = Modality(rawValue: code) { return modality }
        guard let target = aliases[code] else { return nil }
        return Modality(rawValue: target)
    }

    // MARK: - Enhanced multi-frame helpers

    /// Whether the Enhanced IOD's Frame Type descriptive attributes apply.
    ///
    /// PS3.3 C.8.13.1 / C.8.16.1 attach Pixel Presentation, Volumetric Properties
    /// and Volume Based Calculation Technique to the Enhanced CT, MR and PET
    /// families. Shared by `FunctionalGroupBuilder` and `FrameMerger`, which
    /// previously each carried their own `["CT","MR","PT"]` literal.
    public var usesEnhancedFrameTypeDescriptors: Bool {
        self == .ct || self == .mr || self == .pt
    }

    // MARK: - Named constants

    public static let ct: Modality = "CT"
    public static let mr: Modality = "MR"
    public static let nm: Modality = "NM"
    public static let pt: Modality = "PT"
    public static let ctprotocol: Modality = "CTPROTOCOL"

    public static let cr: Modality = "CR"
    public static let dx: Modality = "DX"
    public static let rg: Modality = "RG"
    public static let mg: Modality = "MG"
    public static let px: Modality = "PX"
    public static let io: Modality = "IO"
    public static let xa: Modality = "XA"
    public static let rf: Modality = "RF"
    public static let bmd: Modality = "BMD"
    public static let xaprotocol: Modality = "XAPROTOCOL"

    public static let us: Modality = "US"
    public static let ivus: Modality = "IVUS"
    public static let bdus: Modality = "BDUS"

    public static let es: Modality = "ES"
    public static let gm: Modality = "GM"
    public static let sm: Modality = "SM"
    public static let cfm: Modality = "CFM"
    public static let xc: Modality = "XC"
    public static let dms: Modality = "DMS"
    public static let stain: Modality = "STAIN"

    public static let op: Modality = "OP"
    public static let opt: Modality = "OPT"
    public static let optenf: Modality = "OPTENF"
    public static let optbsv: Modality = "OPTBSV"
    public static let opm: Modality = "OPM"
    public static let oam: Modality = "OAM"
    public static let opv: Modality = "OPV"
    public static let oct: Modality = "OCT"
    public static let ivoct: Modality = "IVOCT"
    public static let ar: Modality = "AR"
    public static let ker: Modality = "KER"
    public static let len: Modality = "LEN"
    public static let srf: Modality = "SRF"
    public static let va: Modality = "VA"
    public static let iol: Modality = "IOL"

    public static let ecg: Modality = "ECG"
    public static let eeg: Modality = "EEG"
    public static let emg: Modality = "EMG"
    public static let eog: Modality = "EOG"
    public static let eps: Modality = "EPS"
    public static let hd: Modality = "HD"
    public static let resp: Modality = "RESP"
    public static let au: Modality = "AU"

    public static let rtimage: Modality = "RTIMAGE"
    public static let rtdose: Modality = "RTDOSE"
    public static let rtstruct: Modality = "RTSTRUCT"
    public static let rtplan: Modality = "RTPLAN"
    public static let rtrecord: Modality = "RTRECORD"
    public static let rtintent: Modality = "RTINTENT"
    public static let rtrad: Modality = "RTRAD"
    public static let rtsegann: Modality = "RTSEGANN"

    public static let sr: Modality = "SR"
    public static let pr: Modality = "PR"
    public static let ko: Modality = "KO"
    public static let seg: Modality = "SEG"
    public static let reg: Modality = "REG"
    public static let rwv: Modality = "RWV"
    public static let ann: Modality = "ANN"
    public static let fid: Modality = "FID"
    public static let doc: Modality = "DOC"
    public static let m3d: Modality = "M3D"
    public static let plan: Modality = "PLAN"
    public static let asmt: Modality = "ASMT"
    public static let smr: Modality = "SMR"
    public static let texturemap: Modality = "TEXTUREMAP"
    public static let hc: Modality = "HC"
    public static let pos: Modality = "POS"

    public static let ot: Modality = "OT"
    public static let bi: Modality = "BI"
    public static let dg: Modality = "DG"
    public static let ls: Modality = "LS"
    public static let oss: Modality = "OSS"
    public static let pa: Modality = "PA"
    public static let tg: Modality = "TG"

    /// Secondary Capture — conventional, not a Defined Term.
    public static let sc: Modality = "SC"
    /// Visible Light — conventional, not a Defined Term.
    public static let vl: Modality = "VL"
}
