import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — the 16 named codes and their class text-diffed against PS3.7 2026a Annex C and PS3.4 2026a Tables B.2-1, C.4-1..C.4-3, K.4-1, F.7.2-2, F.8.2-2 (Scripts/diff_network.py): 16 of 16 match; `description` uses the 2026a names verbatim (A900 "Error: Data Set does not match SOP Class" per C.4-1 / K.4-1, 0110 "Processing Failure" per PS3.7 C.5.21, A701/A702 "Refused: Out of resources" C.5.5, A801 "Refused: Move Destination unknown" C.5.4, B000/B006/B007 per B.2-1) and names every other code PS3.7 Annex C fixes (24 sections, via DIMSEServiceStatusText) — D73, D79, D82; unnamed codes classified by range

/// DIMSE Status Codes
///
/// Status codes returned in DIMSE response messages indicating the result of an operation.
///
/// Reference: PS3.7 Annex C - Status Type Encoding
public enum DIMSEStatus: Sendable, Hashable {
    // MARK: - General Status Categories
    
    /// Operation completed successfully (0x0000)
    case success
    
    /// Pending - More matches/results to follow (0xFF00, 0xFF01)
    case pending(warningOptionalKeys: Bool)
    
    /// Cancel - Operation was cancelled (0xFE00)
    case cancel
    
    // MARK: - Failure Status
    
    /// Refused - Out of resources (0xA700)
    case refusedOutOfResources
    
    /// Refused - SOP Class not supported (0x0122)
    case refusedSOPClassNotSupported
    
    /// Error: Data Set does not match SOP Class (0xA900) — PS3.4 Tables C.4-1..C.4-3,
    /// K.4-1; PS3.7 C.5.2. (The case name predates the 2026a wording.)
    case errorIdentifierDoesNotMatchSOPClass
    
    /// Failed - Unable to process / Error - Cannot understand (0xC000-0xCFFF)
    ///
    /// PS3.4 Table B.2-1 (C-STORE) names the Cxxx range "Error: Cannot
    /// understand"; Tables C.4-1/C.4-2/C.4-3 (C-FIND/C-MOVE/C-GET) and K.4-1
    /// (Modality Worklist) name it "Failed: Unable to process".
    case errorCannotUnderstand(UInt16)
    
    /// Processing Failure (0x0110) — PS3.7 C.5.21. (The case name predates the 2026a wording;
    /// "Failed: Unable to process" is the Cxxx row of PS3.4 Tables C.4-1..C.4-3 / K.4-1.)
    case failedUnableToProcess
    
    /// Duplicate SOP Instance (0x0111) — PS3.7 C.5.8
    case failedDuplicateSOPInstance
    
    /// No such SOP Class (0x0118) — PS3.7 C.5.20
    case failedNoSuchSOPClass
    
    /// No such SOP Instance (0x0112) — PS3.7 C.5.19
    case failedNoSuchSOPInstance
    
    /// Resource limitation (0x0213) — PS3.7 C.5.22
    case failedResourceLimitation
    
    /// Refused: Out of resources (0xA701, 0xA702) — PS3.4 Tables C.4-2 / C.4-3; PS3.7 C.5.5
    case failedOutOfResources(UInt16)
    
    /// Refused: Move Destination unknown (0xA801) — PS3.4 Table C.4-2; PS3.7 C.5.4
    case failedMoveDestinationUnknown
    
    // MARK: - Warning Status
    
    /// Warning - Coercion of data elements or sub-operations complete with warnings (0xB000)
    /// Used for both coercion warnings and C-GET/C-MOVE sub-operation warnings
    case warningCoercionOfDataElements
    
    /// Warning - Data set does not match SOP Class (0xB007)
    case warningDataSetDoesNotMatchSOPClass
    
    /// Warning - Elements discarded (0xB006)
    case warningElementsDiscarded
    
    // MARK: - Other/Unknown
    
    /// A status code without a case of its own. ``description`` names it from
    /// PS3.7 Annex C when Annex C fixes the code (e.g. 0x0106 "Invalid Attribute
    /// Value", 0x0117 "Invalid SOP Instance", 0x0210 "Duplicate invocation");
    /// use ``description(for:)`` for the service-specific PS3.4 wording.
    case unknown(UInt16)
    
