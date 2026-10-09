import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — all 24 command elements (tag, name, VR, VM) text-diffed against PS3.7 2026a Table E.1-1 (Scripts/diff_network.py): 24 of 24 match; the 20 retired elements of Table E.2-1 are not carried by design

/// DICOM Command Set Tags (Group 0000)
///
/// These tags are used exclusively in DIMSE Command Sets for message exchange.
///
/// Reference: PS3.7 Annex E - Command Dictionary
extension Tag {
    // MARK: - Command Group Length
    
    /// Command Group Length (0000,0000)
    /// VR: UL, VM: 1
    /// The length of the command group elements
    public static let commandGroupLength = Tag(group: 0x0000, element: 0x0000)
    
    // MARK: - SOP Class and Instance UIDs
    
    /// Affected SOP Class UID (0000,0002)
    /// VR: UI, VM: 1
    /// SOP Class UID of the affected SOP Instance
    public static let affectedSOPClassUID = Tag(group: 0x0000, element: 0x0002)
    
    /// Requested SOP Class UID (0000,0003)
    /// VR: UI, VM: 1
    /// SOP Class UID of the requested SOP Instance (used in N-* operations)
    public static let requestedSOPClassUID = Tag(group: 0x0000, element: 0x0003)
    
    /// Affected SOP Instance UID (0000,1000)
    /// VR: UI, VM: 1
    /// SOP Instance UID of the affected SOP Instance
    public static let affectedSOPInstanceUID = Tag(group: 0x0000, element: 0x1000)
    
    /// Requested SOP Instance UID (0000,1001)
    /// VR: UI, VM: 1
    /// SOP Instance UID of the requested SOP Instance (used in N-* operations)
    public static let requestedSOPInstanceUID = Tag(group: 0x0000, element: 0x1001)
    
    // MARK: - Command Field
    
    /// Command Field (0000,0100)
    /// VR: US, VM: 1
    /// Identifies the type of DIMSE command
    public static let commandField = Tag(group: 0x0000, element: 0x0100)
    
    // MARK: - Message Identification
    
    /// Message ID (0000,0110)
    /// VR: US, VM: 1
    /// Identifies the DIMSE message, unique within the association
    public static let messageID = Tag(group: 0x0000, element: 0x0110)
    
    /// Message ID Being Responded To (0000,0120)
    /// VR: US, VM: 1
    /// Message ID of the request being responded to
    public static let messageIDBeingRespondedTo = Tag(group: 0x0000, element: 0x0120)
    
    // MARK: - Move/Get Operations
    
    /// Move Destination (0000,0600)
    /// VR: AE, VM: 1
    /// AE Title of the destination for C-MOVE operation
    public static let moveDestination = Tag(group: 0x0000, element: 0x0600)
    
    /// Move Originator Application Entity Title (0000,1030)
    /// VR: AE, VM: 1
    /// AE Title of the MOVE SCU
    public static let moveOriginatorApplicationEntityTitle = Tag(group: 0x0000, element: 0x1030)
    
    /// Move Originator Message ID (0000,1031)
    /// VR: US, VM: 1
    /// Message ID of the C-MOVE operation
    public static let moveOriginatorMessageID = Tag(group: 0x0000, element: 0x1031)
    
    // MARK: - Priority
    
    /// Priority (0000,0700)
    /// VR: US, VM: 1
    /// Operation priority (LOW, MEDIUM, HIGH)
    public static let priority = Tag(group: 0x0000, element: 0x0700)
    
    // MARK: - Data Set
    
    /// Command Data Set Type (0000,0800)
    /// VR: US, VM: 1
    /// Indicates if a data set follows (0x0101 = no data set, otherwise data set present)
    public static let commandDataSetType = Tag(group: 0x0000, element: 0x0800)
    
    // MARK: - Status
    
    /// Status (0000,0900)
    /// VR: US, VM: 1
    /// Status of the DIMSE operation
    public static let status = Tag(group: 0x0000, element: 0x0900)
    
    /// Offending Element (0000,0901)
    /// VR: AT, VM: 1-n
    /// Tag(s) of elements that caused an error
    public static let offendingElement = Tag(group: 0x0000, element: 0x0901)
    
    /// Error Comment (0000,0902)
    /// VR: LO, VM: 1
    /// Textual description of the error
    public static let errorComment = Tag(group: 0x0000, element: 0x0902)
    
    /// Error ID (0000,0903)
    /// VR: US, VM: 1
    /// Implementation-specific error identifier
    public static let errorID = Tag(group: 0x0000, element: 0x0903)
    
    // MARK: - Sub-operation Counts (for C-MOVE, C-GET)
    
    /// Number of Remaining Sub-operations (0000,1020)
    /// VR: US, VM: 1
    /// Number of remaining sub-operations
    public static let numberOfRemainingSuboperations = Tag(group: 0x0000, element: 0x1020)
    
    /// Number of Completed Sub-operations (0000,1021)
    /// VR: US, VM: 1
    /// Number of completed sub-operations
    public static let numberOfCompletedSuboperations = Tag(group: 0x0000, element: 0x1021)
    
    /// Number of Failed Sub-operations (0000,1022)
    /// VR: US, VM: 1
    /// Number of failed sub-operations
    public static let numberOfFailedSuboperations = Tag(group: 0x0000, element: 0x1022)
    
    /// Number of Warning Sub-operations (0000,1023)
    /// VR: US, VM: 1
    /// Number of sub-operations with warning status
    public static let numberOfWarningSuboperations = Tag(group: 0x0000, element: 0x1023)
    
    // MARK: - N-EVENT/N-ACTION
    
    /// Event Type ID (0000,1002)
    /// VR: US, VM: 1
    /// Type of event (for N-EVENT-REPORT)
    public static let eventTypeID = Tag(group: 0x0000, element: 0x1002)
    
    /// Action Type ID (0000,1008)
    /// VR: US, VM: 1
    /// Type of action (for N-ACTION)
    public static let actionTypeID = Tag(group: 0x0000, element: 0x1008)
    
    /// Attribute Identifier List (0000,1005)
    /// VR: AT, VM: 1-n
    /// List of attribute tags (for N-GET, N-SET)
    public static let attributeIdentifierList = Tag(group: 0x0000, element: 0x1005)
}
