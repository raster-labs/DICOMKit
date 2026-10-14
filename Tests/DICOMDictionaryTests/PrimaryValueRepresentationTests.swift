import Testing
import DICOMCore
@testable import DICOMDictionary

@Suite("Primary VR dictionary projection")
struct PrimaryValueRepresentationTests {
    @Test("Every maintained dictionary entry and repeating-group alias has identical primary VR")
    func parity() {
        for entry in DataElementDictionary.allEntries {
            #expect(DataElementDictionary.primaryValueRepresentation(for: entry.tag) == entry.vr.first)
            if entry.tag.group == 0x5000 || entry.tag.group == 0x6000 {
                for delta in stride(from: UInt16(2), through: 254, by: 2) {
                    let alias = Tag(group: entry.tag.group + delta, element: entry.tag.element)
                    #expect(DataElementDictionary.primaryValueRepresentation(for: alias) == entry.vr.first)
                }
            }
        }
        let unknown = Tag(group: 0x7777, element: 0x0123) // Private test attribute
        #expect(DataElementDictionary.primaryValueRepresentation(for: unknown) == nil)
    }
}