    /// The raw 16-bit status code value
    public var rawValue: UInt16 {
        switch self {
        case .success:
            return 0x0000
        case .pending(let warningOptionalKeys):
            return warningOptionalKeys ? 0xFF01 : 0xFF00
        case .cancel:
            return 0xFE00
        case .refusedOutOfResources:
            return 0xA700
        case .refusedSOPClassNotSupported:
            return 0x0122
        case .errorIdentifierDoesNotMatchSOPClass:
            return 0xA900
        case .errorCannotUnderstand(let code):
            return code
        case .failedUnableToProcess:
            return 0x0110
        case .failedDuplicateSOPInstance:
            return 0x0111
        case .failedNoSuchSOPClass:
            return 0x0118
        case .failedNoSuchSOPInstance:
            return 0x0112
        case .failedResourceLimitation:
            return 0x0213
        case .failedOutOfResources(let code):
            return code
        case .failedMoveDestinationUnknown:
            return 0xA801
        case .warningCoercionOfDataElements:
            return 0xB000
        case .warningDataSetDoesNotMatchSOPClass:
            return 0xB007
        case .warningElementsDiscarded:
            return 0xB006
        case .unknown(let code):
            return code
        }
    }
    
    /// Creates a DIMSEStatus from a raw status code value
    ///
    /// - Parameter rawValue: The 16-bit status code
    /// - Returns: The corresponding DIMSEStatus
    public static func from(_ rawValue: UInt16) -> DIMSEStatus {
        switch rawValue {
        case 0x0000:
            return .success
        case 0xFF00:
            return .pending(warningOptionalKeys: false)
        case 0xFF01:
            return .pending(warningOptionalKeys: true)
        case 0xFE00:
            return .cancel
        case 0x0110:
            return .failedUnableToProcess
        case 0x0111:
            return .failedDuplicateSOPInstance
        case 0x0112:
            return .failedNoSuchSOPInstance
        case 0x0118:
            return .failedNoSuchSOPClass
        case 0x0122:
            return .refusedSOPClassNotSupported
        case 0x0213:
            return .failedResourceLimitation
        case 0xA700:
            return .refusedOutOfResources
        case 0xA701, 0xA702:
            return .failedOutOfResources(rawValue)
        case 0xA801:
            return .failedMoveDestinationUnknown
        case 0xA900:
            return .errorIdentifierDoesNotMatchSOPClass
        case 0xB000:
            return .warningCoercionOfDataElements
        case 0xB006:
            return .warningElementsDiscarded
        case 0xB007:
            return .warningDataSetDoesNotMatchSOPClass
        case 0xC000...0xCFFF:
            return .errorCannotUnderstand(rawValue)
        default:
            // The C-STORE ranges of PS3.4 Table B.2-1 — 0xA7xx "Refused: Out of
            // resources" other than 0xA700/0xA701/0xA702, and 0xA9xx "Error:
            // Data Set does not match SOP Class" other than 0xA900 — have no
            // case of their own (mapping them to the named cases would lose
            // the code) and fall to `.unknown`; `isFailure` classifies them as
            // failures by the 0xA000-0xAFFF range rule.
            return .unknown(rawValue)
        }
    }
    
    /// Whether this is a success status
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Whether this status indicates the operation succeeded (success or warning).
    /// Warnings mean the SCP completed the operation, possibly with corrected values.
    public var isSuccessOrWarning: Bool {
        isSuccess || isWarning
    }
    
    /// Whether this is a pending status (more results to follow)
    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
    
