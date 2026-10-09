import Foundation

/// DICOM Unique Identifier (UI) value representation
///
/// Represents a DICOM UID with validation and component access.
/// Reference: DICOM PS3.5 Section 6.2 - UI Value Representation
///
/// A DICOM UID is a string of numeric components separated by periods (dots).
/// Each component is a decimal number, and the total UID length must not exceed 64 characters.
///
/// UID Structure:
/// - Consists of numeric components separated by periods
/// - Each component is an unsigned integer (no leading zeros except for component "0")
/// - Maximum total length is 64 characters
///
/// Common UID Roots:
/// - "1.2.840.10008" - DICOM standard UIDs
/// - "1.2.840.113619" - GE Healthcare
/// - "1.3.6.1.4.1" - IANA-assigned private enterprise numbers
///
/// Reference: DICOM PS3.5 Section 9 - Unique Identifiers (UIDs)
///
/// NEMA-verified: 2026a, checked 2026-09-25 — `parse` enforces the UI row of PS3.5 2026a Table
/// 6.2-1 and every rule of §9.1; `transferSyntaxUIDs` and `sopClassUIDs` are generated
/// from PS3.6 2026a Table A-1 (63 Transfer Syntaxes, 311 SOP Classes).
///
/// Examples:
/// - "1.2.840.10008.1.2" = Implicit VR Little Endian Transfer Syntax
/// - "1.2.840.10008.5.1.4.1.1.2" = CT Image Storage SOP Class
/// - "1.2.840.113619.2.5.1762583153.215519.978957063.78" = Instance UID
public struct DICOMUniqueIdentifier: Sendable, Hashable {
    /// Maximum allowed length for a UID per DICOM PS3.5 Section 9.1
    public static let maximumLength = 64
    
    /// DICOM standard UID root
    public static let dicomRoot = "1.2.840.10008"
    
    /// The raw UID string value
    public let value: String
    
    /// The numeric components of the UID
    public let components: [String]
    
    /// Creates a DICOM Unique Identifier from a validated UID string
    /// - Parameters:
    ///   - value: The UID string value
    ///   - components: The parsed numeric components
    private init(value: String, components: [String]) {
        self.value = value
        self.components = components
    }
    
    /// Parses a DICOM UID string into a DICOMUniqueIdentifier
    ///
    /// Validates the UID format per DICOM PS3.5 Section 9.1:
    /// - Maximum length of 64 characters
    /// - Contains only digits (0-9) and periods (.)
    /// - Does not start or end with a period
    /// - No consecutive periods
    /// - Each component is a valid unsigned integer
    /// - Leading zeros are not permitted except for the component "0"
    ///
    /// Reference: DICOM PS3.5 Section 9.1 - UID Encoding Rules
    ///
    /// - Parameter string: The UID string to parse
    /// - Returns: A DICOMUniqueIdentifier if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMUniqueIdentifier? {
        // Trim whitespace and null padding (common in DICOM)
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        // Empty string is invalid
        guard !trimmed.isEmpty else {
            return nil
        }
        
        // Check maximum length per PS3.5 Section 9.1
        guard trimmed.count <= maximumLength else {
            return nil
        }
        
