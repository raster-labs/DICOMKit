/// Value Representation (VR) enumeration
///
/// Defines all 34 Value Representations from DICOM PS3.5 2026d Table 6.2-1,
/// including the 64-bit OV, SV and UV representations added by CP 1819 (2019a).
/// Each VR specifies the data type and format of a DICOM data element value.
///
/// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed against PS3.5 2026a (frozen): the
/// 34 cases match Table 6.2-1, and `uses32BitLength` matches §7.1.2 / Tables 7.1-1 and 7.1-2
/// (21 VRs with a 16-bit length, 13 with a 32-bit length); OV/SV/UV provenance: CP 1819 (2019a).
/// NEMA-verified: 2026d, checked 2026-09-24 — the same comparison against PS3.5 2026d (NEMA
/// `/current/`, subtitle "PS3.5 2026d"; no frozen 2026d copy is published yet) also matches.
///
/// Reference: DICOM PS3.5 Section 6.2 - Value Representation (VR)
public enum VR: String, Sendable, Hashable, CaseIterable {
    // String VRs
    /// Application Entity (PS3.5 Section 6.2)
    case AE
    /// Age String (PS3.5 Section 6.2)
    case AS
    /// Code String (PS3.5 Section 6.2)
    case CS
    /// Date (PS3.5 Section 6.2)
    case DA
    /// Decimal String (PS3.5 Section 6.2)
    case DS
    /// Date Time (PS3.5 Section 6.2)
    case DT
    /// Integer String (PS3.5 Section 6.2)
    case IS
    /// Long String (PS3.5 Section 6.2)
    case LO
    /// Long Text (PS3.5 Section 6.2)
    case LT
    /// Person Name (PS3.5 Section 6.2)
    case PN
    /// Short String (PS3.5 Section 6.2)
    case SH
    /// Short Text (PS3.5 Section 6.2)
    case ST
    /// Time (PS3.5 Section 6.2)
    case TM
    /// Unlimited Characters (PS3.5 Section 6.2)
    case UC
    /// Unique Identifier (UID) (PS3.5 Section 6.2)
    case UI
    /// Unlimited Text (PS3.5 Section 6.2)
    case UT
    
    // Binary VRs
    /// Attribute Tag (PS3.5 Section 6.2)
    case AT
    /// Floating Point Single (PS3.5 Section 6.2)
    case FL
    /// Floating Point Double (PS3.5 Section 6.2)
    case FD
    /// Other Byte (PS3.5 Section 6.2)
    case OB
    /// Other Double (PS3.5 Section 6.2)
    case OD
    /// Other Float (PS3.5 Section 6.2)
    case OF
    /// Other Long (PS3.5 Section 6.2)
    case OL
    /// Other 64-bit Very Long (PS3.5 Section 6.2): a stream of 64-bit words
    /// whose encoding is specified by the Transfer Syntax, e.g. Extended Offset
    /// Table (7FE0,0001) and Extended Offset Table Lengths (7FE0,0002)
    case OV
    /// Other Word (PS3.5 Section 6.2)
    case OW
    /// Signed Long (PS3.5 Section 6.2)
    case SL
    /// Sequence of Items (PS3.5 Section 6.2)
    case SQ
    /// Signed Short (PS3.5 Section 6.2)
    case SS
    /// Signed 64-bit Very Long (PS3.5 Section 6.2)
    case SV
    /// Unsigned Long (PS3.5 Section 6.2)
    case UL
    /// Unknown (PS3.5 Section 6.2)
    case UN
    /// Universal Resource Identifier or Universal Resource Locator (URI/URL) (PS3.5 Section 6.2)
    case UR
    /// Unsigned Short (PS3.5 Section 6.2)
    case US
    /// Unsigned 64-bit Very Long (PS3.5 Section 6.2)
    case UV
    
    /// Indicates whether this VR uses a 32-bit length field in Explicit VR encoding
    ///
    /// Per PS3.5 Section 7.1.2 Table 7.1-1, most VRs use a 16-bit length field, but
    /// OB, OD, OF, OL, OV, OW, SQ, SV, UC, UN, UR, UT and UV are encoded with two
    /// reserved bytes followed by a 32-bit length field.
    public var uses32BitLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV:
            return true
        default:
            return false
        }
    }
    
    /// Character repertoire for string-based VRs
    ///
    /// Reference: PS3.5 Section 6.1.2 - Character Repertoires
    public var characterRepertoire: CharacterRepertoire? {
        switch self {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .TM, .UI, .UR:
            return .defaultRepertoire
        case .LO, .LT, .PN, .SH, .ST, .UC, .UT:
            return .extendedOrReplacement
        default:
            return nil
        }
    }
}

/// Character repertoire constraints for DICOM string VRs
///
/// Reference: PS3.5 Section 6.1.2
public enum CharacterRepertoire: Sendable, Hashable {
    /// Default Character Repertoire (ISO 646, basic ASCII subset)
    case defaultRepertoire
    /// Extended or Replacement Character Repertoires (controlled by Specific Character Set)
    case extendedOrReplacement
}
