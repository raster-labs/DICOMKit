import Foundation
import DICOMCore
import DICOMDictionary
// NEMA-verified: 2026a, checked 2026-09-28 — transfer syntaxes now come from DICOMCore's PS3.6 2026a Table A-1 registry (was a hand list with 2 unregistered and 29 missing UIDs); storage classes from DICOMDictionary (PS3.4 Table B.5-1)

// MARK: - Validation Error

/// Error types for DICOM validation failures
///
/// These errors provide detailed information about why a DICOM object
/// failed validation, including the specific tag and reason.
///
/// Reference: PS3.3 - Information Object Definitions
/// Reference: PS3.4 - Service Class Specifications
public enum ValidationError: Error, Sendable, Hashable {
    /// A required attribute is missing from the DICOM object
    ///
    /// - Parameters:
    ///   - tag: The tag of the missing attribute
    ///   - description: Human-readable description of the attribute
    case missingRequiredAttribute(tag: Tag, description: String)
    
    /// A UID value is invalid or malformed
    ///
    /// - Parameters:
    ///   - tag: The tag containing the invalid UID
    ///   - value: The invalid UID value
    ///   - reason: Why the UID is invalid
    case invalidUID(tag: Tag, value: String, reason: String)
    
    /// An attribute value is empty when it should not be
    ///
    /// - Parameters:
    ///   - tag: The tag with the empty value
    ///   - description: Human-readable description of the attribute
    case emptyValue(tag: Tag, description: String)
    
    /// An attribute value exceeds the maximum allowed length
    ///
    /// - Parameters:
    ///   - tag: The tag with the oversized value
    ///   - actualLength: The actual length of the value
    ///   - maxLength: The maximum allowed length
    case valueTooLong(tag: Tag, actualLength: Int, maxLength: Int)
    
    /// The SOP Class UID is unknown or not supported
    ///
    /// - Parameter sopClassUID: The unknown SOP Class UID
    case unknownSOPClass(sopClassUID: String)
    
    /// The Transfer Syntax UID is unknown or not supported
    ///
    /// - Parameter transferSyntaxUID: The unknown Transfer Syntax UID
    case unknownTransferSyntax(transferSyntaxUID: String)
    
    /// Pixel data is present but required image attributes are missing
    ///
    /// - Parameter missingTags: Tags that are required for pixel data but missing
    case incompletePixelData(missingTags: [Tag])
    
    /// A custom validation rule failed
    ///
    /// - Parameters:
    ///   - tag: The tag that failed validation (optional)
    ///   - message: Description of the validation failure
    case customValidationFailed(tag: Tag?, message: String)
}

extension ValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingRequiredAttribute(let tag, let desc):
            return "Missing required attribute \(tag) (\(desc))"
        case .invalidUID(let tag, let value, let reason):
            return "Invalid UID at \(tag): '\(value)' - \(reason)"
        case .emptyValue(let tag, let desc):
            return "Empty value for \(tag) (\(desc))"
        case .valueTooLong(let tag, let actual, let max):
            return "Value too long at \(tag): \(actual) bytes (max \(max))"
        case .unknownSOPClass(let uid):
            return "Unknown SOP Class UID: \(uid)"
        case .unknownTransferSyntax(let uid):
            return "Unknown Transfer Syntax UID: \(uid)"
        case .incompletePixelData(let tags):
            let tagList = tags.map { $0.description }.joined(separator: ", ")
            return "Incomplete pixel data - missing: \(tagList)"
        case .customValidationFailed(let tag, let message):
            if let t = tag {
                return "Validation failed at \(t): \(message)"
            }
            return "Validation failed: \(message)"
        }
    }
}

// MARK: - Validation Result

/// Result of validating a DICOM object
///
/// Contains the overall validation status and any errors or warnings found.
public struct ValidationResult: Sendable {
    /// Whether the validation passed (no errors)
    public let isValid: Bool
    
    /// Validation errors that prevent the object from being stored
    public let errors: [ValidationError]
    
    /// Validation warnings that don't prevent storage but should be noted
    public let warnings: [ValidationError]
    
    /// Whether there are any warnings
    public var hasWarnings: Bool {
        !warnings.isEmpty
    }
    
    /// Total number of issues (errors + warnings)
    public var issueCount: Int {
        errors.count + warnings.count
    }
    
