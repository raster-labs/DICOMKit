import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — Warning Reason (0008,1196) is read from the Referenced SOP Sequence items (Table I.1-1, D106); meanings of Tables I.2-1 (3 rows) / I.2-2 (6 rows) dumped by Scripts/nema_docbook.py into standardMeaning(forFailureReason:/forWarningReason:); checked 2026-09-28 — the 7 tags read against PS3.18 2026a Table I.1-1 (all present); FailureReasonCode diffed against Tables I.2-1 / I.2-2: 0110, 0122, C122, A900, C000, A700, B000, B006, B007 match, 0111 is an additional code (I.2.2), the 7 PS3.7-only cases are deprecated; the range classification (A7xx, A9xx, Cxxx) is in knownFailureReason
/// Response from a STOW-RS store operation
///
/// Contains the results of storing one or more DICOM instances,
/// including successfully stored instances and any failures.
///
/// Reference: PS3.18 Section 10.5 - Store Transaction (STOW-RS); Annex I - Store Instances Response Module
///
/// ## Example Usage
///
/// ```swift
/// let response = try await client.storeInstances(instances: [dicomData])
///
/// if response.isFullSuccess {
///     print("All \(response.successCount) instances stored successfully")
/// } else if response.isPartialSuccess {
///     print("Stored \(response.successCount) instances with \(response.failureCount) failures")
/// } else {
///     print("Store failed: \(response.failedInstances)")
/// }
/// ```
public struct STOWResponse: Sendable, Equatable {
    
    // MARK: - Types
    
    /// Result for a single stored instance
    public struct InstanceResult: Sendable, Equatable {
        /// The SOP Class UID of the stored instance
        public let sopClassUID: String?
        
        /// The SOP Instance UID of the stored instance
        public let sopInstanceUID: String
        
        /// The retrieve URL for the stored instance (if available)
        public let retrieveURL: String?
        
        /// Warning Reason (0008,1196): why the instance was accepted with warnings
        /// (PS3.18 2026a Table I.1-1, values in Table I.2-1); nil when stored without warning.
        public let warningReason: UInt16?
        
