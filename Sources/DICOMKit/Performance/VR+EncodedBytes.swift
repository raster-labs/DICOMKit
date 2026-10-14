// NEMA-verified: 2026a, checked 2026-10-14 — exact byte projection of the maintained VR cases.
import DICOMCore

extension VR {
    /// Decode the existing two-byte VR vocabulary without allocating a String.
    static func fromEncodedBytes(_ first: UInt8, _ second: UInt8) -> VR? {
        switch UInt16(first) << 8 | UInt16(second) {
        case 0x4145: return .AE
        case 0x4153: return .AS
        case 0x4154: return .AT
        case 0x4353: return .CS
        case 0x4441: return .DA
        case 0x4453: return .DS
        case 0x4454: return .DT
        case 0x4644: return .FD
        case 0x464C: return .FL
        case 0x4953: return .IS
        case 0x4C4F: return .LO
        case 0x4C54: return .LT
        case 0x4F42: return .OB
        case 0x4F44: return .OD
        case 0x4F46: return .OF
        case 0x4F4C: return .OL
        case 0x4F56: return .OV
        case 0x4F57: return .OW
        case 0x504E: return .PN
        case 0x5348: return .SH
        case 0x534C: return .SL
        case 0x5351: return .SQ
        case 0x5353: return .SS
        case 0x5354: return .ST
        case 0x5356: return .SV
        case 0x544D: return .TM
        case 0x5543: return .UC
        case 0x5549: return .UI
        case 0x554C: return .UL
        case 0x554E: return .UN
        case 0x5552: return .UR
        case 0x5553: return .US
        case 0x5554: return .UT
        case 0x5556: return .UV
        default: return nil
        }
    }
}
