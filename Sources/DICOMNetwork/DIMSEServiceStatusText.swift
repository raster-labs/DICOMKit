import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — generated from the DocBook by Scripts/nema_docbook.py (scratchpad gen_status.py) and carried verbatim: the 31 rows of PS3.4 2026a Tables B.2-1 (C-STORE, 7), C.4-1 (C-FIND, 7), C.4-2 (C-MOVE, 9) and C.4-3 (C-GET, 8); K.4-1 (MWL C-FIND, 7); F.7.2-2 (MPPS N-SET, 1, with Error ID A710) and F.8.2-2 (MPPS N-GET, 1); the 7 Print Management tables H.4.1.2.1.2-1 (2), H.4-4 (10), H.4.2.2.1.2-1 (3), H.4-9 (8), H.4.3.1.2.1.2-1 (8), H.4.3.2.2.1.2-1 (6), H.4.9.2.1.2-1 (2); and the 24 PS3.7 2026a Annex C sections that fix a code (C.1.1, C.3.1, C.4.2-C.4.3, C.5.6-C.5.25, section titles verbatim). The sub-operation counter names are those of PS3.7 2026a Tables 9.3-7 / 9.3-10. Hoisted from the dicom-retrieve / dicom-qr RetrieveStatusText copies (P-QR-STATUS-TEXT, D76); DIMSE-N, MWL, MPPS and Print tables added for D73, D79, D82, D91, D93.

/// The DIMSE service (and, for the DIMSE-N services, the SOP Class) whose
/// response status is being described. The same status code means different
/// things per service (PS3.4 Annex B / C / F / H / K): 0xB000 is "Coercion of
/// Data Elements" for C-STORE but "Sub-operations Complete - One or more
/// Failures" for C-MOVE; 0xB604 is worded differently by the Film Box and the
/// Image Box tables.
public enum DIMSEStatusService: String, Sendable, Hashable, CaseIterable {
    /// Storage Service Class C-STORE — PS3.4 Table B.2-1
    case cStore = "C-STORE"
    /// Query/Retrieve C-FIND — PS3.4 Table C.4-1
    case cFind = "C-FIND"
    /// Query/Retrieve C-MOVE — PS3.4 Table C.4-2
    case cMove = "C-MOVE"
    /// Query/Retrieve C-GET — PS3.4 Table C.4-3
    case cGet = "C-GET"
    /// Modality Worklist Information Model - FIND C-FIND — PS3.4 Table K.4-1
    case mwlFind = "Modality Worklist C-FIND"
    /// Modality Performed Procedure Step N-SET — PS3.4 Table F.7.2-2.
    /// (MPPS N-CREATE has no specific codes, PS3.4 F.7.2.1.4: use ``dimseN``.)
    case mppsNSet = "Modality Performed Procedure Step N-SET"
    /// Modality Performed Procedure Step Retrieve N-GET — PS3.4 Table F.8.2-2
    case mppsNGet = "Modality Performed Procedure Step Retrieve N-GET"
    /// Basic Film Session N-CREATE — PS3.4 Table H.4.1.2.1.2-1
    case filmSessionNCreate = "Basic Film Session N-CREATE"
    /// Basic Film Session N-ACTION — PS3.4 Table H.4-4
    case filmSessionNAction = "Basic Film Session N-ACTION"
    /// Basic Film Box N-CREATE — PS3.4 Table H.4.2.2.1.2-1
    case filmBoxNCreate = "Basic Film Box N-CREATE"
    /// Basic Film Box N-ACTION — PS3.4 Table H.4-9
    case filmBoxNAction = "Basic Film Box N-ACTION"
    /// Basic Grayscale Image Box N-SET — PS3.4 Table H.4.3.1.2.1.2-1
    case grayscaleImageBoxNSet = "Basic Grayscale Image Box N-SET"
    /// Basic Color Image Box N-SET — PS3.4 Table H.4.3.2.2.1.2-1
    case colorImageBoxNSet = "Basic Color Image Box N-SET"
    /// Presentation LUT N-CREATE — PS3.4 Table H.4.9.2.1.2-1
    case presentationLUTNCreate = "Presentation LUT N-CREATE"
    /// Any other DIMSE-N operation (e.g. MPPS N-CREATE, Print Job N-GET): no
    /// service-specific table; only the PS3.7 Annex C general codes apply.
    case dimseN = "DIMSE-N"

