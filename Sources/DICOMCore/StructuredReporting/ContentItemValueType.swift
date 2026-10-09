/// DICOM Content Item Value Types
///
/// Defines the value types for content items in DICOM Structured Reporting.
///
/// Reference: PS3.3 Table C.17.3-7 - Value Type Definitions
///
/// NEMA-verified: 2026a, checked 2026-09-25 — all 16 Value Types of PS3.3 2026a Table C.17.3-7 are present (TABLE added 2026-09-25, P8). The citation said Table C.17.3-1; corrected.

/// Value types for DICOM Structured Reporting content items
///
/// Each content item in an SR document has one of these value types,
/// which determines what kind of data the content item contains.
public enum ContentItemValueType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// TEXT - Unstructured free text
    case text = "TEXT"
    
    /// CODE - Coded concept from a controlled terminology
    case code = "CODE"
    
    /// NUM - Numeric measurement with units
    case num = "NUM"
    
    /// DATE - Calendar date
    case date = "DATE"
    
    /// TIME - Time of day
    case time = "TIME"
    
    /// DATETIME - Combined date and time
    case datetime = "DATETIME"
    
    /// PNAME - Person name
    case pname = "PNAME"
    
    /// UIDREF - DICOM UID reference
    case uidref = "UIDREF"
    
    /// COMPOSITE - Reference to a DICOM composite object
    case composite = "COMPOSITE"
    
    /// IMAGE - Reference to a DICOM image, optionally with frames
    case image = "IMAGE"
    
    /// WAVEFORM - Reference to waveform data
    case waveform = "WAVEFORM"
    
    /// SCOORD - 2D spatial coordinates
    case scoord = "SCOORD"
    
    /// SCOORD3D - 3D spatial coordinates
    case scoord3D = "SCOORD3D"
    
    /// TCOORD - Temporal coordinates
    case tcoord = "TCOORD"
    
    /// CONTAINER - Groups other content items
    case container = "CONTAINER"

    /// TABLE - Two-dimensional tabulation of data (PS3.3 C.18.10)
    case table = "TABLE"
    
    /// Returns a human-readable display name
    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .code: return "Code"
        case .num: return "Numeric"
        case .date: return "Date"
        case .time: return "Time"
        case .datetime: return "DateTime"
        case .pname: return "Person Name"
        case .uidref: return "UID Reference"
        case .composite: return "Composite Reference"
        case .image: return "Image Reference"
        case .waveform: return "Waveform Reference"
        case .scoord: return "Spatial Coordinates (2D)"
        case .scoord3D: return "Spatial Coordinates (3D)"
        case .tcoord: return "Temporal Coordinates"
        case .container: return "Container"
        case .table: return "Table"
        }
    }
    
    /// Returns a description of what this value type contains
    public var typeDescription: String {
        switch self {
        case .text:
            return "Unstructured free text value"
        case .code:
            return "Coded value from a controlled terminology"
        case .num:
            return "Numeric measurement with optional units"
        case .date:
            return "Calendar date value"
        case .time:
            return "Time of day value"
        case .datetime:
            return "Combined date and time value"
        case .pname:
            return "Person name value"
        case .uidref:
            return "DICOM UID reference"
        case .composite:
            return "Reference to a DICOM composite SOP instance"
        case .image:
            return "Reference to a DICOM image, optionally with specific frames"
        case .waveform:
            return "Reference to waveform data"
        case .scoord:
            return "2D spatial coordinates in an image plane"
        case .scoord3D:
            return "3D spatial coordinates in a patient reference frame"
        case .tcoord:
            return "Temporal coordinates (time points or ranges)"
        case .container:
            return "Container grouping other content items"
        case .table:
            return "Two-dimensional tabulation of text, numeric, coded or date-time values"
        }
    }
    
    /// Returns whether this value type can have child content items
    public var canHaveChildren: Bool {
        // Only CONTAINER can have children via CONTAINS relationship
        // Other types can have "children" via HAS PROPERTIES etc.
        return true // All can have modifier children
    }
    
    /// Returns whether this value type is a reference type
    public var isReference: Bool {
        switch self {
        case .composite, .image, .waveform:
            return true
        default:
            return false
        }
    }
    
    /// Returns whether this value type contains coordinate data
    public var isCoordinate: Bool {
        switch self {
        case .scoord, .scoord3D, .tcoord:
            return true
        default:
            return false
        }
    }
    
    /// Returns whether this value type contains simple scalar data
    public var isSimpleValue: Bool {
        switch self {
        case .text, .code, .num, .date, .time, .datetime, .pname, .uidref:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension ContentItemValueType: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
