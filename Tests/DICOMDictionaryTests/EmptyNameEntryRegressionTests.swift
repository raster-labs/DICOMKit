import Testing
@testable import DICOMDictionary
@testable import DICOMCore

/// Regression test for M4 (see BUG_REVIEW.md): dictionary rows whose Name field
/// is empty were dropped because `split(separator:)` omitted empty subsequences,
/// collapsing the 6-column row to 5 and failing the field-count guard.
///
/// PS3.6 2026a has two kinds of blank rows, and both must load:
/// - a blank Name and Keyword but a VR and VM: (0018,0061), (0400,0315), (300A,0782);
/// - every cell blank except the tag and the RET flag: (0008,0202), (0018,9445), (0028,0020).
@Suite("Empty-Name Dictionary Entry Regression Tests")
struct EmptyNameEntryRegressionTests {

    @Test("Tags with an empty Name field are still present in the dictionary")
    func testEmptyNameEntriesArePresent() {
        let cases: [(UInt16, UInt16, VR)] = [
            (0x0018, 0x0061, .DS),
            (0x0400, 0x0315, .FL),
            (0x300A, 0x0782, .US),
        ]

        for (group, element, expectedVR) in cases {
            let entry = DataElementDictionary.lookup(tag: Tag(group: group, element: element))
            #expect(entry != nil, "expected (\(String(group, radix: 16)),\(String(element, radix: 16))) to be present")
            #expect(entry?.vr.contains(expectedVR) == true)
            #expect(entry?.name == "")
            #expect(entry?.keyword == "")
            #expect(entry?.retired == true)
        }
    }

    @Test("Rows that are blank in every PS3.6 column load with an empty name and keyword and VR UN")
    func testFullyBlankRows() {
        for (group, element): (UInt16, UInt16) in [(0x0008, 0x0202), (0x0018, 0x9445), (0x0028, 0x0020)] {
            let entry = DataElementDictionary.lookup(tag: Tag(group: group, element: element))
            #expect(entry != nil)
            #expect(entry?.name == "")
            #expect(entry?.keyword == "")
            #expect(entry?.vr == [.UN])
            #expect(entry?.vm == "")
            #expect(entry?.retired == true)
        }
    }

    @Test("An empty keyword never matches a blank-keyword row")
    func testEmptyKeywordLookupIsNil() {
        #expect(DataElementDictionary.lookup(keyword: "") == nil)
        #expect(UIDDictionary.lookup(keyword: "") == nil)
    }
}
