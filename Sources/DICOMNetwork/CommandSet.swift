import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — command set encoding checked against PS3.7 2026a §6.3.1 (Implicit VR LE, group length first, even lengths) and Table E.1-1 (0000,0800) = 0101H; pad byte per VR from PS3.5 Table 6.2-1 (UI NULL, AE/LO SPACE)

/// Value indicating that no data set follows the command
///
/// When Command Data Set Type (0000,0800) equals this value, no data set follows.
/// Reference: PS3.7 Section 9.3.1
public let noDataSetPresent: UInt16 = 0x0101

/// DIMSE Command Set
///
/// Represents a DICOM Message Service Element (DIMSE) command.
/// Command Sets are always encoded using Implicit VR Little Endian.
///
/// Reference: PS3.7 Section 9.2 - DIMSE Service Message Structure
public struct CommandSet: Sendable, Hashable {
    
    /// The elements in the command set
    private var elements: [Tag: Data]
    
    /// Creates an empty command set
    public init() {
        self.elements = [:]
    }
    
    /// Creates a command set from raw elements
    public init(elements: [Tag: Data]) {
        self.elements = elements
    }
    
    // MARK: - Element Access
    
    /// Gets a UInt16 value for a tag
    ///
    /// - Parameter tag: The command tag
    /// - Returns: The UInt16 value, or nil if not present
    public func getUInt16(_ tag: Tag) -> UInt16? {
        guard let data = elements[tag], data.count >= 2 else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    /// Gets a UInt32 value for a tag
    ///
    /// - Parameter tag: The command tag
    /// - Returns: The UInt32 value, or nil if not present
    public func getUInt32(_ tag: Tag) -> UInt32? {
        guard let data = elements[tag], data.count >= 4 else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    /// Gets a string value for a tag
    ///
    /// - Parameter tag: The command tag
    /// - Returns: The string value (trimmed), or nil if not present
    public func getString(_ tag: Tag) -> String? {
        guard let data = elements[tag] else { return nil }
        let string = String(data: data, encoding: .ascii) ?? ""
        return string.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }
    
    /// Gets the raw data for a tag
    ///
    /// - Parameter tag: The command tag
    /// - Returns: The raw data, or nil if not present
    public func getData(_ tag: Tag) -> Data? {
        elements[tag]
    }
    
    /// Sets a UInt16 value for a tag
    ///
    /// - Parameters:
    ///   - value: The UInt16 value
    ///   - tag: The command tag
    public mutating func setUInt16(_ value: UInt16, for tag: Tag) {
        var data = Data(count: 2)
        data.withUnsafeMutableBytes { $0.storeBytes(of: value, as: UInt16.self) }
        elements[tag] = data
    }
    
    /// Sets a UInt32 value for a tag
    ///
    /// - Parameters:
    ///   - value: The UInt32 value
    ///   - tag: The command tag
    public mutating func setUInt32(_ value: UInt32, for tag: Tag) {
        var data = Data(count: 4)
        data.withUnsafeMutableBytes { $0.storeBytes(of: value, as: UInt32.self) }
        elements[tag] = data
    }
    
    /// Sets a string value for a tag, padded to even length
    ///
    /// The pad byte follows the element's VR (PS3.5 Table 6.2-1, 2026a): UI
    /// values get a trailing NULL (00H); AE and LO values get a trailing SPACE
    /// (20H). The VR is taken from PS3.7 Table E.1-1 by tag: Move Destination
    /// (0000,0600) and Move Originator Application Entity Title (0000,1030)
    /// are AE, Error Comment (0000,0902) is LO; every other string command
    /// element is UI.
    ///
    /// - Parameters:
    ///   - value: The string value
    ///   - tag: The command tag
    public mutating func setString(_ value: String, for tag: Tag) {
        var data = value.data(using: .ascii) ?? Data()
        if data.count % 2 != 0 {
            data.append(Self.spacePaddedCommandTags.contains(tag) ? 0x20 : 0x00)
        }
        elements[tag] = data
    }

    /// Command elements of VR AE or LO (PS3.7 Table E.1-1), which are
    /// space-padded (PS3.5 Table 6.2-1); the remaining string command
    /// elements are UI and NULL-padded.
    private static let spacePaddedCommandTags: Set<Tag> = [
        .moveDestination,                        // (0000,0600) AE
        .moveOriginatorApplicationEntityTitle,   // (0000,1030) AE
        .errorComment                            // (0000,0902) LO
    ]
    
    /// Removes a value for a tag
    ///
    /// - Parameter tag: The command tag
    public mutating func remove(_ tag: Tag) {
        elements.removeValue(forKey: tag)
    }
    
    // MARK: - Common Accessors
    
    /// The DIMSE command type
    public var command: DIMSECommand? {
        guard let value = getUInt16(.commandField) else { return nil }
        return DIMSECommand(rawValue: value)
    }
    
    /// Sets the DIMSE command type
    public mutating func setCommand(_ command: DIMSECommand) {
        setUInt16(command.rawValue, for: .commandField)
    }
    
    /// The message ID
    public var messageID: UInt16? {
        getUInt16(.messageID)
    }
    
    /// Sets the message ID
    public mutating func setMessageID(_ id: UInt16) {
        setUInt16(id, for: .messageID)
    }
    
    /// The message ID being responded to
    public var messageIDBeingRespondedTo: UInt16? {
        getUInt16(.messageIDBeingRespondedTo)
    }
    
    /// Sets the message ID being responded to
    public mutating func setMessageIDBeingRespondedTo(_ id: UInt16) {
        setUInt16(id, for: .messageIDBeingRespondedTo)
    }
    
    /// The affected SOP Class UID
    public var affectedSOPClassUID: String? {
        getString(.affectedSOPClassUID)
    }
    
    /// Sets the affected SOP Class UID
    public mutating func setAffectedSOPClassUID(_ uid: String) {
        setString(uid, for: .affectedSOPClassUID)
    }
    
    /// The affected SOP Instance UID
    public var affectedSOPInstanceUID: String? {
        getString(.affectedSOPInstanceUID)
    }
    
    /// Sets the affected SOP Instance UID
    public mutating func setAffectedSOPInstanceUID(_ uid: String) {
        setString(uid, for: .affectedSOPInstanceUID)
    }
    
    /// The status code
    public var status: DIMSEStatus? {
        guard let value = getUInt16(.status) else { return nil }
        return DIMSEStatus.from(value)
    }
    
    /// Sets the status code
    public mutating func setStatus(_ status: DIMSEStatus) {
        setUInt16(status.rawValue, for: .status)
    }
    
    /// The priority
    public var priority: DIMSEPriority? {
        guard let value = getUInt16(.priority) else { return nil }
        return DIMSEPriority(rawValue: value)
    }
    
    /// Sets the priority
    public mutating func setPriority(_ priority: DIMSEPriority) {
        setUInt16(priority.rawValue, for: .priority)
    }
    
    /// Whether a data set follows this command
    public var hasDataSet: Bool {
        guard let value = getUInt16(.commandDataSetType) else { return false }
        return value != noDataSetPresent
    }
    
    /// Sets whether a data set follows
    public mutating func setHasDataSet(_ hasDataSet: Bool) {
        setUInt16(hasDataSet ? 0x0000 : noDataSetPresent, for: .commandDataSetType)
    }
    
    /// The move destination AE title
    public var moveDestination: String? {
        getString(.moveDestination)
    }

    /// Sets the move destination AE title
    public mutating func setMoveDestination(_ destination: String) {
        setString(destination, for: .moveDestination)
    }

    // MARK: - Error Detail (PS3.7 Annex C)

    /// Error Comment (0000,0902) — textual description of the error, when the
    /// peer included one in a failure response.
    public var errorComment: String? {
        getString(.errorComment)
    }

    /// Sets the Error Comment
    public mutating func setErrorComment(_ comment: String) {
        setString(comment, for: .errorComment)
    }

    /// Error ID (0000,0903) — implementation-specific error identifier.
    public var errorID: UInt16? {
        getUInt16(.errorID)
    }

    /// Sets the Error ID
    public mutating func setErrorID(_ id: UInt16) {
        setUInt16(id, for: .errorID)
    }

    /// Offending Element (0000,0901) — tags of the elements that caused the
    /// error (VR AT, VM 1-n): pairs of little-endian group/element numbers.
    public var offendingElements: [Tag]? {
        guard let data = getData(.offendingElement), data.count >= 4 else { return nil }
        var tags: [Tag] = []
        var offset = data.startIndex
        while offset + 4 <= data.endIndex {
            let group = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let element = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            tags.append(Tag(group: group, element: element))
            offset += 4
        }
        return tags.isEmpty ? nil : tags
    }
    
    // MARK: - Sub-operation Counts
    
    /// Number of remaining sub-operations
    public var numberOfRemainingSuboperations: UInt16? {
        getUInt16(.numberOfRemainingSuboperations)
    }
    
    /// Sets the number of remaining sub-operations
    public mutating func setNumberOfRemainingSuboperations(_ count: UInt16) {
        setUInt16(count, for: .numberOfRemainingSuboperations)
    }
    
    /// Number of completed sub-operations
    public var numberOfCompletedSuboperations: UInt16? {
        getUInt16(.numberOfCompletedSuboperations)
    }
    
    /// Sets the number of completed sub-operations
    public mutating func setNumberOfCompletedSuboperations(_ count: UInt16) {
        setUInt16(count, for: .numberOfCompletedSuboperations)
    }
    
    /// Number of failed sub-operations
    public var numberOfFailedSuboperations: UInt16? {
        getUInt16(.numberOfFailedSuboperations)
    }
    
    /// Sets the number of failed sub-operations
    public mutating func setNumberOfFailedSuboperations(_ count: UInt16) {
        setUInt16(count, for: .numberOfFailedSuboperations)
    }
    
    /// Number of warning sub-operations
    public var numberOfWarningSuboperations: UInt16? {
        getUInt16(.numberOfWarningSuboperations)
    }
    
    /// Sets the number of warning sub-operations
    public mutating func setNumberOfWarningSuboperations(_ count: UInt16) {
        setUInt16(count, for: .numberOfWarningSuboperations)
    }
    
    // MARK: - N-ACTION/N-EVENT-REPORT Fields
    
    /// The requested SOP Class UID (used in N-* operations)
    public var requestedSOPClassUID: String? {
        getString(.requestedSOPClassUID)
    }
    
    /// Sets the requested SOP Class UID
    public mutating func setRequestedSOPClassUID(_ uid: String) {
        setString(uid, for: .requestedSOPClassUID)
    }
    
    /// The requested SOP Instance UID (used in N-* operations)
    public var requestedSOPInstanceUID: String? {
        getString(.requestedSOPInstanceUID)
    }
    
    /// Sets the requested SOP Instance UID
    public mutating func setRequestedSOPInstanceUID(_ uid: String) {
        setString(uid, for: .requestedSOPInstanceUID)
    }
    
    /// The action type ID (for N-ACTION)
    public var actionTypeID: UInt16? {
        getUInt16(.actionTypeID)
    }
    
    /// Sets the action type ID
    public mutating func setActionTypeID(_ id: UInt16) {
        setUInt16(id, for: .actionTypeID)
    }
    
    /// The event type ID (for N-EVENT-REPORT)
    public var eventTypeID: UInt16? {
        getUInt16(.eventTypeID)
    }
    
    /// Sets the event type ID
    public mutating func setEventTypeID(_ id: UInt16) {
        setUInt16(id, for: .eventTypeID)
    }
    
    // MARK: - Encoding
    
    /// Encodes the command set to binary data
    ///
    /// Command sets are always encoded using Implicit VR Little Endian.
    /// The Command Group Length (0000,0000) is calculated and included.
    ///
    /// - Returns: The encoded command set data
    public func encode() -> Data {
        var body = Data()
        
        // Encode all elements except group length (sorted by tag)
        let sortedElements = elements
            .filter { $0.key != .commandGroupLength }
            .sorted { $0.key < $1.key }
        
        for (tag, value) in sortedElements {
            body.append(encodeElement(tag: tag, value: value))
        }
        
        // Calculate and prepend group length
        var result = Data()
        let groupLength = UInt32(body.count)
        var lengthData = Data(count: 4)
        lengthData.withUnsafeMutableBytes { $0.storeBytes(of: groupLength, as: UInt32.self) }
        result.append(encodeElement(tag: .commandGroupLength, value: lengthData))
        result.append(body)
        
        return result
    }
    
    /// Encodes a single element in Implicit VR Little Endian format
    private func encodeElement(tag: Tag, value: Data) -> Data {
        var encoded = Data()
        
        // Tag (4 bytes, little endian)
        var group = tag.group
        var element = tag.element
        encoded.append(Data(bytes: &group, count: 2))
        encoded.append(Data(bytes: &element, count: 2))
        
        // Value Length (4 bytes, little endian)
        var length = UInt32(value.count)
        encoded.append(Data(bytes: &length, count: 4))
        
        // Value
        encoded.append(value)
        
        return encoded
    }
    
    /// Decodes a command set from binary data
    ///
    /// - Parameter data: The binary data (Implicit VR Little Endian)
    /// - Returns: The decoded command set
    /// - Throws: `DICOMNetworkError.decodingFailed` if decoding fails
    public static func decode(from data: Data) throws -> CommandSet {
        var elements: [Tag: Data] = [:]
        var offset = 0
        
        while offset + 8 <= data.count {
            // Read tag (4 bytes) - safe unaligned read
            let group = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let element = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            let tag = Tag(group: group, element: element)
            offset += 4
            
            // Read value length (4 bytes) - safe unaligned read
            let valueLength = UInt32(data[offset]) |
                              (UInt32(data[offset + 1]) << 8) |
                              (UInt32(data[offset + 2]) << 16) |
                              (UInt32(data[offset + 3]) << 24)
            offset += 4
            
            // Read value
            guard offset + Int(valueLength) <= data.count else {
                throw DICOMNetworkError.decodingFailed("Command set value exceeds data bounds")
            }
            let value = data.subdata(in: offset..<(offset + Int(valueLength)))
            offset += Int(valueLength)
            
            elements[tag] = value
        }
        
        return CommandSet(elements: elements)
    }
}

// MARK: - CustomStringConvertible
extension CommandSet: CustomStringConvertible {
    public var description: String {
        var lines: [String] = ["CommandSet:"]
        
        if let cmd = command {
            lines.append("  Command: \(cmd)")
        }
        if let msgID = messageID {
            lines.append("  Message ID: \(msgID)")
        }
        if let respID = messageIDBeingRespondedTo {
            lines.append("  Responding To: \(respID)")
        }
        if let sopClass = affectedSOPClassUID {
            lines.append("  Affected SOP Class: \(sopClass)")
        }
        if let sopInstance = affectedSOPInstanceUID {
            lines.append("  Affected SOP Instance: \(sopInstance)")
        }
        if let st = status {
            lines.append("  Status: \(st)")
        }
        if let pri = priority {
            lines.append("  Priority: \(pri)")
        }
        lines.append("  Has Data Set: \(hasDataSet)")
        
        return lines.joined(separator: "\n")
    }
}
