/// Private Creator Identification
///
/// Identifies the creator of private data elements according to PS3.5 Section 7.8.
/// Private creators reserve a block of element numbers for their private tags.
///
/// Reference: DICOM PS3.5 Section 7.8 - Private Data Elements
/// Reference: DICOM PS3.5 Section 7.8.1 - Private Data Element Tags
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the block rules (creator elements (gggg,0010-00FF) in an odd group; data elements (gggg,bb00-bbFF) where bb is the creator element's low byte) match PS3.5 2026a §7.8.1. The citation "§6.1.4 Private Creator Data Element" named a section that does not exist; corrected. The vendor creator strings are outside NEMA's scope (they match the DCMTK/GDCM private dictionaries).
public struct PrivateCreator: Sendable, Hashable, Equatable {
    /// Creator identification string
    ///
    /// This string identifies the organization or implementation that created
    /// the private elements. It is stored in the private creator element at
    /// (gggg,0010-00FF) where gggg is an odd group number.
    public let creatorID: String
    
    /// Group number (must be odd for private tags)
    public let group: UInt16
    
    /// Private creator element number (0x0010 - 0x00FF)
    ///
    /// The block number (see ``blockNumber``) is the low byte of this element.
    /// Private data elements use (group, block*256 + nn) where nn is 0x00-0xFF.
    public let element: UInt16
    
    /// Block number (0x10 - 0xFF)
    ///
    /// The block number is the lower byte of the private creator element.
    /// Private data elements use (group, block*256 + nn) where nn is 0x00-0xFF.
    public var blockNumber: UInt8 {
        guard element >= 0x0010 && element <= 0x00FF else { return 0 }
        return UInt8(element & 0xFF)
    }
    
    /// Creates a private creator
    /// - Parameters:
    ///   - creatorID: Creator identification string
    ///   - group: Group number (must be odd)
    ///   - element: Private creator element (0x0010-0x00FF)
    public init(creatorID: String, group: UInt16, element: UInt16) {
        self.creatorID = creatorID
        self.group = group
        self.element = element
    }
    
    /// Tag for the private creator element
    public var tag: Tag {
        Tag(group: group, element: element)
    }
    
    /// Returns the tag for a private data element in this creator's block
    /// - Parameter offset: Element offset within the block (0x00-0xFF)
    /// - Returns: Private data element tag
    public func privateTag(offset: UInt8) -> Tag? {
        let elementNumber = UInt16(blockNumber) * 256 + UInt16(offset)
        return Tag(group: group, element: elementNumber)
    }
    
    /// Checks if a tag belongs to this private creator's block
    /// - Parameter tag: Tag to check
    /// - Returns: True if the tag is in this creator's private block
    public func owns(_ tag: Tag) -> Bool {
        guard tag.group == group else { return false }
        
        // Block number is upper byte of element number
        // For creator at 0x0010, block is 0x10, elements are 0x1000-0x10FF
        let tagBlock = UInt8(tag.element >> 8)
        return tagBlock == blockNumber
    }
}

// MARK: - CustomStringConvertible
extension PrivateCreator: CustomStringConvertible {
    public var description: String {
        return "\(creatorID) at \(tag)"
    }
}

// MARK: - Well-Known Private Creators
extension PrivateCreator {
    /// Well-known vendor private creators
    public enum WellKnown {
        // MARK: Siemens
        
        /// Siemens CSA Header (typically at group 0x0029)
        public static func siemensCSA(group: UInt16 = 0x0029, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "SIEMENS CSA HEADER", group: group, element: element)
        }
        
        /// Siemens MR Header (typically at group 0x0019)
        public static func siemensMRHeader(group: UInt16 = 0x0019, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "SIEMENS MR HEADER", group: group, element: element)
        }
        
        /// Siemens CT Header
        public static func siemensCTHeader(group: UInt16 = 0x0019, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "SIEMENS CT HEADER", group: group, element: element)
        }
        
        // MARK: GE Healthcare
        
        /// GE Medical Systems Private Group
        public static func geMedical(group: UInt16 = 0x0009, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "GEMS_IDEN_01", group: group, element: element)
        }
        
        /// GE Acquisition private group (GEMS_ACQU_01). The Protocol Data Block lives in
        /// GEMS_SERS_01 (0025,xx1B), see `geSeries`.
        public static func geProtocol(group: UInt16 = 0x0019, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "GEMS_ACQU_01", group: group, element: element)
        }
        
        /// GE Series Data Block
        public static func geSeries(group: UInt16 = 0x0025, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "GEMS_SERS_01", group: group, element: element)
        }
        
        // MARK: Philips
        
        /// Philips Imaging Private Group
        public static func philipsImaging(group: UInt16 = 0x2001, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "Philips Imaging DD 001", group: group, element: element)
        }
        
        /// Philips MR Imaging Private Group
        public static func philipsMR(group: UInt16 = 0x2005, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "Philips MR Imaging DD 001", group: group, element: element)
        }
        
        // MARK: Canon/Toshiba
        
        /// Canon/Toshiba Private Group
        public static func canon(group: UInt16 = 0x7005, element: UInt16 = 0x0010) -> PrivateCreator {
            PrivateCreator(creatorID: "TOSHIBA_MEC_MR3", group: group, element: element)
        }
    }
}