        /// Creates an instance result
        /// - Parameters:
        ///   - sopClassUID: The SOP Class UID
        ///   - sopInstanceUID: The SOP Instance UID
        ///   - retrieveURL: The retrieve URL for the stored instance
        ///   - warningReason: Warning Reason (0008,1196), PS3.18 Table I.2-1
        public init(sopClassUID: String? = nil, sopInstanceUID: String, retrieveURL: String? = nil,
                    warningReason: UInt16? = nil) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.retrieveURL = retrieveURL
            self.warningReason = warningReason
        }
    }
    
    /// Failure information for a single instance
    public struct InstanceFailure: Sendable, Equatable {
        /// The SOP Class UID of the failed instance
        public let sopClassUID: String?
        
        /// The SOP Instance UID of the failed instance
        public let sopInstanceUID: String?
        
        /// The failure reason code (PS3.18 Table I.2-2)
        public let failureReason: UInt16?
        
        /// Human-readable failure description
        public let failureDescription: String?
        
        /// Creates an instance failure
        /// - Parameters:
        ///   - sopClassUID: The SOP Class UID
        ///   - sopInstanceUID: The SOP Instance UID
        ///   - failureReason: The failure reason code
        ///   - failureDescription: Human-readable description
        public init(
            sopClassUID: String? = nil,
            sopInstanceUID: String? = nil,
            failureReason: UInt16? = nil,
            failureDescription: String? = nil
        ) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.failureReason = failureReason
            self.failureDescription = failureDescription
        }
        
        // MARK: - Standard Failure Reasons
        
        /// Failure reason codes. PS3.18 Table I.2-2 defines 0110, 0122, A7xx, A9xx, Cxxx and C122
        /// and Table I.2-1 the warnings B000, B006 and B007; the other cases here are PS3.7
        /// Annex C statuses that the tables do not list (see the audit report, P-STOW)
        public enum FailureReasonCode: UInt16, Sendable {
            /// Processing failure (Table I.2-2, 0110)
            case processingFailure = 0x0110
            
            /// Duplicate SOP Instance (PS3.7 C.5.9; an additional code as I.2.2 allows, used by
            /// the DICOMKit server for a rejected duplicate)
            case duplicateSOPInstance = 0x0111
            
            /// Referenced SOP Class not supported (Table I.2-2, 0122)
            case sopClassNotSupported = 0x0122
            
            /// Referenced Transfer Syntax not supported (Table I.2-2, C122)
            case referencedTransferSyntaxNotSupported = 0xC122
            
            /// Error: Data Set does not match SOP Class (Table I.2-2, A9xx; the exact value A900
            /// and every other A9xx value classify here)
            case dataSetDoesNotMatchSOPClassError = 0xA900
            
            /// Error: Cannot understand (Table I.2-2, Cxxx; every Cxxx value other than C122
            /// classifies here)
            case cannotUnderstand = 0xC000
            
            /// Refused out of Resources (Table I.2-2, A7xx)
            case outOfResources = 0xA700
            
            /// Coercion of Data Elements (Table I.2-1, B000, a warning)
            case dataSetCoercion = 0xB000
            
            /// Elements Discarded (Table I.2-1, B006, a warning)
            case elementsDiscarded = 0xB006
            
            /// Data Set does not match SOP Class (Table I.2-1, B007, a warning)
            case dataSetDoesNotMatchSOPClassWarning = 0xB007
            
            // PS3.7 Annex C statuses that PS3.18 Tables I.2-1 / I.2-2 do not define for the
            // Store Transaction
            @available(*, deprecated, message: "not a PS3.18 Table I.2-2 Failure Reason")
            case noSuchObjectInstance = 0x0112
            @available(*, deprecated, message: "not a PS3.18 Table I.2-2 Failure Reason")
            case noSuchEventType = 0x0113
            @available(*, deprecated, message: "not a PS3.18 Table I.2-2 Failure Reason")
            case noSuchArgument = 0x0114
            @available(*, deprecated, message: "not a PS3.18 Table I.2-2 Failure Reason")
            case invalidArgumentValue = 0x0115
            @available(*, deprecated, message: "not a PS3.18 Table I.2-2 Failure Reason")
            case mandatoryAttributeMissing = 0x0120
            @available(*, deprecated, renamed: "referencedTransferSyntaxNotSupported", message: "PS3.18 Table I.2-2: C122")
            case transferSyntaxNotSupported = 0x0124
            @available(*, deprecated, renamed: "dataSetDoesNotMatchSOPClassError", message: "PS3.18 Table I.2-2: A9xx (error) or I.2-1 B007 (warning)")
            case dataSetDoesNotMatchSOPClass = 0x0131
        }
        
        /// Returns the failure reason as a known code, if applicable. Exact values map to their
        /// case; the ranges of PS3.18 Table I.2-2 (A7xx Refused out of Resources, A9xx Data Set
        /// does not match SOP Class, Cxxx Cannot understand) map to their range case.
        public var knownFailureReason: FailureReasonCode? {
            guard let reason = failureReason else { return nil }
            if let exact = FailureReasonCode(rawValue: reason) {
                return exact
            }
            switch reason & 0xFF00 {
            case 0xA700: return .outOfResources
            case 0xA900: return .dataSetDoesNotMatchSOPClassError
            case 0xC000...0xCF00: return .cannotUnderstand
            default: return nil
            }
        }
    }
    
    // MARK: - Standard meanings (PS3.18 2026a Annex I.2)
    
    /// The PS3.18 2026a Table I.2-2 meaning of a Failure Reason (0008,1197) value, including
    /// the A7xx / A9xx / Cxxx ranges; 0111 is the additional code (I.2.2) the DICOMKit server
    /// uses for a duplicate SOP Instance. nil for a value the table does not define.
    public static func standardMeaning(forFailureReason code: UInt16) -> String? {
        switch code {
        case 0x0110: return "Processing failure"
        case 0x0111: return "Duplicate SOP Instance"
        case 0x0122: return "Referenced SOP Class not supported"
        case 0xC122: return "Referenced Transfer Syntax not supported"
        case 0xA700...0xA7FF: return "Refused out of Resources"
        case 0xA900...0xA9FF: return "Error: Data Set does not match SOP Class"
        case 0xC000...0xCFFF: return "Error: Cannot understand"
        default: return nil
        }
    }
    
    /// The PS3.18 2026a Table I.2-1 meaning of a Warning Reason (0008,1196) value; nil for a
    /// value the table does not define.
    public static func standardMeaning(forWarningReason code: UInt16) -> String? {
        switch code {
        case 0xB000: return "Coercion of Data Elements"
        case 0xB006: return "Elements Discarded"
        case 0xB007: return "Data Set does not match SOP Class"
        default: return nil
        }
    }
    
    /// `<hex> (<decimal>): <meaning>` for a reason code, as PS3.18 Tables I.2-1 / I.2-2 list
    /// both forms, e.g. `A701 (42753): Refused out of Resources`; an undefined value reads
    /// `… : not defined in PS3.18 Table I.2-x`.
    static func describe(code: UInt16, meaning: String?, table: String) -> String {
        let hex = String(format: "%04X", code)
        return "\(hex) (\(code)): " + (meaning ?? "not defined in PS3.18 Table \(table)")
    }
    
    /// Warning message from the server
    public struct Warning: Sendable, Equatable {
        /// Warning code
        public let code: String?
        
        /// Warning message
        public let message: String
        
        /// Creates a warning
        /// - Parameters:
        ///   - code: Optional warning code
        ///   - message: The warning message
        public init(code: String? = nil, message: String) {
            self.code = code
            self.message = message
        }
    }
    
    // MARK: - Properties
    
    /// Successfully stored instances
    public let storedInstances: [InstanceResult]
    
    /// Failed instances with failure information
    public let failedInstances: [InstanceFailure]
    
    /// Warning messages from the server
    public let warnings: [Warning]
    
    /// The base retrieve URL for the stored instances
    public let retrieveURL: String?
    
    // MARK: - Computed Properties
    
    /// Number of successfully stored instances
    public var successCount: Int {
        return storedInstances.count
    }
    
    /// Number of failed instances
    public var failureCount: Int {
        return failedInstances.count
    }
    
    /// Total number of instances processed
    public var totalCount: Int {
        return successCount + failureCount
    }
    
    /// Whether all instances were stored successfully
    public var isFullSuccess: Bool {
        return failedInstances.isEmpty && !storedInstances.isEmpty
    }
    
    /// Whether some but not all instances were stored
    public var isPartialSuccess: Bool {
        return !storedInstances.isEmpty && !failedInstances.isEmpty
    }
    
    /// Whether all instances failed
    public var isFullFailure: Bool {
        return storedInstances.isEmpty && !failedInstances.isEmpty
    }
    
    /// Whether there are any warnings
    public var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    // MARK: - Initialization
    
    /// Creates a STOW response
    /// - Parameters:
    ///   - storedInstances: Successfully stored instances
    ///   - failedInstances: Failed instances
    ///   - warnings: Warning messages
    ///   - retrieveURL: Base retrieve URL
    public init(
        storedInstances: [InstanceResult] = [],
        failedInstances: [InstanceFailure] = [],
        warnings: [Warning] = [],
        retrieveURL: String? = nil
    ) {
        self.storedInstances = storedInstances
        self.failedInstances = failedInstances
        self.warnings = warnings
        self.retrieveURL = retrieveURL
    }
}

