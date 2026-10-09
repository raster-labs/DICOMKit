/// Private Data Element
///
/// Represents a private data element with its creator reference.
/// Private data elements contain vendor-specific information.
///
/// Reference: DICOM PS3.5 Section 7.8 - Private Data Elements
///
/// NEMA-verified: 2026a, checked 2026-09-25 — carries no standard data beyond the block arithmetic of PS3.5 2026a §7.8.1; the offset range doc (0x10-0xFF) was corrected to 0x00-0xFF.
public struct PrivateDataElement: Sendable {
    /// Private tag
    public let tag: Tag
    
    /// Private creator
    public let creator: PrivateCreator
    
    /// Data element value
    public let element: DataElement
    
    /// Creates a private data element
    /// - Parameters:
    ///   - tag: Private tag
    ///   - creator: Private creator
    ///   - element: Data element
    public init(tag: Tag, creator: PrivateCreator, element: DataElement) {
        self.tag = tag
        self.creator = creator
        self.element = element
    }
    
    /// Element offset within the creator's block (0x00-0xFF)
    public var blockOffset: UInt8? {
        guard creator.owns(tag) else { return nil }
        return UInt8(tag.element & 0xFF)
    }
}

// MARK: - CustomStringConvertible
extension PrivateDataElement: CustomStringConvertible {
    public var description: String {
        if let name = PrivateTagDictionary.wellKnown.name(for: tag, creatorID: creator.creatorID) {
            return "\(tag) [\(name)] - \(creator.creatorID)"
        } else {
            return "\(tag) - \(creator.creatorID)"
        }
    }
}