    /// The PS3.4 table that lists this service's response status values; empty
    /// for ``dimseN``, which has none.
    public var statusTable: String {
        switch self {
        case .cStore: return "B.2-1"
        case .cFind:  return "C.4-1"
        case .cMove:  return "C.4-2"
        case .cGet:   return "C.4-3"
        case .mwlFind: return "K.4-1"
        case .mppsNSet: return "F.7.2-2"
        case .mppsNGet: return "F.8.2-2"
        case .filmSessionNCreate: return "H.4.1.2.1.2-1"
        case .filmSessionNAction: return "H.4-4"
        case .filmBoxNCreate: return "H.4.2.2.1.2-1"
        case .filmBoxNAction: return "H.4-9"
        case .grayscaleImageBoxNSet: return "H.4.3.1.2.1.2-1"
        case .colorImageBoxNSet: return "H.4.3.2.2.1.2-1"
        case .presentationLUTNCreate: return "H.4.9.2.1.2-1"
        case .dimseN: return ""
        }
    }

    /// The Print Management services (PS3.4 Annex H), in the order a code is
    /// looked up when the operation is not known.
    public static let printManagement: [DIMSEStatusService] = [
        .filmSessionNCreate, .filmSessionNAction, .filmBoxNCreate, .filmBoxNAction,
        .grayscaleImageBoxNSet, .colorImageBoxNSet, .presentationLUTNCreate,
    ]
}

/// One row of a PS3.4 response status table.
public struct DIMSEServiceStatusRow: Sendable, Hashable {
    /// Four hex digits as printed in the table; `x` is a wildcard hex digit
    /// ("Cxxx" is the 0xC000-0xCFFF range, "A7xx" the 0xA700-0xA7FF range).
    public let code: String
    /// The "Service Status" column: Failure / Cancel / Warning / Success / Pending.
    public let serviceStatus: String
    /// The "Further Meaning" column, verbatim.
    public let furtherMeaning: String

    public init(code: String, serviceStatus: String, furtherMeaning: String) {
        self.code = code
        self.serviceStatus = serviceStatus
        self.furtherMeaning = furtherMeaning
    }

    /// Whether a 16-bit status code matches this row's code pattern.
    public func matches(_ value: UInt16) -> Bool {
        let hex = String(format: "%04X", value)
        guard hex.count == code.count else { return false }
        for (c, p) in zip(hex, code) where p != "x" && p != c { return false }
        return true
    }
}

/// One status of PS3.7 Annex C that has a fixed code (the general DIMSE
/// statuses, most of them DIMSE-N).
public struct DIMSEAnnexCStatusRow: Sendable, Hashable {
    /// The PS3.7 section, e.g. "C.5.21".
    public let section: String
    /// The Status (0000,0900) value the section fixes.
    public let code: UInt16
    /// The status class of the parent section: Success / Cancel / Warning / Failure.
    public let statusClass: String
    /// The section title, verbatim, e.g. "Processing Failure".
    public let name: String

    public init(section: String, code: UInt16, statusClass: String, name: String) {
        self.section = section
        self.code = code
        self.statusClass = statusClass
        self.name = name
    }
}

/// Service-specific response status wording, as PS3.4 / PS3.7 2026a spell it.
///
/// ``DIMSEStatus/description`` is service-agnostic; this type looks the code
/// up in the table of the service that produced it so the CLI tools and the
/// DICOMStudio console print the same, standard text. A code the service table
/// does not list is named from PS3.7 Annex C when Annex C fixes it, else
/// rendered with the ``DIMSEStatus`` wording.
public enum DIMSEServiceStatusText {