        // Must contain only ASCII digits and periods (DICOM UIDs are ASCII 0-9;
        // CharacterSet.decimalDigits would also admit non-ASCII Unicode digits).
        let validCharacters = CharacterSet(charactersIn: "0123456789.")
        guard trimmed.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            return nil
        }
        
        // Must not start or end with period
        guard !trimmed.hasPrefix(".") && !trimmed.hasSuffix(".") else {
            return nil
        }
        
        // Must not have consecutive periods
        guard !trimmed.contains("..") else {
            return nil
        }
        
        // Parse components
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            .map { String($0) }
        
        // Must have at least one component
        guard !components.isEmpty else {
            return nil
        }
        
        // Validate each component
        for component in components {
            // Must not be empty
            guard !component.isEmpty else {
                return nil
            }
            
            // Leading zeros are not permitted except for "0" itself
            // Reference: PS3.5 Section 9.1
            if component.count > 1 && component.hasPrefix("0") {
                return nil
            }
            
            // Must be a valid unsigned integer (parseable), ASCII digits only.
            // Note: We allow very large numbers as they're just stored as strings
            guard component.allSatisfy({ ("0"..."9").contains($0) }) else {
                return nil
            }
        }
        
        return DICOMUniqueIdentifier(value: trimmed, components: components)
    }
    
    /// Parses multiple DICOM UID values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The string containing multiple UIDs
    /// - Returns: Array of parsed UIDs, or nil if any parsing fails
    public static func parseMultiple(_ string: String) -> [DICOMUniqueIdentifier]? {
        let values = string.split(separator: "\\", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        
        let parsed = values.compactMap { parse($0) }
        
        // Return nil if not all values could be parsed
        guard parsed.count == values.count else {
            return nil
        }
        
        return parsed.isEmpty ? nil : parsed
    }
    
    // MARK: - Component Access
    
    /// Returns the UID root (typically the first few components identifying the organization)
    ///
    /// For standard DICOM UIDs, this is "1.2.840.10008"
    /// For other UIDs, this returns the first 4 components if available
    public var root: String {
        if value.hasPrefix(Self.dicomRoot) {
            return Self.dicomRoot
        }
        
        // Return first 4 components as root (common convention)
        let rootComponents = Array(components.prefix(4))
        return rootComponents.joined(separator: ".")
    }
    
    /// Returns the suffix after the root (the unique part of the UID)
    ///
    /// For standard DICOM UIDs, this is everything after "1.2.840.10008."
    public var suffix: String? {
        if value.hasPrefix(Self.dicomRoot + ".") {
            let startIndex = value.index(value.startIndex, offsetBy: Self.dicomRoot.count + 1)
            return String(value[startIndex...])
        }
        
        // For non-DICOM UIDs, return everything after the first 4 components
        if components.count > 4 {
            return components.dropFirst(4).joined(separator: ".")
        }
        
        return nil
    }
    
    /// The number of components in this UID
    public var componentCount: Int {
        return components.count
    }
    
    // MARK: - UID Type Detection
    
    /// Indicates whether this is a standard DICOM UID (starts with 1.2.840.10008)
    ///
    /// Reference: DICOM PS3.5 Section 9 - Standard DICOM UID root
    public var isStandardDICOM: Bool {
        return value.hasPrefix(Self.dicomRoot)
    }
    
    /// The 63 Transfer Syntax UIDs of PS3.6 2026a Table A-1 (including retired ones).
    ///
    /// Generated from the standard's text; regenerate when the target edition changes.
    public static let transferSyntaxUIDs: Set<String> = [
        "1.2.840.10008.1.2",
        "1.2.840.10008.1.2.1",
        "1.2.840.10008.1.2.1.98",
        "1.2.840.10008.1.2.1.99",
        "1.2.840.10008.1.2.2",
        "1.2.840.10008.1.2.4.50",
        "1.2.840.10008.1.2.4.51",
        "1.2.840.10008.1.2.4.52",
        "1.2.840.10008.1.2.4.53",
        "1.2.840.10008.1.2.4.54",
        "1.2.840.10008.1.2.4.55",
        "1.2.840.10008.1.2.4.56",
        "1.2.840.10008.1.2.4.57",
        "1.2.840.10008.1.2.4.58",
        "1.2.840.10008.1.2.4.59",
        "1.2.840.10008.1.2.4.60",
        "1.2.840.10008.1.2.4.61",
        "1.2.840.10008.1.2.4.62",
        "1.2.840.10008.1.2.4.63",
        "1.2.840.10008.1.2.4.64",
        "1.2.840.10008.1.2.4.65",
        "1.2.840.10008.1.2.4.66",
        "1.2.840.10008.1.2.4.70",
        "1.2.840.10008.1.2.4.80",
        "1.2.840.10008.1.2.4.81",
        "1.2.840.10008.1.2.4.90",
        "1.2.840.10008.1.2.4.91",
        "1.2.840.10008.1.2.4.92",
        "1.2.840.10008.1.2.4.93",
        "1.2.840.10008.1.2.4.94",
        "1.2.840.10008.1.2.4.95",
        "1.2.840.10008.1.2.4.100",
        "1.2.840.10008.1.2.4.100.1",
        "1.2.840.10008.1.2.4.101",
        "1.2.840.10008.1.2.4.101.1",
        "1.2.840.10008.1.2.4.102",
        "1.2.840.10008.1.2.4.102.1",
        "1.2.840.10008.1.2.4.103",
        "1.2.840.10008.1.2.4.103.1",
        "1.2.840.10008.1.2.4.104",
        "1.2.840.10008.1.2.4.104.1",
        "1.2.840.10008.1.2.4.105",
        "1.2.840.10008.1.2.4.105.1",
        "1.2.840.10008.1.2.4.106",
        "1.2.840.10008.1.2.4.106.1",
        "1.2.840.10008.1.2.4.107",
        "1.2.840.10008.1.2.4.108",
        "1.2.840.10008.1.2.4.110",
        "1.2.840.10008.1.2.4.111",
        "1.2.840.10008.1.2.4.112",
        "1.2.840.10008.1.2.4.201",
        "1.2.840.10008.1.2.4.202",
        "1.2.840.10008.1.2.4.203",
        "1.2.840.10008.1.2.4.204",
        "1.2.840.10008.1.2.4.205",
        "1.2.840.10008.1.2.5",
        "1.2.840.10008.1.2.6.1",
        "1.2.840.10008.1.2.6.2",
        "1.2.840.10008.1.2.7.1",
        "1.2.840.10008.1.2.7.2",
        "1.2.840.10008.1.2.7.3",
        "1.2.840.10008.1.2.8.1",
        "1.2.840.10008.1.20",
    ]

    /// The 311 SOP Class UIDs of PS3.6 2026a Table A-1 (including retired ones).
    ///
    /// Meta SOP Classes, Service Classes and Well-known SOP Instances are not SOP
    /// Classes and are not in this set. Generated from the standard's text.
    public static let sopClassUIDs: Set<String> = [
        "1.2.840.10008.1.1",
        "1.2.840.10008.1.3.10",
        "1.2.840.10008.1.9",
        "1.2.840.10008.1.20.1",
        "1.2.840.10008.1.20.2",
        "1.2.840.10008.1.40",
        "1.2.840.10008.1.42",
        "1.2.840.10008.3.1.2.1.1",
        "1.2.840.10008.3.1.2.2.1",
        "1.2.840.10008.3.1.2.3.1",
        "1.2.840.10008.3.1.2.3.2",
        "1.2.840.10008.3.1.2.3.3",
        "1.2.840.10008.3.1.2.3.4",
        "1.2.840.10008.3.1.2.3.5",
        "1.2.840.10008.3.1.2.5.1",
        "1.2.840.10008.3.1.2.6.1",
        "1.2.840.10008.5.1.1.1",
        "1.2.840.10008.5.1.1.2",
        "1.2.840.10008.5.1.1.4",
        "1.2.840.10008.5.1.1.4.1",
        "1.2.840.10008.5.1.1.4.2",
        "1.2.840.10008.5.1.1.14",
        "1.2.840.10008.5.1.1.15",
        "1.2.840.10008.5.1.1.16",
        "1.2.840.10008.5.1.1.16.376",
        "1.2.840.10008.5.1.1.22",
        "1.2.840.10008.5.1.1.23",
        "1.2.840.10008.5.1.1.24",
        "1.2.840.10008.5.1.1.24.1",
        "1.2.840.10008.5.1.1.26",
        "1.2.840.10008.5.1.1.27",
        "1.2.840.10008.5.1.1.29",
        "1.2.840.10008.5.1.1.30",
        "1.2.840.10008.5.1.1.31",
        "1.2.840.10008.5.1.1.33",
        "1.2.840.10008.5.1.1.40",
        "1.2.840.10008.5.1.4.1.1.1",
        "1.2.840.10008.5.1.4.1.1.1.1",
        "1.2.840.10008.5.1.4.1.1.1.1.1",
        "1.2.840.10008.5.1.4.1.1.1.2",
        "1.2.840.10008.5.1.4.1.1.1.2.1",
        "1.2.840.10008.5.1.4.1.1.1.3",
        "1.2.840.10008.5.1.4.1.1.1.3.1",
        "1.2.840.10008.5.1.4.1.1.2",
        "1.2.840.10008.5.1.4.1.1.2.1",
        "1.2.840.10008.5.1.4.1.1.2.2",
        "1.2.840.10008.5.1.4.1.1.3",
        "1.2.840.10008.5.1.4.1.1.3.1",
        "1.2.840.10008.5.1.4.1.1.4",
        "1.2.840.10008.5.1.4.1.1.4.1",
        "1.2.840.10008.5.1.4.1.1.4.2",
        "1.2.840.10008.5.1.4.1.1.4.3",
        "1.2.840.10008.5.1.4.1.1.4.4",
        "1.2.840.10008.5.1.4.1.1.5",
        "1.2.840.10008.5.1.4.1.1.6",
        "1.2.840.10008.5.1.4.1.1.6.1",
        "1.2.840.10008.5.1.4.1.1.6.2",
        "1.2.840.10008.5.1.4.1.1.6.3",
        "1.2.840.10008.5.1.4.1.1.7",
        "1.2.840.10008.5.1.4.1.1.7.1",
        "1.2.840.10008.5.1.4.1.1.7.2",
        "1.2.840.10008.5.1.4.1.1.7.3",
        "1.2.840.10008.5.1.4.1.1.7.4",
        "1.2.840.10008.5.1.4.1.1.8",
        "1.2.840.10008.5.1.4.1.1.9",
        "1.2.840.10008.5.1.4.1.1.9.1",
        "1.2.840.10008.5.1.4.1.1.9.1.1",
        "1.2.840.10008.5.1.4.1.1.9.1.2",
        "1.2.840.10008.5.1.4.1.1.9.1.3",
        "1.2.840.10008.5.1.4.1.1.9.1.4",
        "1.2.840.10008.5.1.4.1.1.9.2.1",
        "1.2.840.10008.5.1.4.1.1.9.3.1",
        "1.2.840.10008.5.1.4.1.1.9.4.1",
        "1.2.840.10008.5.1.4.1.1.9.4.2",
        "1.2.840.10008.5.1.4.1.1.9.5.1",
        "1.2.840.10008.5.1.4.1.1.9.6.1",
        "1.2.840.10008.5.1.4.1.1.9.6.2",
        "1.2.840.10008.5.1.4.1.1.9.7.1",
        "1.2.840.10008.5.1.4.1.1.9.7.2",
        "1.2.840.10008.5.1.4.1.1.9.7.3",
        "1.2.840.10008.5.1.4.1.1.9.7.4",
        "1.2.840.10008.5.1.4.1.1.9.8.1",
        "1.2.840.10008.5.1.4.1.1.9.100.1",
        "1.2.840.10008.5.1.4.1.1.9.100.2",
        "1.2.840.10008.5.1.4.1.1.10",
        "1.2.840.10008.5.1.4.1.1.11",
        "1.2.840.10008.5.1.4.1.1.11.1",
        "1.2.840.10008.5.1.4.1.1.11.2",
        "1.2.840.10008.5.1.4.1.1.11.3",
        "1.2.840.10008.5.1.4.1.1.11.4",
        "1.2.840.10008.5.1.4.1.1.11.5",
        "1.2.840.10008.5.1.4.1.1.11.6",
        "1.2.840.10008.5.1.4.1.1.11.7",
        "1.2.840.10008.5.1.4.1.1.11.8",
        "1.2.840.10008.5.1.4.1.1.11.9",
        "1.2.840.10008.5.1.4.1.1.11.10",
        "1.2.840.10008.5.1.4.1.1.11.11",
        "1.2.840.10008.5.1.4.1.1.11.12",
        "1.2.840.10008.5.1.4.1.1.12.1",
        "1.2.840.10008.5.1.4.1.1.12.1.1",
        "1.2.840.10008.5.1.4.1.1.12.2",
        "1.2.840.10008.5.1.4.1.1.12.2.1",
        "1.2.840.10008.5.1.4.1.1.12.3",
        "1.2.840.10008.5.1.4.1.1.12.77",
        "1.2.840.10008.5.1.4.1.1.13.1.1",
        "1.2.840.10008.5.1.4.1.1.13.1.2",
        "1.2.840.10008.5.1.4.1.1.13.1.3",
        "1.2.840.10008.5.1.4.1.1.13.1.4",
        "1.2.840.10008.5.1.4.1.1.13.1.5",
        "1.2.840.10008.5.1.4.1.1.14.1",
        "1.2.840.10008.5.1.4.1.1.14.2",
        "1.2.840.10008.5.1.4.1.1.20",
        "1.2.840.10008.5.1.4.1.1.30",
        "1.2.840.10008.5.1.4.1.1.40",
        "1.2.840.10008.5.1.4.1.1.66",
        "1.2.840.10008.5.1.4.1.1.66.1",
        "1.2.840.10008.5.1.4.1.1.66.2",
        "1.2.840.10008.5.1.4.1.1.66.3",
        "1.2.840.10008.5.1.4.1.1.66.4",
        "1.2.840.10008.5.1.4.1.1.66.5",
        "1.2.840.10008.5.1.4.1.1.66.6",
        "1.2.840.10008.5.1.4.1.1.66.7",
        "1.2.840.10008.5.1.4.1.1.66.8",
        "1.2.840.10008.5.1.4.1.1.67",
        "1.2.840.10008.5.1.4.1.1.68.1",
        "1.2.840.10008.5.1.4.1.1.68.2",
        "1.2.840.10008.5.1.4.1.1.77.1",
        "1.2.840.10008.5.1.4.1.1.77.2",
        "1.2.840.10008.5.1.4.1.1.77.1.1",
        "1.2.840.10008.5.1.4.1.1.77.1.1.1",
        "1.2.840.10008.5.1.4.1.1.77.1.2",
        "1.2.840.10008.5.1.4.1.1.77.1.2.1",
        "1.2.840.10008.5.1.4.1.1.77.1.3",
        "1.2.840.10008.5.1.4.1.1.77.1.4",
        "1.2.840.10008.5.1.4.1.1.77.1.4.1",
        "1.2.840.10008.5.1.4.1.1.77.1.5.1",
        "1.2.840.10008.5.1.4.1.1.77.1.5.2",
        "1.2.840.10008.5.1.4.1.1.77.1.5.3",
        "1.2.840.10008.5.1.4.1.1.77.1.5.4",
        "1.2.840.10008.5.1.4.1.1.77.1.5.5",
        "1.2.840.10008.5.1.4.1.1.77.1.5.6",
        "1.2.840.10008.5.1.4.1.1.77.1.5.7",
        "1.2.840.10008.5.1.4.1.1.77.1.5.8",
        "1.2.840.10008.5.1.4.1.1.77.1.6",
        "1.2.840.10008.5.1.4.1.1.77.1.7",
        "1.2.840.10008.5.1.4.1.1.77.1.8",
        "1.2.840.10008.5.1.4.1.1.77.1.9",
        "1.2.840.10008.5.1.4.1.1.78.1",
        "1.2.840.10008.5.1.4.1.1.78.2",
        "1.2.840.10008.5.1.4.1.1.78.3",
        "1.2.840.10008.5.1.4.1.1.78.4",
        "1.2.840.10008.5.1.4.1.1.78.5",
        "1.2.840.10008.5.1.4.1.1.78.6",
        "1.2.840.10008.5.1.4.1.1.78.7",
        "1.2.840.10008.5.1.4.1.1.78.8",
        "1.2.840.10008.5.1.4.1.1.79.1",
        "1.2.840.10008.5.1.4.1.1.80.1",
        "1.2.840.10008.5.1.4.1.1.81.1",
        "1.2.840.10008.5.1.4.1.1.82.1",
        "1.2.840.10008.5.1.4.1.1.88.1",
        "1.2.840.10008.5.1.4.1.1.88.2",
        "1.2.840.10008.5.1.4.1.1.88.3",
        "1.2.840.10008.5.1.4.1.1.88.4",
        "1.2.840.10008.5.1.4.1.1.88.11",
        "1.2.840.10008.5.1.4.1.1.88.22",
        "1.2.840.10008.5.1.4.1.1.88.33",
        "1.2.840.10008.5.1.4.1.1.88.34",
        "1.2.840.10008.5.1.4.1.1.88.35",
        "1.2.840.10008.5.1.4.1.1.88.40",
        "1.2.840.10008.5.1.4.1.1.88.50",
        "1.2.840.10008.5.1.4.1.1.88.59",
        "1.2.840.10008.5.1.4.1.1.88.65",
        "1.2.840.10008.5.1.4.1.1.88.67",
        "1.2.840.10008.5.1.4.1.1.88.68",
        "1.2.840.10008.5.1.4.1.1.88.69",
        "1.2.840.10008.5.1.4.1.1.88.70",
        "1.2.840.10008.5.1.4.1.1.88.71",
        "1.2.840.10008.5.1.4.1.1.88.72",
        "1.2.840.10008.5.1.4.1.1.88.73",
        "1.2.840.10008.5.1.4.1.1.88.74",
        "1.2.840.10008.5.1.4.1.1.88.75",
        "1.2.840.10008.5.1.4.1.1.88.76",
        "1.2.840.10008.5.1.4.1.1.88.77",
        "1.2.840.10008.5.1.4.1.1.90.1",
        "1.2.840.10008.5.1.4.1.1.91.1",
        "1.2.840.10008.5.1.4.1.1.104.1",
        "1.2.840.10008.5.1.4.1.1.104.2",
        "1.2.840.10008.5.1.4.1.1.104.3",
        "1.2.840.10008.5.1.4.1.1.104.4",
        "1.2.840.10008.5.1.4.1.1.104.5",
        "1.2.840.10008.5.1.4.1.1.128",
        "1.2.840.10008.5.1.4.1.1.128.1",
        "1.2.840.10008.5.1.4.1.1.129",
        "1.2.840.10008.5.1.4.1.1.130",
        "1.2.840.10008.5.1.4.1.1.131",
        "1.2.840.10008.5.1.4.1.1.200.1",
        "1.2.840.10008.5.1.4.1.1.200.2",
        "1.2.840.10008.5.1.4.1.1.200.3",
        "1.2.840.10008.5.1.4.1.1.200.4",
        "1.2.840.10008.5.1.4.1.1.200.5",
        "1.2.840.10008.5.1.4.1.1.200.6",
        "1.2.840.10008.5.1.4.1.1.200.7",
        "1.2.840.10008.5.1.4.1.1.200.8",
        "1.2.840.10008.5.1.4.1.1.201.1",
        "1.2.840.10008.5.1.4.1.1.201.2",
        "1.2.840.10008.5.1.4.1.1.201.3",
        "1.2.840.10008.5.1.4.1.1.201.4",
        "1.2.840.10008.5.1.4.1.1.201.5",
        "1.2.840.10008.5.1.4.1.1.201.6",
        "1.2.840.10008.5.1.4.1.1.481.1",
        "1.2.840.10008.5.1.4.1.1.481.2",
        "1.2.840.10008.5.1.4.1.1.481.3",
        "1.2.840.10008.5.1.4.1.1.481.4",
        "1.2.840.10008.5.1.4.1.1.481.5",
        "1.2.840.10008.5.1.4.1.1.481.6",
        "1.2.840.10008.5.1.4.1.1.481.7",
        "1.2.840.10008.5.1.4.1.1.481.8",
        "1.2.840.10008.5.1.4.1.1.481.9",
        "1.2.840.10008.5.1.4.1.1.481.10",
        "1.2.840.10008.5.1.4.1.1.481.11",
        "1.2.840.10008.5.1.4.1.1.481.12",
        "1.2.840.10008.5.1.4.1.1.481.13",
        "1.2.840.10008.5.1.4.1.1.481.14",
        "1.2.840.10008.5.1.4.1.1.481.15",
        "1.2.840.10008.5.1.4.1.1.481.16",
        "1.2.840.10008.5.1.4.1.1.481.17",
        "1.2.840.10008.5.1.4.1.1.481.18",
        "1.2.840.10008.5.1.4.1.1.481.19",
        "1.2.840.10008.5.1.4.1.1.481.20",
        "1.2.840.10008.5.1.4.1.1.481.21",
        "1.2.840.10008.5.1.4.1.1.481.22",
        "1.2.840.10008.5.1.4.1.1.481.23",
        "1.2.840.10008.5.1.4.1.1.481.24",
        "1.2.840.10008.5.1.4.1.1.481.25",
        "1.2.840.10008.5.1.4.1.1.501.1",
        "1.2.840.10008.5.1.4.1.1.501.2.1",
        "1.2.840.10008.5.1.4.1.1.501.2.2",
        "1.2.840.10008.5.1.4.1.1.501.3",
        "1.2.840.10008.5.1.4.1.1.501.4",
        "1.2.840.10008.5.1.4.1.1.501.5",
        "1.2.840.10008.5.1.4.1.1.501.6",
        "1.2.840.10008.5.1.4.1.1.601.1",
        "1.2.840.10008.5.1.4.1.1.601.2",
        "1.2.840.10008.5.1.4.1.1.601.3",
        "1.2.840.10008.5.1.4.1.1.601.4",
        "1.2.840.10008.5.1.4.1.1.601.5",
        "1.2.840.10008.5.1.4.1.2.1.1",
        "1.2.840.10008.5.1.4.1.2.1.2",
        "1.2.840.10008.5.1.4.1.2.1.3",
        "1.2.840.10008.5.1.4.1.2.2.1",
        "1.2.840.10008.5.1.4.1.2.2.2",
        "1.2.840.10008.5.1.4.1.2.2.3",
        "1.2.840.10008.5.1.4.1.2.3.1",
        "1.2.840.10008.5.1.4.1.2.3.2",
        "1.2.840.10008.5.1.4.1.2.3.3",
        "1.2.840.10008.5.1.4.1.2.4.2",
        "1.2.840.10008.5.1.4.1.2.4.3",
        "1.2.840.10008.5.1.4.1.2.5.3",
        "1.2.840.10008.5.1.4.20.1",
        "1.2.840.10008.5.1.4.20.2",
        "1.2.840.10008.5.1.4.20.3",
        "1.2.840.10008.5.1.4.31",
        "1.2.840.10008.5.1.4.32.1",
        "1.2.840.10008.5.1.4.32.2",
        "1.2.840.10008.5.1.4.32.3",
        "1.2.840.10008.5.1.4.33",
        "1.2.840.10008.5.1.4.34.1",
        "1.2.840.10008.5.1.4.34.2",
        "1.2.840.10008.5.1.4.34.3",
        "1.2.840.10008.5.1.4.34.4.1",
        "1.2.840.10008.5.1.4.34.4.2",
        "1.2.840.10008.5.1.4.34.4.3",
        "1.2.840.10008.5.1.4.34.4.4",
        "1.2.840.10008.5.1.4.34.6.1",
        "1.2.840.10008.5.1.4.34.6.2",
        "1.2.840.10008.5.1.4.34.6.3",
        "1.2.840.10008.5.1.4.34.6.4",
        "1.2.840.10008.5.1.4.34.6.5",
        "1.2.840.10008.5.1.4.34.7",
        "1.2.840.10008.5.1.4.34.8",
        "1.2.840.10008.5.1.4.34.9",
        "1.2.840.10008.5.1.4.34.10",
        "1.2.840.10008.5.1.4.37.1",
        "1.2.840.10008.5.1.4.37.2",
        "1.2.840.10008.5.1.4.37.3",
        "1.2.840.10008.5.1.4.38.1",
        "1.2.840.10008.5.1.4.38.2",
        "1.2.840.10008.5.1.4.38.3",
        "1.2.840.10008.5.1.4.38.4",
        "1.2.840.10008.5.1.4.39.1",
        "1.2.840.10008.5.1.4.39.2",
        "1.2.840.10008.5.1.4.39.3",
        "1.2.840.10008.5.1.4.39.4",
        "1.2.840.10008.5.1.4.41",
        "1.2.840.10008.5.1.4.42",
        "1.2.840.10008.5.1.4.43.1",
        "1.2.840.10008.5.1.4.43.2",
        "1.2.840.10008.5.1.4.43.3",
        "1.2.840.10008.5.1.4.43.4",
        "1.2.840.10008.5.1.4.44.1",
        "1.2.840.10008.5.1.4.44.2",
        "1.2.840.10008.5.1.4.44.3",
        "1.2.840.10008.5.1.4.44.4",
        "1.2.840.10008.5.1.4.45.1",
        "1.2.840.10008.5.1.4.45.2",
        "1.2.840.10008.5.1.4.45.3",
        "1.2.840.10008.5.1.4.45.4",
        "1.2.840.10008.10.1",
        "1.2.840.10008.10.2",
        "1.2.840.10008.10.3",
        "1.2.840.10008.10.4",
    ]

    /// Indicates whether this is a standard Transfer Syntax UID
    ///
    /// True exactly for the 63 UIDs registered as Transfer Syntaxes in PS3.6 2026a
    /// Table A-1. Before 2026-09-25 this was a prefix test on "1.2.840.10008.1.2", which
    /// missed the retired Papyrus 3 syntax (1.2.840.10008.1.20).
    public var isTransferSyntax: Bool {
        Self.transferSyntaxUIDs.contains(value)
    }
    
    /// Indicates whether this is a standard SOP Class UID
    ///
    /// True exactly for the 311 UIDs registered as SOP Classes in PS3.6 2026a
    /// Table A-1. Private SOP Classes are not recognised. Before 2026-09-25 this was a
    /// prefix heuristic that missed 28 SOP Classes (Verification, Storage Commitment,
    /// every Print Management class, ...) and matched 10 UIDs that are not SOP Classes
    /// (Meta SOP Classes, Service Classes, Well-known SOP Instances).
    public var isSOPClass: Bool {
        Self.sopClassUIDs.contains(value)
    }
    
    /// Returns the DICOM format string (same as value)
    public var dicomString: String {
        return value
    }
}

// MARK: - Protocol Conformances

extension DICOMUniqueIdentifier: CustomStringConvertible {
    public var description: String {
        return value
    }
}

extension DICOMUniqueIdentifier: ExpressibleByStringLiteral {
    /// Creates a UID from a string literal
    ///
    /// - Note: This will crash if the string is not a valid UID. Use `parse(_:)` for safe parsing.
    public init(stringLiteral value: String) {
        guard let uid = DICOMUniqueIdentifier.parse(value) else {
            fatalError("Invalid DICOM UID: \(value)")
        }
        self = uid
    }
}

extension DICOMUniqueIdentifier: Comparable {
    /// Compares UIDs lexicographically by their string value
    public static func < (lhs: DICOMUniqueIdentifier, rhs: DICOMUniqueIdentifier) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMUniqueIdentifier: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uid = DICOMUniqueIdentifier.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DICOM UID format: \(string)"
            )
        }
        self = uid
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
