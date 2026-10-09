/// DICOM Data Element Tag
///
/// A tag uniquely identifies a data element and consists of an ordered pair
/// of 16-bit unsigned integers: group number and element number.
///
/// Reference: DICOM PS3.5 Section 7.1 - Data Elements
///
/// NEMA-verified: 2026a, checked 2026-09-25 — a Tag is the (group, element) pair of PS3.5 2026a §7.1.1, and private groups are the odd ones (§7.8.1). No other standard data.
/// NEMA-verified: 2026a, checked 2026-10-01 — `isPrivate` follows PS3.5 2026a §7.1 ("Private Data Elements have an odd Group Number that is not 0001, 0003, 0005, 0007, or FFFF"; §7.8.1: those groups "shall not be used"); `isOddGroup` keeps the plain parity test (D151).
public struct Tag: Sendable, Hashable, Comparable {
    /// Group number (16-bit unsigned integer)
    public let group: UInt16
    
    /// Element number (16-bit unsigned integer)
    public let element: UInt16
    
    /// Creates a new DICOM tag
    /// - Parameters:
    ///   - group: Group number
    ///   - element: Element number
    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }
    
    /// Indicates whether this is a private tag
    ///
    /// "Private Data Elements have an odd Group Number that is not 0001, 0003, 0005, 0007, or
    /// FFFF" (PS3.5 2026a 7.1). Elements in those five groups "shall not be used" (7.8.1); they
    /// are neither Standard nor Private, and ``isOddGroup`` still reports them. Before
    /// 2026-10-01 this was the parity test alone (D151).
    ///
    /// Reference: PS3.5 Section 7.1 - Data Elements; Section 7.8 - Private Data Elements
    public var isPrivate: Bool {
        isOddGroup && !Tag.unusableOddGroups.contains(group)
    }

    /// Whether the group number is odd: a Private Data Element, or an element in one of the
    /// groups 0001, 0003, 0005, 0007 and FFFF that PS3.5 7.8.1 says "shall not be used".
    /// De-identification and "remove private" passes test this, so such elements go too.
    public var isOddGroup: Bool {
        (group & 0x0001) != 0
    }

    /// The odd groups that are not Private (PS3.5 2026a 7.1) and shall not be used (7.8.1).
    public static let unusableOddGroups: Set<UInt16> = [0x0001, 0x0003, 0x0005, 0x0007, 0xFFFF]
    
    /// Comparable conformance - tags are ordered by group, then element
    public static func < (lhs: Tag, rhs: Tag) -> Bool {
        if lhs.group != rhs.group {
            return lhs.group < rhs.group
        }
        return lhs.element < rhs.element
    }
}

// MARK: - CustomStringConvertible
extension Tag: CustomStringConvertible {
    /// Formatted string representation in (GGGG,EEEE) format
    public var description: String {
        return String(format: "(%04X,%04X)", group, element)
    }
}
