import Testing
@testable import DICOMDictionary
@testable import DICOMCore

/// Pins the generated tables to the DICOM 2026a text they were generated from
/// (DICOMDICTIONARY_STANDARD_IMPLEMENTATION.md). The row counts and the sampled
/// rows come from the frozen PS3.4, PS3.6 and PS3.7 2026a DocBook; the full
/// row-by-row check is `Scripts/diff_dictionary.py`.
@Suite("DICOM 2026a dictionary tables")
struct Standard2026aTests {

    // MARK: Data elements

    @Test("Row count: PS3.6 Tables 6-1, 7-1, 8-1, 9-1 plus PS3.7 Tables E.1-1, E.2-1")
    func elementRowCount() {
        // 5,238 + 22 + 19 + 1 + 24 + 22, with the 50xx/60xx repeating rows stored
        // once at their base group and the three FFFE delimiters not emitted.
        #expect(DataElementDictionary.allEntries.count == 5326)
    }

    @Test("Elements added after the pydicom 2.4.4 dictionary are present")
    func elementsNewIn2026a() {
        let expected: [(UInt16, UInt16, String, VR, String)] = [
            (0x0006, 0x0001, "CurrentFrameFunctionalGroupsSequence", .SQ, "1"),   // Table 9-1
            (0x0008, 0x001C, "SyntheticData", .CS, "1"),
            (0x0010, 0x0044, "GenderIdentityCodeSequence", .SQ, "1"),
            (0x0010, 0x2162, "EthnicGroups", .UC, "1-n"),
            (0x0012, 0x0022, "IssuerOfClinicalTrialProtocolID", .LO, "1"),
            (0x0014, 0x6020, "AcquisitionImageCounter", .UV, "1"),
            (0x0018, 0x1204, "DateOfManufacture", .DA, "1"),
            (0x0018, 0x9826, "ExcitationWavelength", .FD, "1"),
        ]
        for (g, e, keyword, vr, vm) in expected {
            let entry = DataElementDictionary.lookup(tag: Tag(group: g, element: e))
            #expect(entry?.keyword == keyword, "(\(String(g, radix: 16)),\(String(e, radix: 16)))")
            #expect(entry?.vr == [vr])
            #expect(entry?.vm == vm)
            #expect(entry?.retired == false)
        }
    }