    /// PS3.4 2026a Table B.2-1
    static let cStoreRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "A7xx", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources"),
        DIMSEServiceStatusRow(code: "A9xx", serviceStatus: "Failure", furtherMeaning: "Error: Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "Cxxx", serviceStatus: "Failure", furtherMeaning: "Error: Cannot understand"),
        DIMSEServiceStatusRow(code: "B000", serviceStatus: "Warning", furtherMeaning: "Coercion of Data Elements"),
        DIMSEServiceStatusRow(code: "B007", serviceStatus: "Warning", furtherMeaning: "Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "B006", serviceStatus: "Warning", furtherMeaning: "Elements Discarded"),
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Success"),
    ]

    /// PS3.4 2026a Table C.4-1
    static let cFindRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "A700", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources"),
        DIMSEServiceStatusRow(code: "A900", serviceStatus: "Failure", furtherMeaning: "Error: Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "Cxxx", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to process"),
        DIMSEServiceStatusRow(code: "FE00", serviceStatus: "Cancel", furtherMeaning: "Matching terminated due to Cancel request"),
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Matching is complete - No final Identifier is supplied."),
        DIMSEServiceStatusRow(code: "FF00", serviceStatus: "Pending", furtherMeaning: "Matches are continuing - Current Match is supplied and any Optional Keys were supported in the same manner as Required Keys."),
        DIMSEServiceStatusRow(code: "FF01", serviceStatus: "Pending", furtherMeaning: "Matches are continuing - Warning that one or more Optional Keys were not supported for existence and/or matching for this Identifier."),
    ]

    /// PS3.4 2026a Table C.4-2
    static let cMoveRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "A701", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources - Unable to calculate number of matches"),
        DIMSEServiceStatusRow(code: "A702", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources - Unable to perform sub-operations"),
        DIMSEServiceStatusRow(code: "A801", serviceStatus: "Failure", furtherMeaning: "Refused: Move Destination unknown"),
        DIMSEServiceStatusRow(code: "A900", serviceStatus: "Failure", furtherMeaning: "Error: Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "Cxxx", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to process"),
        DIMSEServiceStatusRow(code: "FE00", serviceStatus: "Cancel", furtherMeaning: "Sub-operations terminated due to Cancel Indication"),
        DIMSEServiceStatusRow(code: "B000", serviceStatus: "Warning", furtherMeaning: "Sub-operations Complete - One or more Failures"),
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Sub-operations Complete - No Failures"),
        DIMSEServiceStatusRow(code: "FF00", serviceStatus: "Pending", furtherMeaning: "Sub-operations are continuing"),
    ]

    /// PS3.4 2026a Table C.4-3
    static let cGetRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "A701", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources - Unable to calculate number of matches"),
        DIMSEServiceStatusRow(code: "A702", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources - Unable to perform sub-operations"),
        DIMSEServiceStatusRow(code: "A900", serviceStatus: "Failure", furtherMeaning: "Error: Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "Cxxx", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to process"),
        DIMSEServiceStatusRow(code: "FE00", serviceStatus: "Cancel", furtherMeaning: "Sub-operations terminated due to Cancel Indication"),
        DIMSEServiceStatusRow(code: "B000", serviceStatus: "Warning", furtherMeaning: "Sub-operations Complete - One or more Failures or Warnings"),
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Sub-operations Complete - No Failures or Warnings"),
        DIMSEServiceStatusRow(code: "FF00", serviceStatus: "Pending", furtherMeaning: "Sub-operations are continuing"),
    ]

