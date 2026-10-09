// NEMA-verified: 2026a, checked 2026-10-01 — Private Creator Data Elements are (gggg,0010-00FF) with gggg odd (PS3.5 2026a 7.8.1); Item, Item Delimitation Item and Sequence Delimitation Item names and keywords are the (FFFE,E000/E00D/E0DD) rows of PS3.6 2026a Table 6-1 (3 rows), which the data dictionary resource does not carry (no VR)
import DICOMCore
import DICOMDictionary

/// Names for tags the PS3.6 data dictionary has no row for, shared by the presenters
/// (`MetadataPresenter`, `HexDumper`, `TagEditor`) so they label them the same way.
enum AttributeNames {

    /// PS3.5 2026a 7.8.1: "Private Creator Data Elements numbered (gggg,0010-00FF) (gggg is
    /// odd) shall be used to reserve a block of Elements".
    static let privateCreatorName = "Private Creator"

    /// Whether `tag` is a Private Creator Data Element (PS3.5 7.8.1).
    static func isPrivateCreator(_ tag: Tag) -> Bool {
        tag.isPrivate && (0x0010...0x00FF).contains(tag.element)
    }

    /// The three (FFFE,xxxx) rows of PS3.6 2026a Table 6-1: (name, keyword). They have no VR
    /// (PS3.5 7.5), so the dictionary resource leaves them out.
    static let delimiters: [Tag: (name: String, keyword: String)] = [
        Tag(group: 0xFFFE, element: 0xE000): ("Item", "Item"),
        Tag(group: 0xFFFE, element: 0xE00D): ("Item Delimitation Item", "ItemDelimitationItem"),
        Tag(group: 0xFFFE, element: 0xE0DD): ("Sequence Delimitation Item", "SequenceDelimitationItem"),
    ]

    /// The PS3.6 name, "Private Creator" for a Private Creator Data Element, the delimiter
    /// names of Table 6-1, else nil.
    static func name(for tag: Tag) -> String? {
        if let entry = DataElementDictionary.lookup(tag: tag) { return entry.name }
        if isPrivateCreator(tag) { return privateCreatorName }
        return delimiters[tag]?.name
    }
}