    /// Creates a successful validation result
    public static var success: ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: [])
    }
    
    /// Creates a successful validation result with warnings
    ///
    /// - Parameter warnings: Warning issues to include
    /// - Returns: A valid result with warnings
    public static func successWithWarnings(_ warnings: [ValidationError]) -> ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: warnings)
    }
    
    /// Creates a failed validation result
    ///
    /// - Parameters:
    ///   - errors: Error issues that caused validation to fail
    ///   - warnings: Warning issues (optional)
    /// - Returns: An invalid result
    public static func failure(errors: [ValidationError], warnings: [ValidationError] = []) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors, warnings: warnings)
    }
    
    /// Creates a validation result
    private init(isValid: Bool, errors: [ValidationError], warnings: [ValidationError]) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

extension ValidationResult: CustomStringConvertible {
    public var description: String {
        if isValid {
            if warnings.isEmpty {
                return "ValidationResult(valid)"
            } else {
                return "ValidationResult(valid with \(warnings.count) warning(s))"
            }
        } else {
            return "ValidationResult(invalid: \(errors.count) error(s), \(warnings.count) warning(s))"
        }
    }
}

// MARK: - Validation Level

/// Level of validation strictness
///
/// Controls how thorough validation is and what types of issues
/// are reported as errors vs. warnings.
public enum ValidationLevel: Sendable, Hashable, CaseIterable {
    /// Minimal validation - only critical attributes
    ///
    /// Checks:
    /// - SOP Class UID present and valid
    /// - SOP Instance UID present and valid
    case minimal
    
    /// Standard validation for most use cases
    ///
    /// Checks everything in minimal, plus:
    /// - Study Instance UID present and valid
    /// - Series Instance UID present and valid
    /// - Patient ID present
    /// - Modality present
    case standard
    
    /// Strict validation for production environments
    ///
    /// Checks everything in standard, plus:
    /// - Transfer Syntax validation
    /// - All UIDs have valid format
    /// - Required Type 1 and Type 1C attributes
    /// - Pixel data consistency (if present)
    case strict
}

extension ValidationLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .minimal:
            return "minimal"
        case .standard:
            return "standard"
        case .strict:
            return "strict"
        }
    }
}

// MARK: - Validation Configuration

/// Configuration for DICOM validation
///
/// Allows customization of validation behavior including
/// which checks to perform and how strict to be.
///
/// ## Usage
///
/// ```swift
/// // Use default configuration
/// let config = ValidationConfiguration()
///
/// // Strict validation for production
/// let strictConfig = ValidationConfiguration(
///     level: .strict,
///     validateTransferSyntax: true,
///     validatePixelData: true
/// )
///
/// // Lenient validation for testing
/// let lenientConfig = ValidationConfiguration(
///     level: .minimal,
///     treatWarningsAsErrors: false
/// )
/// ```
public struct ValidationConfiguration: Sendable, Hashable {
    /// The validation level
    public let level: ValidationLevel
    
    /// Whether to validate the Transfer Syntax UID
    public let validateTransferSyntax: Bool
    
    /// Whether to validate pixel data attributes if pixel data is present
    public let validatePixelData: Bool
    
    /// Whether to treat warnings as errors
    public let treatWarningsAsErrors: Bool
    
    /// Optional list of SOP Classes to accept (empty = accept all)
    public let allowedSOPClasses: Set<String>
    
    /// Optional list of additional required tags
    public let additionalRequiredTags: Set<Tag>
    
    /// Creates a validation configuration
    ///
    /// - Parameters:
    ///   - level: Validation strictness level (default: .standard)
    ///   - validateTransferSyntax: Whether to validate Transfer Syntax (default: false)
    ///   - validatePixelData: Whether to validate pixel data attributes (default: true)
    ///   - treatWarningsAsErrors: Whether warnings should fail validation (default: false)
    ///   - allowedSOPClasses: Allowed SOP Classes, empty for all (default: empty)
    ///   - additionalRequiredTags: Additional tags to require (default: empty)
    public init(
        level: ValidationLevel = .standard,
        validateTransferSyntax: Bool = false,
        validatePixelData: Bool = true,
        treatWarningsAsErrors: Bool = false,
        allowedSOPClasses: Set<String> = [],
        additionalRequiredTags: Set<Tag> = []
    ) {
        self.level = level
        self.validateTransferSyntax = validateTransferSyntax
        self.validatePixelData = validatePixelData
        self.treatWarningsAsErrors = treatWarningsAsErrors
        self.allowedSOPClasses = allowedSOPClasses
        self.additionalRequiredTags = additionalRequiredTags
    }
    
    // MARK: - Presets
    