// MARK: - JSON Parsing

extension STOWResponse {
    
    /// DICOM JSON tags used in STOW-RS responses
    private enum Tag {
        static let referencedSOPSequence = "00081199"  // (0008,1199)
        static let failedSOPSequence = "00081198"      // (0008,1198)
        static let retrieveURL = "00081190"            // (0008,1190)
        static let referencedSOPClassUID = "00081150"  // (0008,1150)
        static let referencedSOPInstanceUID = "00081155" // (0008,1155)
        static let failureReason = "00081197"          // (0008,1197)
        static let warningReason = "00081196"          // (0008,1196)
    }
    
    /// Parses a STOW-RS JSON response
    /// - Parameter json: The DICOM JSON object (single dataset)
    /// - Returns: Parsed STOWResponse
    /// - Throws: DICOMwebError if parsing fails
    public static func parse(json: [String: Any]) throws -> STOWResponse {
        var storedInstances: [InstanceResult] = []
        var failedInstances: [InstanceFailure] = []
        var warnings: [Warning] = []
        var retrieveURL: String?
        
        // Parse RetrieveURL (0008,1190)
        if let urlElement = json[Tag.retrieveURL] as? [String: Any],
           let values = urlElement["Value"] as? [String] {
            retrieveURL = values.first
        }
        
        // Parse ReferencedSOPSequence (0008,1199) - successful instances
        if let seqElement = json[Tag.referencedSOPSequence] as? [String: Any],
           let items = seqElement["Value"] as? [[String: Any]] {
            for item in items {
                let result = parseInstanceResult(from: item)
                storedInstances.append(result)
                // Warning Reason (0008,1196), Table I.1-1: accepted with warnings (Table I.2-1).
                if let code = result.warningReason {
                    warnings.append(Warning(
                        code: String(format: "%04X", code),
                        message: "\(result.sopInstanceUID): " + describe(
                            code: code, meaning: standardMeaning(forWarningReason: code), table: "I.2-1")))
                }
            }
        }
        
        // Parse FailedSOPSequence (0008,1198) - failed instances
        if let seqElement = json[Tag.failedSOPSequence] as? [String: Any],
           let items = seqElement["Value"] as? [[String: Any]] {
            for item in items {
                let failure = parseInstanceFailure(from: item)
                failedInstances.append(failure)
            }
        }
        
        return STOWResponse(
            storedInstances: storedInstances,
            failedInstances: failedInstances,
            warnings: warnings,
            retrieveURL: retrieveURL
        )
    }
    