    @Test("Keywords, names, VM and retired flags that differed from PS3.6 2026a")
    func correctedRows() {
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x003A, element: 0x0320))?.keyword == "SummarizedFilterLookupTableSequence")
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x003A, element: 0x0325))?.keyword == "AnalogFilterTypeCodeSequence")
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0018, element: 0x1153))?.name == "Exposure in µAs")
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x5200, element: 0x9230))?.name == "Per-Frame Functional Groups Sequence")
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0028, element: 0x1200))?.vm == "1-n or 1")
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0028, element: 0x3006))?.vm == "1-n or 1")
        for (g, e): (UInt16, UInt16) in [(0x0010, 0x2160), (0x0038, 0x0004), (0x0070, 0x1807), (0x0070, 0x1808)] {
            #expect(DataElementDictionary.lookup(tag: Tag(group: g, element: e))?.retired == true)
        }
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x3004, element: 0x0012))?.retired == false)
    }

    @Test("Command elements come from PS3.7 Tables E.1-1 and E.2-1")
    func commandElements() {
        let group0 = DataElementDictionary.allEntries.filter { $0.tag.group == 0x0000 }
        #expect(group0.count == 46)
        #expect(group0.filter { $0.retired }.count == 22)
        let status = DataElementDictionary.lookup(tag: Tag(group: 0x0000, element: 0x0900))
        #expect(status?.keyword == "Status")
        #expect(status?.vr == [.US])
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0000, element: 0x0001))?.retired == true)
    }

    @Test("Delimiters are not dictionary entries")
    func delimitersAbsent() {
        for element: UInt16 in [0xE000, 0xE00D, 0xE0DD] {
            #expect(DataElementDictionary.lookup(tag: Tag(group: 0xFFFE, element: element)) == nil)
        }
    }

    // MARK: UID registry

    @Test("UID registry holds every row of PS3.6 Table A-1")
    func uidRegistryCounts() {
        #expect(UIDDictionary.registryEntries.count == 465)
        #expect(UIDDictionary.registryEntries.filter { $0.type == .transferSyntax }.count == 63)
        #expect(UIDDictionary.registryEntries.filter { $0.type == .sopClass }.count == 311)
        #expect(UIDDictionary.registryEntries.filter { $0.retired }.count == 75)
        #expect(UIDDictionary.registryEntries.allSatisfy { $0.registered })
        #expect(UIDDictionary.allEntries.count == 465 + UIDDictionary.unregisteredEntries.count)
        #expect(Set(UIDDictionary.registryEntries.map(\.uid)).count == 465, "no duplicate UIDs")
    }

    @Test("Transfer Syntaxes DICOMCore decodes are all in the registry")
    func transferSyntaxesMatchDICOMCore() {
        // Only UIDs under the DICOM root; DICOMCore also carries private (vendor-rooted)
        // syntaxes that PS3.6 cannot register.
        for ts in TransferSyntax.allKnown where ts.uid.hasPrefix("1.2.840.10008.") {
            let entry = UIDDictionary.lookup(uid: ts.uid)
            #expect(entry != nil, Comment(rawValue: ts.uid))
            #expect(entry?.type == .transferSyntax)
        }
        let unregistered = UIDDictionary.unregisteredEntries.map(\.uid)
        #expect(unregistered == ["1.2.840.10008.1.2.4.107.1", "1.2.840.10008.1.2.4.108.1"])
        for uid in unregistered {
            #expect(UIDDictionary.lookup(uid: uid)?.registered == false)
        }
    }

    @Test("Registry rows sampled against Table A-1")
    func uidRows() {
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.4.92")?.keyword == "JPEG2000MCLossless")
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.4.93")?.keyword == "JPEG2000MC")
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.2")?.retired == true)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.2")?.name == "Explicit VR Big Endian (Retired)")
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.4.80")?.keyword == "JPEGLSLossless")
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.4.110")?.type == .transferSyntax)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.4.2")?.type == .serviceClass)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.7.1.1")?.type == .applicationHostingModel)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.8.1.1")?.type == .mappingResource)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.15.1.1")?.type == .synchronizationFrameOfReference)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.2.6.1")?.type == .codingScheme)
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.3.1.2.3.3")?.type == .sopClass)   // Modality Performed Procedure Step
        #expect(UIDDictionary.lookup(uid: "1.2.840.10008.5.1.4.1.1.88.67")?.name == "X-Ray Radiation Dose SR Storage")
        #expect(UIDDictionary.lookup(keyword: "CTImageStorage")?.uid == "1.2.840.10008.5.1.4.1.1.2")
    }

    // MARK: Storage SOP Classes

    @Test("Storage SOP Classes are PS3.4 Tables B.5-1 and B.6-1")
    func storageSOPClasses() {
        #expect(StorageSOPClass.allUIDs.count == 170)
        #expect(StorageSOPClass.retiredUIDs.count == 4)
        #expect(Set(StorageSOPClass.allUIDs).count == 170, "no duplicates")
        #expect(StorageSOPClass.allUIDSet.isDisjoint(with: StorageSOPClass.retiredUIDSet))
        // Every entry is a registered SOP Class.
        for uid in StorageSOPClass.allUIDs + StorageSOPClass.retiredUIDs {
            #expect(UIDDictionary.lookup(uid: uid)?.type == .sopClass, Comment(rawValue: uid))
        }
        // Classes that were missing before 2026-09-28.
        for uid in ["1.2.840.10008.5.1.4.1.1.88.67",   // X-Ray Radiation Dose SR
                    "1.2.840.10008.5.1.4.1.1.481.8",   // RT Ion Plan
                    "1.2.840.10008.5.1.4.1.1.30",      // Parametric Map
                    "1.2.840.10008.5.1.4.1.1.104.3",   // Encapsulated STL
                    "1.2.840.10008.5.1.4.1.1.6.3"] {   // Photoacoustic Image
            #expect(StorageSOPClass.allUIDSet.contains(uid), Comment(rawValue: uid))
        }
        // Retired classes are recognised but not proposed.
        #expect(StorageSOPClass.isStorage("1.2.840.10008.5.1.4.1.1.5"))          // NM Image Storage (Retired)
        #expect(!StorageSOPClass.allUIDSet.contains("1.2.840.10008.5.1.4.1.1.5"))
        #expect(!StorageSOPClass.isStorage("1.2.840.10008.1.1"))                   // Verification
        // Common imaging classes keep the low presentation-context IDs.
        #expect(StorageSOPClass.allUIDs.first == "1.2.840.10008.5.1.4.1.1.1")
        #expect(StorageSOPClass.allUIDs.prefix(78).contains("1.2.840.10008.5.1.4.1.1.2"))
    }
}