    /// PS3.4 2026a Table K.4-1
    static let mwlFindRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "A700", serviceStatus: "Failure", furtherMeaning: "Refused: Out of resources"),
        DIMSEServiceStatusRow(code: "A900", serviceStatus: "Failure", furtherMeaning: "Error: Data Set does not match SOP Class"),
        DIMSEServiceStatusRow(code: "Cxxx", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to process"),
        DIMSEServiceStatusRow(code: "FE00", serviceStatus: "Cancel", furtherMeaning: "Matching terminated due to Cancel request"),
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Matching is complete - No final Identifier is supplied."),
        DIMSEServiceStatusRow(code: "FF00", serviceStatus: "Pending", furtherMeaning: "Matches are continuing - Current Match is supplied and any Optional Keys were supported in the same manner as Required Keys."),
        DIMSEServiceStatusRow(code: "FF01", serviceStatus: "Pending", furtherMeaning: "Matches are continuing - Warning that one or more Optional Keys were not supported for existence for this Identifier."),
    ]

    /// PS3.4 2026a Table F.7.2-2
    static let mppsNSetRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0110", serviceStatus: "Failure", furtherMeaning: "Processing Failure"),
    ]

    /// PS3.4 2026a Table F.8.2-2
    static let mppsNGetRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0001", serviceStatus: "Warning", furtherMeaning: "Requested optional Attributes are not supported"),
    ]

    /// PS3.4 2026a Table H.4.1.2.1.2-1
    static let filmSessionNCreateRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Film session successfully created"),
        DIMSEServiceStatusRow(code: "B600", serviceStatus: "Warning", furtherMeaning: "Memory allocation not supported"),
    ]

    /// PS3.4 2026a Table H.4-4
    static let filmSessionNActionRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Film belonging to the film session are accepted for printing; if supported, the Print Job SOP Instance is created"),
        DIMSEServiceStatusRow(code: "B601", serviceStatus: "Warning", furtherMeaning: "Film session printing (collation) is not supported"),
        DIMSEServiceStatusRow(code: "B602", serviceStatus: "Warning", furtherMeaning: "Film Session SOP Instance hierarchy does not contain Image Box SOP Instances (empty page)"),
        DIMSEServiceStatusRow(code: "B604", serviceStatus: "Warning", furtherMeaning: "Image size is larger than image box size, the image has been demagnified."),
        DIMSEServiceStatusRow(code: "B609", serviceStatus: "Warning", furtherMeaning: "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        DIMSEServiceStatusRow(code: "B60A", serviceStatus: "Warning", furtherMeaning: "Image size or Combined Print Image size is larger than the Image Box size. Image or Combined Print Image has been decimated to fit."),
        DIMSEServiceStatusRow(code: "C600", serviceStatus: "Failure", furtherMeaning: "Failed: Film Session SOP Instance hierarchy does not contain Film Box SOP Instances"),
        DIMSEServiceStatusRow(code: "C601", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to create Print Job SOP Instance; print queue is full"),
        DIMSEServiceStatusRow(code: "C603", serviceStatus: "Failure", furtherMeaning: "Failed: Image size is larger than image box size"),
        DIMSEServiceStatusRow(code: "C613", serviceStatus: "Failure", furtherMeaning: "Failed: Combined Print Image size is larger than the Image Box size"),
    ]

    /// PS3.4 2026a Table H.4.2.2.1.2-1
    static let filmBoxNCreateRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Film Box successfully created"),
        DIMSEServiceStatusRow(code: "B605", serviceStatus: "Warning", furtherMeaning: "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
        DIMSEServiceStatusRow(code: "C616", serviceStatus: "Failure", furtherMeaning: "Failed: There is an existing Film Box that has not been printed and N-ACTION at the Film Session level is not supported. A new Film Box will not be created when a previous Film Box has not been printed."),
    ]

    /// PS3.4 2026a Table H.4-9
    static let filmBoxNActionRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Film accepted for printing; if supported, the Print Job SOP Instance is created"),
        DIMSEServiceStatusRow(code: "B603", serviceStatus: "Warning", furtherMeaning: "Film Box SOP Instance hierarchy does not contain Image Box SOP Instances (empty page)"),
        DIMSEServiceStatusRow(code: "B604", serviceStatus: "Warning", furtherMeaning: "Image size is larger than image box size, the image has been demagnified."),
        DIMSEServiceStatusRow(code: "B609", serviceStatus: "Warning", furtherMeaning: "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        DIMSEServiceStatusRow(code: "B60A", serviceStatus: "Warning", furtherMeaning: "Image size or Combined Print Image size is larger than the Image Box size. Image or Combined Print Image has been decimated to fit."),
        DIMSEServiceStatusRow(code: "C602", serviceStatus: "Failure", furtherMeaning: "Failed: Unable to create Print Job SOP Instance; print queue is full"),
        DIMSEServiceStatusRow(code: "C603", serviceStatus: "Failure", furtherMeaning: "Failed: Image size is larger than image box size"),
        DIMSEServiceStatusRow(code: "C613", serviceStatus: "Failure", furtherMeaning: "Failed: Combined Print Image size is larger than the Image Box size"),
    ]

    /// PS3.4 2026a Table H.4.3.1.2.1.2-1
    static let grayscaleImageBoxNSetRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Image successfully stored in Image Box"),
        DIMSEServiceStatusRow(code: "B604", serviceStatus: "Warning", furtherMeaning: "Image size larger than image box size, the image has been demagnified."),
        DIMSEServiceStatusRow(code: "B605", serviceStatus: "Warning", furtherMeaning: "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
        DIMSEServiceStatusRow(code: "B609", serviceStatus: "Warning", furtherMeaning: "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        DIMSEServiceStatusRow(code: "B60A", serviceStatus: "Warning", furtherMeaning: "Image size or Combined Print Image size is larger than the Image Box size. The Image or Combined Print Image has been decimated to fit."),
        DIMSEServiceStatusRow(code: "C603", serviceStatus: "Failure", furtherMeaning: "Failed: Image size is larger than image box size"),
        DIMSEServiceStatusRow(code: "C605", serviceStatus: "Failure", furtherMeaning: "Failed: Insufficient memory in printer to store the image"),
        DIMSEServiceStatusRow(code: "C613", serviceStatus: "Failure", furtherMeaning: "Failed: Combined Print Image size is larger than the Image Box size"),
    ]

    /// PS3.4 2026a Table H.4.3.2.2.1.2-1
    static let colorImageBoxNSetRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "B604", serviceStatus: "Warning", furtherMeaning: "Image size larger than image box size, the image has been demagnified."),
        DIMSEServiceStatusRow(code: "B609", serviceStatus: "Warning", furtherMeaning: "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        DIMSEServiceStatusRow(code: "B60A", serviceStatus: "Warning", furtherMeaning: "Image size or Combined Print Image size is larger than the Image Box size. The Image or Combined Print Image has been decimated to fit."),
        DIMSEServiceStatusRow(code: "C603", serviceStatus: "Failure", furtherMeaning: "Failed: Image size is larger than image box size"),
        DIMSEServiceStatusRow(code: "C605", serviceStatus: "Failure", furtherMeaning: "Failed: Insufficient memory in printer to store the image"),
        DIMSEServiceStatusRow(code: "C613", serviceStatus: "Failure", furtherMeaning: "Failed: Combined Print Image size is larger than the Image Box size"),
    ]

    /// PS3.4 2026a Table H.4.9.2.1.2-1
    static let presentationLUTNCreateRows: [DIMSEServiceStatusRow] = [
        DIMSEServiceStatusRow(code: "0000", serviceStatus: "Success", furtherMeaning: "Presentation LUT successfully created"),
        DIMSEServiceStatusRow(code: "B605", serviceStatus: "Warning", furtherMeaning: "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
    ]

    /// PS3.4 2026a Table F.7.2-2, Error Comment (0000,0902) / Error ID (0000,0903) columns
    static let mppsNSetErrorIDs: [UInt16: String] = [
        0xA710: "Performed Procedure Step Object may no longer be updated", // with Status 0110
    ]

    /// PS3.7 2026a Annex C: the status sections that fix a code (C.1.1, C.3.1, C.4.2-C.4.3,
    /// C.5.6-C.5.25); the service-class specific sections (C.2.1, C.4.1, C.5.1-C.5.5) have no code.
    static let annexCRows: [DIMSEAnnexCStatusRow] = [
        DIMSEAnnexCStatusRow(section: "C.1.1", code: 0x0000, statusClass: "Success", name: "Success"),
        DIMSEAnnexCStatusRow(section: "C.3.1", code: 0xFE00, statusClass: "Cancel", name: "Cancel"),
        DIMSEAnnexCStatusRow(section: "C.4.2", code: 0x0107, statusClass: "Warning", name: "Attribute List warning"),
        DIMSEAnnexCStatusRow(section: "C.4.3", code: 0x0116, statusClass: "Warning", name: "Attribute Value out of range"),
        DIMSEAnnexCStatusRow(section: "C.5.6", code: 0x0122, statusClass: "Failure", name: "Refused: SOP Class not supported"),
        DIMSEAnnexCStatusRow(section: "C.5.7", code: 0x0119, statusClass: "Failure", name: "Class-Instance conflict"),
        DIMSEAnnexCStatusRow(section: "C.5.8", code: 0x0111, statusClass: "Failure", name: "Duplicate SOP Instance"),
        DIMSEAnnexCStatusRow(section: "C.5.9", code: 0x0210, statusClass: "Failure", name: "Duplicate invocation"),
        DIMSEAnnexCStatusRow(section: "C.5.10", code: 0x0115, statusClass: "Failure", name: "Invalid argument value"),
        DIMSEAnnexCStatusRow(section: "C.5.11", code: 0x0106, statusClass: "Failure", name: "Invalid Attribute Value"),
        DIMSEAnnexCStatusRow(section: "C.5.12", code: 0x0117, statusClass: "Failure", name: "Invalid SOP Instance"),
        DIMSEAnnexCStatusRow(section: "C.5.13", code: 0x0120, statusClass: "Failure", name: "Missing Attribute"),
        DIMSEAnnexCStatusRow(section: "C.5.14", code: 0x0121, statusClass: "Failure", name: "Missing Attribute Value"),
        DIMSEAnnexCStatusRow(section: "C.5.15", code: 0x0212, statusClass: "Failure", name: "Mistyped argument"),
        DIMSEAnnexCStatusRow(section: "C.5.16", code: 0x0114, statusClass: "Failure", name: "No such argument"),
        DIMSEAnnexCStatusRow(section: "C.5.17", code: 0x0105, statusClass: "Failure", name: "No such Attribute"),
        DIMSEAnnexCStatusRow(section: "C.5.18", code: 0x0113, statusClass: "Failure", name: "No such Event Type"),
        DIMSEAnnexCStatusRow(section: "C.5.19", code: 0x0112, statusClass: "Failure", name: "No such SOP Instance"),
        DIMSEAnnexCStatusRow(section: "C.5.20", code: 0x0118, statusClass: "Failure", name: "No such SOP Class"),
        DIMSEAnnexCStatusRow(section: "C.5.21", code: 0x0110, statusClass: "Failure", name: "Processing Failure"),
        DIMSEAnnexCStatusRow(section: "C.5.22", code: 0x0213, statusClass: "Failure", name: "Resource limitation"),
        DIMSEAnnexCStatusRow(section: "C.5.23", code: 0x0211, statusClass: "Failure", name: "Unrecognized operation"),
        DIMSEAnnexCStatusRow(section: "C.5.24", code: 0x0123, statusClass: "Failure", name: "No such Action Type"),
        DIMSEAnnexCStatusRow(section: "C.5.25", code: 0x0124, statusClass: "Failure", name: "Refused: Not authorized"),
    ]

    /// The rows of the PS3.4 table for `service`, in table order (empty for ``DIMSEStatusService/dimseN``).
    public static func rows(for service: DIMSEStatusService) -> [DIMSEServiceStatusRow] {
        switch service {
        case .cStore: return cStoreRows
        case .cFind:  return cFindRows
        case .cMove:  return cMoveRows
        case .cGet:   return cGetRows
        case .mwlFind: return mwlFindRows
        case .mppsNSet: return mppsNSetRows
        case .mppsNGet: return mppsNGetRows
        case .filmSessionNCreate: return filmSessionNCreateRows
        case .filmSessionNAction: return filmSessionNActionRows
        case .filmBoxNCreate: return filmBoxNCreateRows
        case .filmBoxNAction: return filmBoxNActionRows
        case .grayscaleImageBoxNSet: return grayscaleImageBoxNSetRows
        case .colorImageBoxNSet: return colorImageBoxNSetRows
        case .presentationLUTNCreate: return presentationLUTNCreateRows
        case .dimseN: return []
        }
    }

    /// The table row for a status code, or nil when the table has no row for it.
    /// An exact code wins over a wildcard range ("A900" before "A9xx").
    public static func row(for code: UInt16, service: DIMSEStatusService) -> DIMSEServiceStatusRow? {
        let table = rows(for: service)
        if let exact = table.first(where: { !$0.code.contains("x") && $0.matches(code) }) { return exact }
        return table.first(where: { $0.matches(code) })
    }

    /// The PS3.7 2026a Annex C statuses that fix a code, in section order.
    public static var annexCStatusRows: [DIMSEAnnexCStatusRow] { annexCRows }

    /// The PS3.7 Annex C status for `code`, or nil when Annex C fixes no such code.
    public static func annexCRow(for code: UInt16) -> DIMSEAnnexCStatusRow? {
        annexCRows.first { $0.code == code }
    }

    /// The Print Management (PS3.4 Annex H) row for `code` when the operation
    /// is not known: the first of ``DIMSEStatusService/printManagement`` whose
    /// table lists the exact code. Every Annex H failure code (C600-C616) has
    /// one meaning; a warning worded differently by two tables (B604, B60A)
    /// gets the Film Session wording.
    public static func printRow(for code: UInt16) -> (service: DIMSEStatusService, row: DIMSEServiceStatusRow)? {
        for service in DIMSEStatusService.printManagement {
            if let row = rows(for: service).first(where: { !$0.code.contains("x") && $0.matches(code) }) {
                return (service, row)
            }
        }
        return nil
    }

    /// The Error Comment PS3.4 Table F.7.2-2 pairs with an MPPS N-SET Error ID
    /// (0000,0903), e.g. 0xA710 "Performed Procedure Step Object may no longer
    /// be updated"; nil for any other Error ID.
    public static func mppsNSetErrorComment(errorID: UInt16) -> String? {
        mppsNSetErrorIDs[errorID]
    }

    /// "Success (0x0000): Sub-operations Complete - No Failures" — the PS3.4
    /// Service Status, the code, and the Further Meaning. A code outside the
    /// table is named from PS3.7 Annex C ("Failure (0x0106): Invalid Attribute
    /// Value") when Annex C fixes it, else rendered with the ``DIMSEStatus``
    /// wording and the table named.
    public static func describe(_ status: DIMSEStatus, service: DIMSEStatusService) -> String {
        let hex = String(format: "%04X", status.rawValue)
        if let row = row(for: status.rawValue, service: service) {
            return "\(row.serviceStatus) (0x\(hex)): \(row.furtherMeaning)"
        }
        if let general = annexCRow(for: status.rawValue) {
            return "\(general.statusClass) (0x\(hex)): \(general.name)"
        }
        guard !service.statusTable.isEmpty else { return "\(status)" }
        return "\(status) (not listed in PS3.4 Table \(service.statusTable))"
    }

    /// A Print Management response status worded per PS3.4 Annex H (looked up
    /// with ``printRow(for:)``), else per PS3.7 Annex C, else with the
    /// ``DIMSEStatus`` wording.
    public static func describePrintStatus(_ status: DIMSEStatus) -> String {
        let hex = String(format: "%04X", status.rawValue)
        if let (_, row) = printRow(for: status.rawValue) {
            return "\(row.serviceStatus) (0x\(hex)): \(row.furtherMeaning)"
        }
        return describe(status, service: .dimseN)
    }

    /// The final-response counters of a C-MOVE / C-GET under their PS3.7 names
    /// (Tables 9.3-10 / 9.3-7): Number of Completed / Failed / Warning Sub-operations.
    public static func subOperationCounts(_ progress: RetrieveProgress) -> String {
        "Number of Completed Sub-operations: \(progress.completed), "
            + "Number of Failed Sub-operations: \(progress.failed), "
            + "Number of Warning Sub-operations: \(progress.warning)"
    }
}

extension DIMSEStatus {
    /// The status worded per the PS3.4 response status table of `service`
    /// (see ``DIMSEServiceStatusText/describe(_:service:)``).
    public func description(for service: DIMSEStatusService) -> String {
        DIMSEServiceStatusText.describe(self, service: service)
    }
}
