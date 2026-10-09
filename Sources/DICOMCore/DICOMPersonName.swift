import Foundation

/// DICOM Person Name (PN) value representation
///
/// Represents a person name in DICOM format with support for name components and
/// multiple character set representations.
///
/// Reference: DICOM PS3.5 Section 6.2 - PN Value Representation
///
/// The PN format consists of up to 5 components separated by caret (^):
/// - Family name (surname)
/// - Given name (first name)
/// - Middle name
/// - Name prefix (e.g., "Dr.", "Mr.")
/// - Name suffix (e.g., "Jr.", "III")
///
/// Format: `family^given^middle^prefix^suffix`
///
/// Multiple representations (alphabetic, ideographic, phonetic) are separated by equals (=):
/// `alphabetic=ideographic=phonetic`
///
/// Reference: DICOM PS3.5 Section 6.2.1 - Person Name Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the PN row of PS3.5 2026a Table 6.2-1 (five "^" components, up to three "=" component groups, trailing null components omitted). Not enforced: the 64-character limit per component group and the ban on 5CH; extra "^" components beyond five are dropped on read.
///
/// Examples:
/// - "Doe^John" = family name "Doe", given name "John"
/// - "Doe^John^Robert^Dr.^Jr." = full name with all components
/// - "Yamada^Tarou==やまだ^たろう" = with phonetic representation (empty ideographic)
public struct DICOMPersonName: Sendable, Hashable {
    /// Name component group representing one character set representation
    ///
    /// Each component group contains the 5 name components in a specific
    /// character repertoire (alphabetic, ideographic, or phonetic).
    ///
    /// Reference: DICOM PS3.5 Section 6.2.1.1
    public struct ComponentGroup: Sendable, Hashable {
        /// Family name (surname)
        public let familyName: String
        
        /// Given name (first name)
        public let givenName: String
        
        /// Middle name
        public let middleName: String
        
        /// Name prefix (e.g., "Dr.", "Mr.")
        public let namePrefix: String
        
        /// Name suffix (e.g., "Jr.", "III")
        public let nameSuffix: String
        
        /// Creates a component group from individual components
        /// - Parameters:
        ///   - familyName: Family name (surname)
        ///   - givenName: Given name (first name)
        ///   - middleName: Middle name
        ///   - namePrefix: Name prefix (e.g., "Dr.")
        ///   - nameSuffix: Name suffix (e.g., "Jr.")
        public init(
            familyName: String = "",
            givenName: String = "",
            middleName: String = "",
            namePrefix: String = "",
            nameSuffix: String = ""
        ) {
            self.familyName = familyName
            self.givenName = givenName
            self.middleName = middleName
            self.namePrefix = namePrefix
            self.nameSuffix = nameSuffix
        }
        
        /// Indicates whether this component group is empty (all components are empty)
        public var isEmpty: Bool {
            return familyName.isEmpty &&
                   givenName.isEmpty &&
                   middleName.isEmpty &&
                   namePrefix.isEmpty &&
                   nameSuffix.isEmpty
        }
        
        /// Returns the DICOM formatted string for this component group
        ///
        /// Trailing empty components and their delimiters are omitted.
        public var dicomString: String {
            let components = [familyName, givenName, middleName, namePrefix, nameSuffix]
            
            // Find the last non-empty component
            var lastNonEmptyIndex = -1
            for (index, component) in components.enumerated() {
                if !component.isEmpty {
                    lastNonEmptyIndex = index
                }
            }
            
            // If all empty, return empty string
            guard lastNonEmptyIndex >= 0 else {
                return ""
            }
            
            // Join components up to and including the last non-empty one
            return components[0...lastNonEmptyIndex].joined(separator: "^")
        }
        
        /// Returns a human-readable formatted name
        ///
        /// Format: "prefix given middle family suffix" (e.g., "Dr. John Robert Doe Jr.")
        /// Empty components are omitted.
        public var formattedName: String {
            var parts: [String] = []
            
            if !namePrefix.isEmpty { parts.append(namePrefix) }
            if !givenName.isEmpty { parts.append(givenName) }
            if !middleName.isEmpty { parts.append(middleName) }
            if !familyName.isEmpty { parts.append(familyName) }
            if !nameSuffix.isEmpty { parts.append(nameSuffix) }
            
            return parts.joined(separator: " ")
        }
        
        /// Parses a component group string into a ComponentGroup
        ///
        /// Trims leading/trailing whitespace from each component per DICOM conventions.
        ///
        /// - Parameter string: String with components separated by caret (^)
        /// - Returns: A ComponentGroup with parsed components
        public static func parse(_ string: String) -> ComponentGroup {
            let components = string.split(separator: "^", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            
            return ComponentGroup(
                familyName: components.count > 0 ? components[0] : "",
                givenName: components.count > 1 ? components[1] : "",
                middleName: components.count > 2 ? components[2] : "",
                namePrefix: components.count > 3 ? components[3] : "",
                nameSuffix: components.count > 4 ? components[4] : ""
            )
        }
    }
    
    /// Alphabetic representation of the name (required)
    ///
    /// Written in single-byte characters using ISO 646 repertoire
    /// or extended character sets.
    /// Reference: DICOM PS3.5 Section 6.2.1.1
    public let alphabetic: ComponentGroup
    