    /// Parses an InstanceResult from a DICOM JSON sequence item
    private static func parseInstanceResult(from json: [String: Any]) -> InstanceResult {
        var sopClassUID: String?
        var sopInstanceUID = ""
        var retrieveURL: String?
        var warningReason: UInt16?
        
        // ReferencedSOPClassUID (0008,1150)
        if let element = json[Tag.referencedSOPClassUID] as? [String: Any],
           let values = element["Value"] as? [String] {
            sopClassUID = values.first
        }
        
        // ReferencedSOPInstanceUID (0008,1155)
        if let element = json[Tag.referencedSOPInstanceUID] as? [String: Any],
           let values = element["Value"] as? [String] {
            sopInstanceUID = values.first ?? ""
        }
        
        // RetrieveURL (0008,1190)
        if let element = json[Tag.retrieveURL] as? [String: Any],
           let values = element["Value"] as? [String] {
            retrieveURL = values.first
        }
        
        // WarningReason (0008,1196), US — PS3.18 Table I.1-1 (Referenced SOP Sequence item)
        if let element = json[Tag.warningReason] as? [String: Any],
           let values = element["Value"] as? [Any],
           let first = values.first,
           let value = (first as? Int) ?? (first as? NSNumber)?.intValue,
           let code = UInt16(exactly: value) {
            warningReason = code
        }
        
        return InstanceResult(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            retrieveURL: retrieveURL,
            warningReason: warningReason
        )
    }
    
    /// Parses an InstanceFailure from a DICOM JSON sequence item
    private static func parseInstanceFailure(from json: [String: Any]) -> InstanceFailure {
        var sopClassUID: String?
        var sopInstanceUID: String?
        var failureReason: UInt16?
        var failureDescription: String?
        
        // ReferencedSOPClassUID (0008,1150)
        if let element = json[Tag.referencedSOPClassUID] as? [String: Any],
           let values = element["Value"] as? [String] {
            sopClassUID = values.first
        }
        
        // ReferencedSOPInstanceUID (0008,1155)
        if let element = json[Tag.referencedSOPInstanceUID] as? [String: Any],
           let values = element["Value"] as? [String] {
            sopInstanceUID = values.first
        }
        
        // FailureReason (0008,1197)
        if let element = json[Tag.failureReason] as? [String: Any],
           let values = element["Value"] as? [Int] {
            if let value = values.first {
                failureReason = UInt16(exactly: value)
            }
        }
        
        // WarningReason (0008,1196) - used for failure description
        if let element = json[Tag.warningReason] as? [String: Any],
           let values = element["Value"] as? [Int] {
            if let value = values.first {
                failureDescription = "Reason code: \(value)"
            }
        }
        
        return InstanceFailure(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            failureReason: failureReason,
            failureDescription: failureDescription
        )
    }
}

// MARK: - CustomStringConvertible

extension STOWResponse: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        
        if isFullSuccess {
            parts.append("Success: \(successCount) instance(s) stored")
        } else if isPartialSuccess {
            parts.append("Partial Success: \(successCount) stored, \(failureCount) failed")
        } else if isFullFailure {
            parts.append("Failed: \(failureCount) instance(s)")
        } else {
            parts.append("Empty response")
        }
        
        if hasWarnings {
            parts.append("(\(warnings.count) warning(s))")
        }
        
        return parts.joined(separator: " ")
    }
}

extension STOWResponse.InstanceFailure: CustomStringConvertible {
    public var description: String {
        var parts: [String] = ["Instance failure"]
        
        if let uid = sopInstanceUID {
            parts.append("SOP Instance: \(uid)")
        }
        
        if let reason = failureReason {
            parts.append("Reason: \(String(format: "0x%04X", reason))")
        }
        
        if let desc = failureDescription {
            parts.append("Description: \(desc)")
        }
        
        return parts.joined(separator: ", ")
    }
}
