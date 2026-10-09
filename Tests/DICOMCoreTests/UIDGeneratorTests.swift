import Testing
@testable import DICOMCore

/// Generated UIDs must satisfy the encoding rules of PS3.5 2026a §9.1.
@Suite("UIDGenerator Tests")
struct UIDGeneratorTests {

    /// The §9.1 rules, checked directly on the string rather than through the parser.
    private func assertEncodingRules(_ uid: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(uid.count <= 64, "at most 64 characters: \(uid)", sourceLocation: sourceLocation)
        #expect(!uid.isEmpty, sourceLocation: sourceLocation)
        let components = uid.split(separator: ".", omittingEmptySubsequences: false)
        for component in components {
            #expect(!component.isEmpty, "no empty component in \(uid)", sourceLocation: sourceLocation)
            #expect(component.allSatisfy { ("0"..."9").contains($0) }, "digits only in \(uid)", sourceLocation: sourceLocation)
            if component.count > 1 {
                #expect(component.first != "0", "no leading zero in \(component) of \(uid)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test("Default root is a valid UID prefix")
    func testDefaultRoot() {
        assertEncodingRules(UIDGenerator.defaultRoot)
        #expect(DICOMUniqueIdentifier.parse(UIDGenerator.defaultRoot) != nil)
    }

    /// PS3.5 2026a §9.2.2: privately defined UIDs are built on a registered root the
    /// defining organisation owns. The library's root is the one its JP3D transfer
    /// syntaxes already use, never the OFFIS DCMTK root (`1.2.276.0.7230010.3`).
    @Test("Default root is the library's private root, not the DCMTK root (PS3.5 9.2.2)")
    func testDefaultRootIsOwnRoot() {
        #expect(UIDGenerator.defaultRoot == "1.2.826.0.1.3680043.10.511.4")
        #expect(!UIDGenerator.defaultRoot.hasPrefix("1.2.276.0.7230010"))
        // Generated UIDs must still fit in 64 characters with the longer root (§9.1).
        let generator = UIDGenerator()
        for _ in 0..<50 {
            let uid = generator.generate(type: 3).value
            #expect(uid.count <= 64)
            #expect(uid.hasPrefix("1.2.826.0.1.3680043.10.511.4.3."))
        }
    }

    @Test("generate() obeys PS3.5 §9.1 and starts with the root")
    func testGenerate() {
        let generator = UIDGenerator()
        for _ in 0..<200 {
            let uid = generator.generate().value
            assertEncodingRules(uid)
            #expect(uid.hasPrefix(UIDGenerator.defaultRoot + "."))
        }
    }

    @Test("Typed generators insert the type component after the root")
    func testTypedGenerators() {
        let generator = UIDGenerator()
        #expect(generator.generateStudyInstanceUID().value.hasPrefix(UIDGenerator.defaultRoot + ".1."))
        #expect(generator.generateSeriesInstanceUID().value.hasPrefix(UIDGenerator.defaultRoot + ".2."))
        #expect(generator.generateSOPInstanceUID().value.hasPrefix(UIDGenerator.defaultRoot + ".3."))
        for _ in 0..<50 {
            assertEncodingRules(generator.generate(type: 255).value)
        }
    }

    @Test("A long custom root is truncated to 64 characters without breaking the rules")
    func testLongRootTruncates() {
        // A 51-character root leaves too little room for timestamp + random.
        let root = "1.2.826.0.1.3680043.9.7433.1234567890.1234567890.12"
        #expect(root.count == 51)
        let generator = UIDGenerator(root: root)
        for _ in 0..<50 {
            let uid = generator.generate().value
            assertEncodingRules(uid)
            #expect(uid.count <= 64)
            #expect(!uid.hasSuffix("."))
        }
    }

    @Test("Consecutive UIDs are distinct")
    func testDistinct() {
        let generator = UIDGenerator()
        var seen = Set<String>()
        for _ in 0..<500 { seen.insert(generator.generate().value) }
        #expect(seen.count == 500)
    }
}
