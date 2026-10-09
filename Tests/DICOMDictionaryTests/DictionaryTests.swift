import Testing
import Foundation
@testable import DICOMDictionary
@testable import DICOMCore

@Suite("Dictionary Tests")
struct DictionaryTests {

    @Test("Packaged app dictionary bundle resolves from Resources")
    func packagedAppDictionaryBundleResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let packaged = resources.appendingPathComponent(
            DICOMDictionaryResourceBundle.bundleName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Bundle.module.bundleURL, to: packaged)

        let resolved = DICOMDictionaryResourceBundle.packagedBundle(
            mainResourceURL: resources)
        #expect(resolved?.bundleURL.standardizedFileURL == packaged.standardizedFileURL)
        #expect(
            resolved?.url(forResource: "DataElementDictionary", withExtension: "txt")
                != nil)
    }
    
    @Test("Data element dictionary lookup by tag")
    func testDataElementLookupByTag() {
        let entry = DataElementDictionary.lookup(tag: .patientName)
        #expect(entry != nil)
        #expect(entry?.name == "Patient's Name")
        #expect(entry?.keyword == "PatientName")
        #expect(entry?.vr.contains(.PN) == true)
    }
    
    @Test("Data element dictionary lookup by keyword")
    func testDataElementLookupByKeyword() {
        let entry = DataElementDictionary.lookup(keyword: "PatientName")
        #expect(entry != nil)
        #expect(entry?.tag == .patientName)
        #expect(entry?.name == "Patient's Name")
    }
    
    @Test("File Meta Information elements")
    func testFileMetaInformationElements() {
        let transferSyntax = DataElementDictionary.lookup(tag: .transferSyntaxUID)
        #expect(transferSyntax != nil)
        #expect(transferSyntax?.keyword == "TransferSyntaxUID")
        #expect(transferSyntax?.vr.contains(.UI) == true)
        
        let sopClassUID = DataElementDictionary.lookup(tag: .mediaStorageSOPClassUID)
        #expect(sopClassUID != nil)
        #expect(sopClassUID?.keyword == "MediaStorageSOPClassUID")
    }
    
    @Test("64-bit Value Representations are declared for the CP 1818 (Extended Offset Table) and CP 1819 (0072,008x / 0008,04xx) elements")
    func testSixtyFourBitElements() {
        #expect(DataElementDictionary.lookup(tag: .extendedOffsetTable)?.vr == [.OV])
        #expect(DataElementDictionary.lookup(tag: .extendedOffsetTableLengths)?.vr == [.OV])
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x7FE0, element: 0x0003))?.vr == [.UV])
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0072, element: 0x0081))?.vr == [.OV])
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0072, element: 0x0082))?.vr == [.SV])
        #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0072, element: 0x0083))?.vr == [.UV])
        for element: UInt16 in [0x040C, 0x040D, 0x0428, 0x0429] {
            #expect(DataElementDictionary.lookup(tag: Tag(group: 0x0008, element: element))?.vr == [.UV])
        }
    }

    @Test("UID dictionary lookup by UID")
    func testUIDLookupByUID() {
        let entry = UIDDictionary.lookup(uid: "1.2.840.10008.1.2.1")
        #expect(entry != nil)
        #expect(entry?.name == "Explicit VR Little Endian")
        #expect(entry?.keyword == "ExplicitVRLittleEndian")
        #expect(entry?.type == .transferSyntax)
    }
    
    @Test("UID dictionary lookup by keyword")
    func testUIDLookupByKeyword() {
        let entry = UIDDictionary.lookup(keyword: "ExplicitVRLittleEndian")
        #expect(entry != nil)
        #expect(entry?.uid == "1.2.840.10008.1.2.1")
        #expect(entry?.type == .transferSyntax)
    }
    
    @Test("Transfer Syntax UIDs")
    func testTransferSyntaxUIDs() {
        let transferSyntaxes = UIDDictionary.transferSyntaxes
        #expect(transferSyntaxes.count >= 3)
        
        let explicitVRLE = transferSyntaxes.first { $0.uid == "1.2.840.10008.1.2.1" }
        #expect(explicitVRLE != nil)
    }
    
    @Test("SOP Class UIDs")
    func testSOPClassUIDs() {
        let sopClasses = UIDDictionary.sopClasses
        #expect(sopClasses.count >= 1)
        
        let ctImage = UIDDictionary.lookup(uid: "1.2.840.10008.5.1.4.1.1.2")
        #expect(ctImage != nil)
        #expect(ctImage?.name == "CT Image Storage")
        #expect(ctImage?.type == .sopClass)
    }

    @Test("Visible Light still-image SOP classes resolve to names")
    func testVisibleLightStillSOPClasses() {
        let expected = [
            "1.2.840.10008.5.1.4.1.1.77.1.1": "VL Endoscopic Image Storage",
            "1.2.840.10008.5.1.4.1.1.77.1.2": "VL Microscopic Image Storage",
            "1.2.840.10008.5.1.4.1.1.77.1.3": "VL Slide-Coordinates Microscopic Image Storage",
            "1.2.840.10008.5.1.4.1.1.77.1.4": "VL Photographic Image Storage"
        ]
        for (uid, name) in expected {
            let entry = UIDDictionary.lookup(uid: uid)
            #expect(entry != nil, "No entry for \(uid)")
            #expect(entry?.name == name)
            #expect(entry?.type == .sopClass)
        }
    }

    @Test("Still and video VL SOP classes are distinct entries")
    func testStillAndVideoVLAreDistinct() {
        // The trailing ".1" distinguishes the video class from the still class;
        // both must resolve, and to different names.
        let still = UIDDictionary.lookup(uid: "1.2.840.10008.5.1.4.1.1.77.1.4")
        let video = UIDDictionary.lookup(uid: "1.2.840.10008.5.1.4.1.1.77.1.4.1")
        #expect(still?.name == "VL Photographic Image Storage")
        #expect(video?.name == "Video Photographic Image Storage")
        #expect(still?.name != video?.name)
    }
}