    /// Ideographic representation of the name (optional)
    ///
    /// Written in ideographic characters (e.g., Japanese Kanji).
    /// Reference: DICOM PS3.5 Section 6.2.1.1
    public let ideographic: ComponentGroup
    
    /// Phonetic representation of the name (optional)
    ///
    /// Written in phonetic characters (e.g., Japanese Hiragana/Katakana).
    /// Reference: DICOM PS3.5 Section 6.2.1.1
    public let phonetic: ComponentGroup
    
    /// Creates a DICOM person name from component groups
    /// - Parameters:
    ///   - alphabetic: Alphabetic representation (required)
    ///   - ideographic: Ideographic representation (optional)
    ///   - phonetic: Phonetic representation (optional)
    public init(
        alphabetic: ComponentGroup,
        ideographic: ComponentGroup = ComponentGroup(),
        phonetic: ComponentGroup = ComponentGroup()
    ) {
        self.alphabetic = alphabetic
        self.ideographic = ideographic
        self.phonetic = phonetic
    }
    
    /// Convenience initializer for simple names with only alphabetic components
    /// - Parameters:
    ///   - familyName: Family name (surname)
    ///   - givenName: Given name (first name)
    ///   - middleName: Middle name
    ///   - namePrefix: Name prefix (e.g., "Dr.")
    ///   - nameSuffix: Name suffix (e.g., "Jr.")
    public init(
        familyName: String = "",
        givenName: String = "",
        middleName: String = "",
        namePrefix: String = "",
        nameSuffix: String = ""
    ) {
        self.alphabetic = ComponentGroup(
            familyName: familyName,
            givenName: givenName,
            middleName: middleName,
            namePrefix: namePrefix,
            nameSuffix: nameSuffix
        )
        self.ideographic = ComponentGroup()
        self.phonetic = ComponentGroup()
    }
    
    /// Parses a DICOM PN string into a DICOMPersonName
    ///
    /// Accepts the standard DICOM person name format:
    /// `alphabetic=ideographic=phonetic`
    ///
    /// Where each representation has format:
    /// `family^given^middle^prefix^suffix`
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - PN Value Representation
    ///
    /// - Parameter string: The PN string to parse
    /// - Returns: A DICOMPersonName if parsing succeeds, nil if the string is empty
    public static func parse(_ string: String) -> DICOMPersonName? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Empty string is invalid per DICOM standard
        guard !trimmed.isEmpty else {
            return nil
        }
        
        // Split by '=' to get component groups
        let groups = trimmed.split(separator: "=", omittingEmptySubsequences: false)
            .map { String($0) }
        
        let alphabetic = groups.count > 0 ? ComponentGroup.parse(groups[0]) : ComponentGroup()
        let ideographic = groups.count > 1 ? ComponentGroup.parse(groups[1]) : ComponentGroup()
        let phonetic = groups.count > 2 ? ComponentGroup.parse(groups[2]) : ComponentGroup()
        
        return DICOMPersonName(
            alphabetic: alphabetic,
            ideographic: ideographic,
            phonetic: phonetic
        )
    }
    
    // MARK: - Convenience Accessors
    
    /// Family name from the alphabetic representation
    public var familyName: String {
        return alphabetic.familyName
    }
    
    /// Given name from the alphabetic representation
    public var givenName: String {
        return alphabetic.givenName
    }
    
    /// Middle name from the alphabetic representation
    public var middleName: String {
        return alphabetic.middleName
    }
    
    /// Name prefix from the alphabetic representation
    public var namePrefix: String {
        return alphabetic.namePrefix
    }
    
    /// Name suffix from the alphabetic representation
    public var nameSuffix: String {
        return alphabetic.nameSuffix
    }
    
    /// Indicates whether this person name has ideographic representation
    public var hasIdeographic: Bool {
        return !ideographic.isEmpty
    }
    
    /// Indicates whether this person name has phonetic representation
    public var hasPhonetic: Bool {
        return !phonetic.isEmpty
    }
    
    /// Returns a human-readable formatted name using the alphabetic representation
    ///
    /// Format: "prefix given middle family suffix" (e.g., "Dr. John Robert Doe Jr.")
    public var formattedName: String {
        return alphabetic.formattedName
    }
    
    /// Returns the DICOM PN format string
    ///
    /// Trailing empty component groups and their delimiters are omitted.
    public var dicomString: String {
        let alphabeticStr = alphabetic.dicomString
        let ideographicStr = ideographic.dicomString
        let phoneticStr = phonetic.dicomString
        
        // Build the string, omitting trailing empty groups
        if !phoneticStr.isEmpty {
            return "\(alphabeticStr)=\(ideographicStr)=\(phoneticStr)"
        } else if !ideographicStr.isEmpty {
            return "\(alphabeticStr)=\(ideographicStr)"
        } else {
            return alphabeticStr
        }
    }
}

extension DICOMPersonName: CustomStringConvertible {
    public var description: String {
        return formattedName.isEmpty ? dicomString : formattedName
    }
}

extension DICOMPersonName: Comparable {
    /// Compares person names alphabetically by family name, then given name
    public static func < (lhs: DICOMPersonName, rhs: DICOMPersonName) -> Bool {
        if lhs.familyName != rhs.familyName {
            return lhs.familyName.localizedCaseInsensitiveCompare(rhs.familyName) == .orderedAscending
        }
        return lhs.givenName.localizedCaseInsensitiveCompare(rhs.givenName) == .orderedAscending
    }
}