    /// Default configuration for most use cases
    public static let `default` = ValidationConfiguration()
    
    /// Minimal validation - only checks critical attributes
    public static let minimal = ValidationConfiguration(
        level: .minimal,
        validateTransferSyntax: false,
        validatePixelData: false
    )
    
    /// Strict validation for production environments
    public static let strict = ValidationConfiguration(
        level: .strict,
        validateTransferSyntax: true,
        validatePixelData: true,
        treatWarningsAsErrors: true
    )
}

extension ValidationConfiguration: CustomStringConvertible {
    public var description: String {
        var parts = ["ValidationConfiguration(level: \(level)"]
        if validateTransferSyntax {
            parts.append("validateTS")
        }
        if validatePixelData {
            parts.append("validatePD")
        }
        if treatWarningsAsErrors {
            parts.append("warningsAsErrors")
        }
        if !allowedSOPClasses.isEmpty {
            parts.append("\(allowedSOPClasses.count) allowed SOP Classes")
        }
        if !additionalRequiredTags.isEmpty {
            parts.append("\(additionalRequiredTags.count) additional tags")
        }
        return parts.joined(separator: ", ") + ")"
    }
}

// MARK: - DICOM Validator

/// Validates DICOM data sets before network operations
///
/// `DICOMValidator` provides comprehensive validation of DICOM objects
/// to ensure they meet requirements before being sent to a PACS or
/// other DICOM destination.
///
/// ## Usage
///
/// ```swift
/// let validator = DICOMValidator()
///
/// // Validate with default configuration
/// let result = validator.validate(dataSet)
/// if !result.isValid {
///     for error in result.errors {
///         print("Validation error: \(error)")
///     }
/// }
///
/// // Validate with strict configuration
/// let strictResult = validator.validate(dataSet, configuration: .strict)
/// ```
///
/// ## Validation Levels
///
/// - **Minimal**: Only SOP Class UID and SOP Instance UID
/// - **Standard**: Adds Study/Series UIDs, Patient ID, Modality
/// - **Strict**: Full validation including pixel data consistency
///
/// Reference: PS3.3 - Information Object Definitions
/// Reference: PS3.4 - Service Class Specifications
public struct DICOMValidator: Sendable {
    
    // MARK: - Known UIDs
    
    /// Known Storage SOP Class UIDs.
    ///
    /// Sourced from the package-wide canonical registry
    /// (`StorageSOPClass.allUIDSet` in `DICOMDictionary`) so validation,
    /// C-GET negotiation and the Storage SCP all recognise the same set of
    /// storage objects — see ``StorageSOPClass``.
    private static let knownStorageSOPClasses: Set<String> = StorageSOPClass.allUIDSet
    
    /// Known Transfer Syntax UIDs.
    ///
    /// Sourced from DICOMCore's registry (`TransferSyntax.allKnown`, PS3.6
    /// Table A-1 plus the fragmentable video variants of PS3.5 Annex A.4
    /// (video transfer syntaxes)) so the validator recognises every registered
    /// syntax — JPEG XL, Encapsulated Uncompressed, Deflated Image Frame
    /// Compression, SMPTE ST 2110, JPIP, the retired JPEG processes, RFC 2557
    /// and Papyrus 3 — instead of a hand-maintained subset.
    private static let knownTransferSyntaxes: Set<String> = Set(TransferSyntax.allKnown.map(\.uid))

    // MARK: - Initialization
    
    /// Creates a new DICOM validator
    public init() {}
    
    // MARK: - Validation Methods
    
