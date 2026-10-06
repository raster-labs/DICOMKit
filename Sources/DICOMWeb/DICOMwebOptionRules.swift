import Foundation

// NEMA-verified: 2026a, checked 2026-10-06 — `DICOMwebOptionRefusal` carries no standard data; the Change Workitem State refusal it is thrown with (`UPSState.changeStateTarget(optionValue:)`, Workitem.swift) was read against PS3.18 2026a 11.7.1.4 (3 legal values) and PS3.4 2026a Table CC.1.1-2 (change to SCHEDULED: C303H / C307H) (D255)

// MARK: - DICOMwebOptionRefusal

/// A value a DICOMweb front end (dicom-wado, DICOM Studio's CLI Workshop) was given for an
/// option, refused by a rule of the standard. The rules live in DICOMWeb so both front ends
/// print one text; the error says how a command-line tool should report it.
public struct DICOMwebOptionRefusal: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {

    /// How a command-line front end reports the refusal.
    public enum Kind: Sendable {
        /// The value is not of the form the parameter takes (a usage error: exit 64 with usage).
        case usage
        /// A well-formed value the standard does not allow for this operation (exit 1).
        case refused
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    /// The process exit status a command-line front end uses: 64 (EX_USAGE) or 1.
    public var exitCode: Int32 { kind == .usage ? 64 : 1 }

    public var description: String { message }
    public var errorDescription: String? { message }
}
