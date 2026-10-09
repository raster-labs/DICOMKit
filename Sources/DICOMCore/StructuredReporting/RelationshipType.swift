/// DICOM Structured Reporting Relationship Types
///
/// Defines the relationship types used in DICOM Structured Reporting to connect
/// content items in a hierarchical tree structure.
///
/// Reference: PS3.3 Table C.17.3-8 - Relationship Type Definitions
///
/// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed: all 7 values match PS3.3 2026a Table
/// C.17.3-8 exactly.

/// Relationship types between content items in DICOM Structured Reporting
///
/// Each relationship type defines how a child content item relates to its parent.
/// The relationship type constrains which value types can be children of a parent.
public enum RelationshipType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// CONTAINS - The child content item is part of the parent
    /// Used for: Document root contains content, CONTAINER contains children
    /// Parent: CONTAINER, ROOT
    case contains = "CONTAINS"
    
    /// HAS PROPERTIES - The child describes properties of the parent
    /// Used for: Adding descriptive attributes to a finding or measurement
    /// Parent: Any except CONTAINER with CONTINUOUS continuity
    case hasProperties = "HAS PROPERTIES"
    
    /// HAS OBS CONTEXT - The child describes observation context
    /// Used for: Observer identification, observation date/time
    /// Parent: Any
    case hasObsContext = "HAS OBS CONTEXT"
    
    /// HAS ACQ CONTEXT - The child describes acquisition context
    /// Used for: Acquisition protocol, device settings
    /// Parent: Any
    case hasAcqContext = "HAS ACQ CONTEXT"
    
    /// HAS CONCEPT MOD - The child modifies the meaning of the parent concept
    /// Used for: Laterality, anatomic location modifier
    /// Parent: CODE, NUM, COMPOSITE, IMAGE, WAVEFORM, SCOORD, SCOORD3D, TCOORD
    case hasConceptMod = "HAS CONCEPT MOD"
    
    /// INFERRED FROM - The parent is inferred from the child
    /// Used for: Measurement derived from image region, finding based on observations
    /// Parent: CODE, NUM
    case inferredFrom = "INFERRED FROM"
    
    /// SELECTED FROM - The parent is selected from the child
    /// Used for: Region of interest selected from an image
    /// Parent: SCOORD, SCOORD3D, TCOORD
    case selectedFrom = "SELECTED FROM"
    
    /// The display name of the relationship type
    public var displayName: String {
        switch self {
        case .contains: return "Contains"
        case .hasProperties: return "Has Properties"
        case .hasObsContext: return "Has Observation Context"
        case .hasAcqContext: return "Has Acquisition Context"
        case .hasConceptMod: return "Has Concept Modifier"
        case .inferredFrom: return "Inferred From"
        case .selectedFrom: return "Selected From"
        }
    }
    
    /// Description of what this relationship type means
    public var meaning: String {
        switch self {
        case .contains:
            return "The child content item is part of the parent"
        case .hasProperties:
            return "The child describes properties of the parent"
        case .hasObsContext:
            return "The child describes observation context"
        case .hasAcqContext:
            return "The child describes acquisition context"
        case .hasConceptMod:
            return "The child modifies the meaning of the parent concept"
        case .inferredFrom:
            return "The parent is inferred from the child"
        case .selectedFrom:
            return "The parent is selected from the child"
        }
    }
}

// MARK: - Relationship Validation

extension RelationshipType {
    /// Checks if this relationship type is valid for a given parent value type
    /// - Parameter parentValueType: The value type of the parent content item
    /// - Returns: True if this relationship can have the given parent type
    public func isValidForParent(_ parentValueType: ContentItemValueType) -> Bool {
        switch self {
        case .contains:
            // CONTAINS can only have CONTAINER parent (or root)
            return parentValueType == .container
            
        case .hasProperties:
            // HAS PROPERTIES cannot have CONTAINER with CONTINUOUS parent
            // For simplicity, we allow all non-CONTAINER parents
            return parentValueType != .container
            
        case .hasObsContext, .hasAcqContext:
            // These can have any parent
            return true
            
        case .hasConceptMod:
            // HAS CONCEPT MOD is valid for specific types
            switch parentValueType {
            case .code, .num, .composite, .image, .waveform, .scoord, .scoord3D, .tcoord:
                return true
            default:
                return false
            }
            
        case .inferredFrom:
            // INFERRED FROM is valid for CODE and NUM
            return parentValueType == .code || parentValueType == .num
            
        case .selectedFrom:
            // SELECTED FROM is valid for SCOORD, SCOORD3D, TCOORD
            return parentValueType == .scoord || parentValueType == .scoord3D || parentValueType == .tcoord
        }
    }
    
    /// Returns the valid child value types for this relationship
    public var validChildValueTypes: [ContentItemValueType] {
        switch self {
        case .contains:
            // All value types can be children of CONTAINS
            return ContentItemValueType.allCases
            
        case .hasProperties:
            // All value types except CONTAINER can be properties
            return ContentItemValueType.allCases.filter { $0 != .container }
            
        case .hasObsContext:
            // Observation context is typically TEXT, CODE, PNAME, DATETIME
            return [.text, .code, .pname, .datetime, .date, .time, .uidref]
            
        case .hasAcqContext:
            // Acquisition context can be various types
            return [.text, .code, .num, .datetime, .date, .time]
            
        case .hasConceptMod:
            // Concept modifiers are typically CODE or TEXT
            return [.code, .text]
            
        case .inferredFrom:
            // INFERRED FROM children are typically references or coordinates
            return [.image, .composite, .waveform, .scoord, .scoord3D, .tcoord, .num]
            
        case .selectedFrom:
            // SELECTED FROM children are images or waveforms
            return [.image, .waveform]
        }
    }
}

// MARK: - CustomStringConvertible

extension RelationshipType: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