    /// Validates a DICOM data set using a DataSet-like interface
    ///
    /// This method accepts any type that can provide string values for tags
    /// and data for the pixel data tag, making it compatible with the
    /// DICOMKit DataSet type.
    ///
    /// - Parameters:
    ///   - getString: Function to get a string value for a tag
    ///   - getData: Function to get raw data for a tag
    ///   - configuration: Validation configuration to use
    /// - Returns: The validation result
    public func validate(
        getString: (Tag) -> String?,
        getData: (Tag) -> Data?,
        configuration: ValidationConfiguration = .default
    ) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationError] = []
        
        // Validate based on level
        switch configuration.level {
        case .minimal:
            validateMinimal(getString: getString, errors: &errors, warnings: &warnings)
            
        case .standard:
            validateMinimal(getString: getString, errors: &errors, warnings: &warnings)
            validateStandard(getString: getString, errors: &errors, warnings: &warnings)
            
        case .strict:
            validateMinimal(getString: getString, errors: &errors, warnings: &warnings)
            validateStandard(getString: getString, errors: &errors, warnings: &warnings)
            validateStrict(getString: getString, getData: getData, errors: &errors, warnings: &warnings)
        }
        
        // Validate Transfer Syntax if requested
        if configuration.validateTransferSyntax {
            validateTransferSyntax(getString: getString, errors: &errors, warnings: &warnings)
        }
        
        // Validate pixel data if requested and present
        if configuration.validatePixelData {
            validatePixelDataAttributes(getString: getString, getData: getData, errors: &errors, warnings: &warnings)
        }
        
        // Check allowed SOP Classes if specified
        if !configuration.allowedSOPClasses.isEmpty {
            if let sopClassUID = getString(.sopClassUID) {
                if !configuration.allowedSOPClasses.contains(sopClassUID) {
                    errors.append(.unknownSOPClass(sopClassUID: sopClassUID))
                }
            }
        }
        
        // Check additional required tags
        for tag in configuration.additionalRequiredTags {
            if getString(tag) == nil && getData(tag) == nil {
                errors.append(.missingRequiredAttribute(tag: tag, description: "Additional required attribute"))
            }
        }
        
        // Handle warnings as errors if configured
        if configuration.treatWarningsAsErrors {
            errors.append(contentsOf: warnings)
            warnings = []
        }
        
        // Return result
        if errors.isEmpty {
            return warnings.isEmpty ? .success : .successWithWarnings(warnings)
        } else {
            return .failure(errors: errors, warnings: warnings)
        }
    }
    
    // MARK: - Minimal Validation
    
    private func validateMinimal(
        getString: (Tag) -> String?,
        errors: inout [ValidationError],
        warnings: inout [ValidationError]
    ) {
        // SOP Class UID (Type 1)
        if let sopClassUID = getString(.sopClassUID) {
            if sopClassUID.isEmpty {
                errors.append(.emptyValue(tag: .sopClassUID, description: "SOP Class UID"))
            } else if DICOMUniqueIdentifier.parse(sopClassUID) == nil {
                errors.append(.invalidUID(tag: .sopClassUID, value: sopClassUID, reason: "Invalid UID format"))
            }
        } else {
            errors.append(.missingRequiredAttribute(tag: .sopClassUID, description: "SOP Class UID"))
        }
        
        // SOP Instance UID (Type 1)
        if let sopInstanceUID = getString(.sopInstanceUID) {
            if sopInstanceUID.isEmpty {
                errors.append(.emptyValue(tag: .sopInstanceUID, description: "SOP Instance UID"))
            } else if DICOMUniqueIdentifier.parse(sopInstanceUID) == nil {
                errors.append(.invalidUID(tag: .sopInstanceUID, value: sopInstanceUID, reason: "Invalid UID format"))
            }
        } else {
            errors.append(.missingRequiredAttribute(tag: .sopInstanceUID, description: "SOP Instance UID"))
        }
    }
    
    // MARK: - Standard Validation
    
    private func validateStandard(
        getString: (Tag) -> String?,
        errors: inout [ValidationError],
        warnings: inout [ValidationError]
    ) {
        // Study Instance UID (Type 1)
        if let studyInstanceUID = getString(.studyInstanceUID) {
            if studyInstanceUID.isEmpty {
                errors.append(.emptyValue(tag: .studyInstanceUID, description: "Study Instance UID"))
            } else if DICOMUniqueIdentifier.parse(studyInstanceUID) == nil {
                errors.append(.invalidUID(tag: .studyInstanceUID, value: studyInstanceUID, reason: "Invalid UID format"))
            }
        } else {
            errors.append(.missingRequiredAttribute(tag: .studyInstanceUID, description: "Study Instance UID"))
        }
        
        // Series Instance UID (Type 1)
        if let seriesInstanceUID = getString(.seriesInstanceUID) {
            if seriesInstanceUID.isEmpty {
                errors.append(.emptyValue(tag: .seriesInstanceUID, description: "Series Instance UID"))
            } else if DICOMUniqueIdentifier.parse(seriesInstanceUID) == nil {
                errors.append(.invalidUID(tag: .seriesInstanceUID, value: seriesInstanceUID, reason: "Invalid UID format"))
            }
        } else {
            errors.append(.missingRequiredAttribute(tag: .seriesInstanceUID, description: "Series Instance UID"))
        }
        
        // Patient ID (Type 2 - should be present but can be empty)
        if getString(.patientID) == nil {
            warnings.append(.missingRequiredAttribute(tag: .patientID, description: "Patient ID"))
        }
        
        // Modality (Type 1 for most IODs)
        if let modality = getString(.modality) {
            if modality.isEmpty {
                warnings.append(.emptyValue(tag: .modality, description: "Modality"))
            }
        } else {
            warnings.append(.missingRequiredAttribute(tag: .modality, description: "Modality"))
        }
    }
    
    // MARK: - Strict Validation
    
    private func validateStrict(
        getString: (Tag) -> String?,
        getData: (Tag) -> Data?,
        errors: inout [ValidationError],
        warnings: inout [ValidationError]
    ) {
        // Verify SOP Class is known
        if let sopClassUID = getString(.sopClassUID) {
            if !Self.knownStorageSOPClasses.contains(sopClassUID) {
                // Check if it looks like a valid UID structure at least
                if DICOMUniqueIdentifier.parse(sopClassUID) != nil {
                    // Valid UID but not in our list - just warn
                    warnings.append(.unknownSOPClass(sopClassUID: sopClassUID))
                }
            }
        }
        
        // Additional Type 2 attributes that should be present
        let type2Attributes: [(Tag, String)] = [
            (.patientName, "Patient Name"),
            (.patientBirthDate, "Patient Birth Date"),
            (.patientSex, "Patient Sex"),
            (.studyDate, "Study Date"),
            (.studyTime, "Study Time"),
            (.seriesNumber, "Series Number"),
            (.instanceNumber, "Instance Number")
        ]
        
        for (tag, description) in type2Attributes {
            if getString(tag) == nil {
                warnings.append(.missingRequiredAttribute(tag: tag, description: description))
            }
        }
    }
    
    // MARK: - Transfer Syntax Validation
    
    private func validateTransferSyntax(
        getString: (Tag) -> String?,
        errors: inout [ValidationError],
        warnings: inout [ValidationError]
    ) {
        if let transferSyntaxUID = getString(.transferSyntaxUID) {
            if transferSyntaxUID.isEmpty {
                warnings.append(.emptyValue(tag: .transferSyntaxUID, description: "Transfer Syntax UID"))
            } else if DICOMUniqueIdentifier.parse(transferSyntaxUID) == nil {
                errors.append(.invalidUID(tag: .transferSyntaxUID, value: transferSyntaxUID, reason: "Invalid UID format"))
            } else if !Self.knownTransferSyntaxes.contains(transferSyntaxUID) {
                warnings.append(.unknownTransferSyntax(transferSyntaxUID: transferSyntaxUID))
            }
        }
        // Transfer Syntax is in File Meta Information, may not always be present
    }
    
    // MARK: - Pixel Data Validation
    
    private func validatePixelDataAttributes(
        getString: (Tag) -> String?,
        getData: (Tag) -> Data?,
        errors: inout [ValidationError],
        warnings: inout [ValidationError]
    ) {
        // Check if pixel data is present
        guard getData(.pixelData) != nil else {
            // No pixel data present, skip validation
            return
        }
        
        // Required attributes for pixel data
        var missingTags: [Tag] = []
        
        // Rows
        if getString(.rows) == nil {
            missingTags.append(.rows)
        }
        
        // Columns
        if getString(.columns) == nil {
            missingTags.append(.columns)
        }
        
        // Bits Allocated
        if getString(.bitsAllocated) == nil {
            missingTags.append(.bitsAllocated)
        }
        
        // Bits Stored
        if getString(.bitsStored) == nil {
            missingTags.append(.bitsStored)
        }
        
        // High Bit
        if getString(.highBit) == nil {
            missingTags.append(.highBit)
        }
        
        // Pixel Representation
        if getString(.pixelRepresentation) == nil {
            missingTags.append(.pixelRepresentation)
        }
        
        // Samples Per Pixel
        if getString(.samplesPerPixel) == nil {
            missingTags.append(.samplesPerPixel)
        }
        
        // Photometric Interpretation
        if getString(.photometricInterpretation) == nil {
            missingTags.append(.photometricInterpretation)
        }
        
        if !missingTags.isEmpty {
            errors.append(.incompletePixelData(missingTags: missingTags))
        }
    }
    
    // MARK: - UID Validation Helper
    
    /// Validates a UID string
    ///
    /// - Parameter uid: The UID string to validate
    /// - Returns: true if the UID is valid
    public func isValidUID(_ uid: String) -> Bool {
        DICOMUniqueIdentifier.parse(uid) != nil
    }
}
