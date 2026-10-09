import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the 5 Result/Reason values text-diffed against PS3.8 2026a Table 9-18 (Scripts/diff_network.py): 5 of 5 match; ID rule (odd, 1-255) per §9.3.2.2 / Table 9-13

/// Presentation Context for DICOM association negotiation
///
/// A Presentation Context defines a pairing of an Abstract Syntax (SOP Class)
/// with one or more Transfer Syntaxes for data encoding.
///
/// Reference: PS3.8 Section 9.3.2.2 - Presentation Context Item
public struct PresentationContext: Sendable, Hashable {
    /// Unique identifier for this presentation context (odd number, 1-255)
    public let id: UInt8
    
    /// Abstract Syntax UID (SOP Class UID)
    ///
    /// Identifies the type of DICOM service or object (e.g., CT Image Storage)
    public let abstractSyntax: String
    
    /// Proposed Transfer Syntaxes
    ///
    /// One or more transfer syntaxes that can be used for data encoding.
    /// Listed in order of preference.
    public let transferSyntaxes: [String]
    
    /// Creates a proposed presentation context for association request
    ///
    /// - Parameters:
    ///   - id: Presentation context ID (must be odd, 1-255)
    ///   - abstractSyntax: The Abstract Syntax (SOP Class) UID
    ///   - transferSyntaxes: One or more Transfer Syntax UIDs
    /// - Throws: `DICOMNetworkError.invalidPDU` if parameters are invalid
    public init(id: UInt8, abstractSyntax: String, transferSyntaxes: [String]) throws {
        guard id % 2 == 1 else {
            throw DICOMNetworkError.invalidPDU("Presentation Context ID must be odd, got \(id)")
        }
        guard !abstractSyntax.isEmpty else {
            throw DICOMNetworkError.invalidPDU("Abstract Syntax cannot be empty")
        }
        guard !transferSyntaxes.isEmpty else {
            throw DICOMNetworkError.invalidPDU("At least one Transfer Syntax is required")
        }
        
        self.id = id
        self.abstractSyntax = abstractSyntax
        self.transferSyntaxes = transferSyntaxes
    }
}

// MARK: - CustomStringConvertible
extension PresentationContext: CustomStringConvertible {
    public var description: String {
        let ts = transferSyntaxes.joined(separator: ", ")
        return "PresentationContext(id=\(id), abstractSyntax=\(abstractSyntax), transferSyntaxes=[\(ts)])"
    }
}

/// Result of presentation context negotiation
///
/// Reference: PS3.8 Section 9.3.3.2 - Presentation Context Item
public enum PresentationContextResult: UInt8, Sendable, Hashable {
    /// Acceptance - the presentation context is accepted
    case acceptance = 0
    
    /// User rejection - the abstract syntax is not recognized
    case userRejection = 1
    
    /// No reason (provider rejection) - no reason given
    case noReasonProviderRejection = 2
    
    /// Abstract syntax not supported (provider rejection)
    case abstractSyntaxNotSupported = 3
    
    /// Transfer syntaxes not supported (provider rejection)
    case transferSyntaxesNotSupported = 4
}

extension PresentationContextResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .acceptance:
            return "Acceptance"
        case .userRejection:
            return "User Rejection"
        case .noReasonProviderRejection:
            return "No Reason (Provider Rejection)"
        case .abstractSyntaxNotSupported:
            return "Abstract Syntax Not Supported"
        case .transferSyntaxesNotSupported:
            return "Transfer Syntaxes Not Supported"
        }
    }
}

/// Accepted Presentation Context from association accept
///
/// Contains the result of negotiation for a single presentation context.
///
/// Reference: PS3.8 Section 9.3.3.2
public struct AcceptedPresentationContext: Sendable, Hashable {
    /// Presentation context ID (matches the proposed context)
    public let id: UInt8
    
    /// Result of the negotiation
    public let result: PresentationContextResult
    
    /// The accepted transfer syntax (only valid when result is acceptance)
    public let transferSyntax: String?
    
    /// Creates an accepted presentation context
    ///
    /// - Parameters:
    ///   - id: The presentation context ID
    ///   - result: The result of negotiation
    ///   - transferSyntax: The accepted transfer syntax (for acceptance)
    public init(id: UInt8, result: PresentationContextResult, transferSyntax: String? = nil) {
        self.id = id
        self.result = result
        self.transferSyntax = transferSyntax
    }
    
    /// Whether this presentation context was accepted
    public var isAccepted: Bool {
        result == .acceptance && transferSyntax != nil
    }
}

extension AcceptedPresentationContext: CustomStringConvertible {
    public var description: String {
        if let ts = transferSyntax {
            return "AcceptedPresentationContext(id=\(id), result=\(result), transferSyntax=\(ts))"
        } else {
            return "AcceptedPresentationContext(id=\(id), result=\(result))"
        }
    }
}