    /// Whether this is a failure status
    public var isFailure: Bool {
        switch self {
        case .refusedOutOfResources, .refusedSOPClassNotSupported,
             .errorIdentifierDoesNotMatchSOPClass, .errorCannotUnderstand,
             .failedUnableToProcess, .failedDuplicateSOPInstance,
             .failedNoSuchSOPClass, .failedNoSuchSOPInstance,
             .failedResourceLimitation, .failedOutOfResources,
             .failedMoveDestinationUnknown:
            return true
        case .unknown(let code):
            // 0xA000-0xAFFF are failures (PS3.7 Annex C, "Refused"/"Error").
            // 0x0001 is the warning "Requested optional Attributes are not
            // supported" (PS3.4 Table F.8.2-2, MPPS Retrieve N-GET).
            // PS3.7 Annex C defines no status codes in 0x0002-0x00FF; an
            // unknown code there is treated as a failure as a safe policy,
            // not because the standard classifies it.
            //
            // 0x0100-0x0FFF is the DIMSE-N failure block (PS3.7 Annex C:
            // 0x0105 no such attribute, 0x0106 invalid attribute value,
            // 0x0110 processing failure, 0x0112 no such SOP Instance,
            // 0x0117 invalid object instance, 0x0120 missing attribute …),
            // minus the two warnings carved out in `isWarning`.
            if code == 0x0001 { return false }
            if code >= 0x0001 && code <= 0x00FF { return true }
            if code >= 0x0100 && code <= 0x0FFF { return !Self.dimseNWarningCodes.contains(code) }
            return code >= 0xA000 && code <= 0xAFFF
        default:
            return false
        }
    }

    /// DIMSE-N status codes in the 0x01xx block that are warnings, not failures.
    ///
    /// Reference: PS3.7 Annex C — 0x0107 Attribute List Error, 0x0116 Attribute
    /// Value Out of Range. Everything else in the block is a failure; in
    /// particular **0x0106 (Invalid Attribute Value) is a failure**, and treating
    /// it as a warning made an SCU sail past a printer's rejection of, say, an
    /// unsupported Medium Type and fail confusingly two operations later.
    private static let dimseNWarningCodes: Set<UInt16> = [0x0107, 0x0116]

    /// Whether this is a warning status
    public var isWarning: Bool {
        switch self {
        case .warningCoercionOfDataElements, .warningDataSetDoesNotMatchSOPClass,
             .warningElementsDiscarded:
            return true
        case .unknown(let code):
            // 0xB000-0xBFFF are warnings, plus the DIMSE-N warnings
            // 0x0001 (optional attributes not supported), 0x0107 (attribute
            // list error) and 0x0116 (attribute value out of range).
            return (code >= 0xB000 && code <= 0xBFFF)
                || code == 0x0001
                || Self.dimseNWarningCodes.contains(code)
        default:
            return false
        }
    }
    
    /// Whether this is a cancel status
    public var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }
    
    /// Whether this status indicates the operation is complete (not pending)
    public var isFinal: Bool {
        !isPending
    }
}

// MARK: - CustomStringConvertible
extension DIMSEStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success:
            return "Success (0x0000)"
        case .pending(let warningOptionalKeys):
            let code = warningOptionalKeys ? "0xFF01" : "0xFF00"
            return "Pending (\(code))"
        case .cancel:
            return "Cancel (0xFE00)"
        case .refusedOutOfResources:
            return "Refused: Out of resources (0xA700)"
        case .refusedSOPClassNotSupported:
            return "Refused: SOP Class not supported (0x0122)"
        case .errorIdentifierDoesNotMatchSOPClass:
            return "Error: Data Set does not match SOP Class (0xA900)"
        case .errorCannotUnderstand(let code):
            return "Failed: unable to process / cannot understand (Cxxx) (0x\(String(format: "%04X", code)))"
        case .failedUnableToProcess:
            return "Processing Failure (0x0110)"
        case .failedDuplicateSOPInstance:
            return "Duplicate SOP Instance (0x0111)"
        case .failedNoSuchSOPClass:
            return "No such SOP Class (0x0118)"
        case .failedNoSuchSOPInstance:
            return "No such SOP Instance (0x0112)"
        case .failedResourceLimitation:
            return "Resource limitation (0x0213)"
        case .failedOutOfResources(let code):
            return "Refused: Out of resources (0x\(String(format: "%04X", code)))"
        case .failedMoveDestinationUnknown:
            return "Refused: Move Destination unknown (0xA801)"
        case .warningCoercionOfDataElements:
            return "Warning: Coercion of Data Elements (0xB000)"
        case .warningDataSetDoesNotMatchSOPClass:
            return "Warning: Data Set does not match SOP Class (0xB007)"
        case .warningElementsDiscarded:
            return "Warning: Elements Discarded (0xB006)"
        case .unknown(let code):
            if let general = DIMSEServiceStatusText.annexCRow(for: code) {
                return "\(general.name) (0x\(String(format: "%04X", code)))"
            }
            return "Unknown status (0x\(String(format: "%04X", code)))"
        }
    }
}
