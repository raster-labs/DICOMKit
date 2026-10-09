/// Private Tag Allocator
///
/// Allocates private creator blocks and generates private tags.
/// Manages conflict-free private group selection and serialization.
///
/// Reference: DICOM PS3.5 Section 7.8 - Private Data Elements
///
/// NEMA-verified: 2026a, checked 2026-09-25 — allocation follows PS3.5 2026a §7.8.1: odd groups only, creator elements 0x0010-0x00FF, one block per creator identifier per group, blocks need not be sequential.
public actor PrivateTagAllocator {
    /// Allocated private creators by group
    private var allocations: [UInt16: [UInt16: PrivateCreator]] = [:]
    
    /// Creates a new private tag allocator
    public init() {}
    
    /// Reserves a private creator block in a group
    /// - Parameters:
    ///   - creatorID: Private creator identification string
    ///   - group: Odd group number for private tags
    /// - Returns: Private creator with allocated block, or nil if no blocks available
    /// - Throws: If group is not valid for private tags (must be odd)
    public func allocateBlock(creatorID: String, in group: UInt16) throws -> PrivateCreator? {
        // Verify group is odd (private)
        guard (group & 0x0001) != 0 else {
            throw PrivateTagError.invalidGroup(group)
        }
        
        // Check if this creator is already allocated in this group
        if let existing = allocations[group]?.values.first(where: { $0.creatorID == creatorID }) {
            return existing
        }
        
        // Find first available block (0x0010-0x00FF)
        let allocatedElements: Set<UInt16> = if let groupAllocs = allocations[group] {
            Set(groupAllocs.keys)
        } else {
            []
        }
        
        for element in UInt16(0x0010)...UInt16(0x00FF) {
            if !allocatedElements.contains(element) {
                let creator = PrivateCreator(creatorID: creatorID, group: group, element: element)
                
                if allocations[group] == nil {
                    allocations[group] = [:]
                }
                allocations[group]![element] = creator
                
                return creator
            }
        }
        
        // No available blocks
        return nil
    }
    
    /// Gets or allocates a private creator block
    /// - Parameters:
    ///   - creatorID: Private creator identification string
    ///   - group: Odd group number for private tags
    /// - Returns: Private creator with block
    /// - Throws: If group is invalid or no blocks available
    public func getOrAllocateBlock(creatorID: String, in group: UInt16) throws -> PrivateCreator {
        if let existing = allocations[group]?.values.first(where: { $0.creatorID == creatorID }) {
            return existing
        }
        
        guard let allocated = try allocateBlock(creatorID: creatorID, in: group) else {
            throw PrivateTagError.noBlocksAvailable(group: group)
        }
        
        return allocated
    }
    
    /// Creates a private tag in an allocated block
    /// - Parameters:
    ///   - creator: Private creator
    ///   - offset: Element offset within block (0x00-0xFF)
    /// - Returns: Private tag
    public func createTag(creator: PrivateCreator, offset: UInt8) async throws -> Tag {
        guard let tag = creator.privateTag(offset: offset) else {
            throw PrivateTagError.invalidOffset(offset)
        }
        return tag
    }
    
    /// Finds the private creator for a private tag
    /// - Parameter tag: Private tag to look up
    /// - Returns: Private creator if known
    public func creator(for tag: Tag) -> PrivateCreator? {
        guard tag.isPrivate else { return nil }
        
        // Block number is the upper byte of the element
        let blockNumber = UInt8(tag.element >> 8)
        guard blockNumber >= 0x10 else { return nil }
        
        // Creator element is the block number
        let creatorElement = UInt16(blockNumber)
        
        return allocations[tag.group]?[creatorElement]
    }
    
    /// Resets all allocations
    public func reset() {
        allocations.removeAll()
    }
    
    /// Gets all allocated creators in a group
    /// - Parameter group: Group number
    /// - Returns: Array of allocated private creators
    public func creators(in group: UInt16) -> [PrivateCreator] {
        if let groupAllocations = allocations[group] {
            return Array(groupAllocations.values)
        }
        return []
    }
}

/// Private Tag Errors
public enum PrivateTagError: Error, Sendable {
    /// Group number is not odd (not valid for private tags)
    case invalidGroup(UInt16)
    
    /// No blocks available in group
    case noBlocksAvailable(group: UInt16)
    
    /// Invalid element offset
    case invalidOffset(UInt8)
}

extension PrivateTagError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidGroup(let group):
            return "Group \(String(format: "0x%04X", group)) is not odd (not valid for private tags)"
        case .noBlocksAvailable(let group):
            return "No private creator blocks available in group \(String(format: "0x%04X", group))"
        case .invalidOffset(let offset):
            return "Invalid private tag offset \(String(format: "0x%02X", offset))"
        }
    }
}
