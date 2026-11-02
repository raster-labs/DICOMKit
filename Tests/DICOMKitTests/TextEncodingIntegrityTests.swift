import Foundation
import Testing
import DICOMCore
@testable import DICOMKit

@Suite("M2 text encoding and edited identity integrity")
struct TextEncodingIntegrityTests {
    private let latin1 = "ISO_IR 100"
    private let japanese = "\\ISO 2022 IR 87"
    private let sequenceTag = Tag(group: 0x0040, element: 0x0275)

    private func raw(_ value: String, tag: DICOMCore.Tag = .patientName, vr: VR = .PN, charset: String) -> DataElement {
        var bytes = CharacterSetHandler.from(specificCharacterSet: charset).encode(value)
        if bytes.count % 2 != 0 { bytes.append(0x20) }
        return DataElement(tag: tag, vr: vr, length: UInt32(bytes.count), valueData: bytes)
    }

    private func legacyDataSet() -> DataSet {
        let inherited = SequenceItem(elements: [raw("Müller^Jörg", charset: latin1)])
        let override = SequenceItem(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: japanese),
            raw("Yamada^Tarou=山田^太郎", charset: japanese),
        ])
        return DataSet(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: latin1),
            raw("Müller^Jörg", charset: latin1),
            raw("  Unedited café", tag: .studyDescription, vr: .LO, charset: latin1),
            DataElement(tag: sequenceTag, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(),
                        sequenceItems: [inherited, override]),
        ])
    }

    private func roundTrip(_ dataset: DataSet) throws -> DICOMFile {
        try DICOMFile.read(from: DICOMFile.create(dataSet: dataset).write())
    }

    @Test("Raw Latin-1 and nested inherited/overridden declarations decode and round trip")
    func legacyRoundTrip() throws {
        let original = legacyDataSet()
        let decoded = try roundTrip(original).dataSet
        #expect(decoded.string(for: .patientName) == "Müller^Jörg")
        #expect(decoded[.patientName]?.valueData == original[.patientName]?.valueData)
        #expect(decoded.string(for: .specificCharacterSet) == latin1)
        #expect(decoded.string(for: .studyDescription) == "  Unedited café")
        let items = try #require(decoded[sequenceTag]?.sequenceItems)
        #expect(items[0].string(for: .patientName) == "Müller^Jörg")
        #expect(items[1].string(for: .patientName) == "Yamada^Tarou=山田^太郎")
        #expect(items[1].string(for: .specificCharacterSet) == japanese)
    }

    @Test("Selected metadata retains its text decoding context without adding an unrequested tag")
    func selectedMetadataCharset() throws {
        let bytes = try DICOMFile.create(dataSet: legacyDataSet()).write()
        let result = try DICOMMetadataDiscovery.read(byteCount: bytes.count, retaining: [.patientName]) { offset, count in
            bytes.subdata(in: offset..<(offset + count))
        }
        #expect(result.selectedRootElements.tags == [.patientName])
        #expect(result.selectedRootElements.string(for: .patientName) == "Müller^Jörg")
    }

    @Test("Unicode edit transcodes all legacy and nested text, preserving unedited values")
    func unicodeEdit() throws {
        var dataset = try roundTrip(legacyDataSet()).dataSet
        _ = try TagEditor().applyCheckedChanges(to: &dataset, sets: ["PatientName=患者^新"], deletes: [],
            deletePrivate: false, sourceDataSet: nil, copyTags: [], verbose: false, dryRun: false)
        let decoded = try roundTrip(dataset).dataSet
        #expect(decoded.string(for: .specificCharacterSet) == "ISO_IR 192")
        #expect(decoded.string(for: .patientName) == "患者^新")
        #expect(decoded.string(for: .studyDescription) == "  Unedited café")
        #expect(String(data: try #require(decoded[.studyDescription]?.valueData), encoding: .utf8) != nil)
        let items = try #require(decoded[sequenceTag]?.sequenceItems)
        #expect(items[0].string(for: .patientName) == "Müller^Jörg")
        #expect(items[1].string(for: .patientName) == "Yamada^Tarou=山田^太郎")
        #expect(items[1].string(for: .specificCharacterSet) == "ISO_IR 192")
    }

    @Test("New UTF-8 values obtain a declaration and retain leading spaces")
    func undeclaredNewUnicode() throws {
        var dataset = DataSet()
        dataset.setString("  Müller^Jörg", for: .patientName, vr: .PN)
        let decoded = try roundTrip(dataset).dataSet
        #expect(decoded.string(for: .specificCharacterSet) == "ISO_IR 192")
        #expect(decoded.string(for: .patientName) == "  Müller^Jörg")
    }

    @Test("Copying text from Latin-1 into a UTF-8 dataset retains the selected text")
    func copyAcrossCharsets() throws {
        var destination = DataSet(elements: [.string(tag: .patientName, vr: .PN, value: "患者")])
        _ = try TagEditor().applyCheckedChanges(to: &destination, sets: [], deletes: [], deletePrivate: false,
            sourceDataSet: legacyDataSet(), copyTags: ["PatientName"], verbose: false, dryRun: false)
        let decoded = try roundTrip(destination).dataSet
        #expect(decoded.string(for: .patientName) == "Müller^Jörg")
        #expect(decoded.string(for: .specificCharacterSet) == "ISO_IR 192")
    }

    @Test("Copying a complete mixed-charset dataset preserves explicit Item overrides")
    func copyAllWithOverride() throws {
        var destination = DataSet()
        _ = try TagEditor().applyCheckedChanges(to: &destination, sets: [], deletes: [], deletePrivate: false,
            sourceDataSet: legacyDataSet(), copyTags: [], verbose: false, dryRun: false)
        let decoded = try roundTrip(destination).dataSet
        #expect(decoded.string(for: .specificCharacterSet) == latin1)
        #expect(decoded.string(for: .patientName) == "Müller^Jörg")
        let items = try #require(decoded[sequenceTag]?.sequenceItems)
        #expect(items[0].string(for: .patientName) == "Müller^Jörg")
        #expect(items[1].string(for: .patientName) == "Yamada^Tarou=山田^太郎")
        #expect(items[1].string(for: .specificCharacterSet) == "ISO_IR 192")
    }

    @Test("Unsupported, malformed and unrepresentable encodings fail without substitution")
    func failedConversions() throws {
        #expect(throws: DICOMTextEncodingError.self) { try legacyDataSet().transcodingText(to: "") }
        #expect(throws: DICOMTextEncodingError.self) { try legacyDataSet().transcodingText(to: "UNKNOWN") }
        let malformed = DataSet(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: "ISO_IR 192"),
            DataElement(tag: .patientName, vr: .PN, length: 2, valueData: Data([0xC3, 0x20])),
        ])
        #expect(throws: DICOMTextEncodingError.self) { try malformed.transcodingText() }
        #expect(throws: DICOMTextEncodingError.self) { try DICOMFile.create(dataSet: malformed).write() }
        let rawUndeclared = DataSet(elements: [raw("Müller", charset: latin1)])
        #expect(throws: DICOMTextEncodingError.self) { try DICOMFile.create(dataSet: rawUndeclared).write() }
    }

    @Test("An empty Item declaration overrides its parent rather than inheriting Latin-1")
    func emptyOverrideRejectsLatin1Bytes() {
        let item = SequenceItem(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: ""),
            raw("Müller", charset: latin1),
        ])
        let dataset = DataSet(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: latin1),
            DataElement(tag: sequenceTag, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(), sequenceItems: [item]),
        ])
        #expect(dataset[sequenceTag]?.sequenceItems?.first?.string(for: .patientName) == nil)
        #expect(throws: DICOMTextEncodingError.self) { try dataset.transcodingText() }
    }

    @Test("Nested UTF-8 override is independent of its Latin-1 parent and validates its bytes")
    func utf8Override() throws {
        let valid = SequenceItem(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: "ISO_IR 192"),
            raw("患者", charset: "ISO_IR 192"),
        ])
        var dataset = DataSet(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: latin1),
            raw("Müller", charset: latin1),
            DataElement(tag: sequenceTag, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(), sequenceItems: [valid]),
        ])
        let decoded = try roundTrip(dataset).dataSet
        #expect(decoded.string(for: .patientName) == "Müller")
        #expect(decoded[sequenceTag]?.sequenceItems?.first?.string(for: .patientName) == "患者")
        let invalid = SequenceItem(elements: [
            .string(tag: .specificCharacterSet, vr: .CS, value: "ISO_IR 192"),
            DataElement(tag: .patientName, vr: .PN, length: 2, valueData: Data([0xC3, 0x20])),
        ])
        dataset.setSequence([invalid], for: sequenceTag)
        #expect(throws: DICOMTextEncodingError.self) { try dataset.transcodingText() }
        #expect(throws: DICOMTextEncodingError.self) { try DICOMFile.create(dataSet: dataset).write() }
    }

    @Test("Explicit charset conversion changes every affected value, never only its label")
    func explicitCharsetChange() throws {
        var dataset = DataSet(elements: [.string(tag: .patientName, vr: .PN, value: "Müller^Jörg")])
        _ = try TagEditor().applyCheckedChanges(to: &dataset, sets: ["SpecificCharacterSet=ISO_IR 100"],
            deletes: [], deletePrivate: false, sourceDataSet: nil, copyTags: [], verbose: false, dryRun: false)
        let decoded = try roundTrip(dataset).dataSet
        #expect(decoded.string(for: .specificCharacterSet) == latin1)
        #expect(decoded[.patientName]?.valueData == raw("Müller^Jörg", charset: latin1).valueData)
        #expect(decoded.string(for: .patientName) == "Müller^Jörg")
    }

    @Test("Invalid charset aliases fail both dry-run and edit before output; legal ISO2022 round trips")
    func strictCharsetEdits() throws {
        let original = DataSet(elements: [.string(tag: .patientName, vr: .PN, value: "山田^太郎")])
        for declaration in ["ISO_IR 87", "ISO_IR 159", "ISO 2022 IR 14", "ISO 2022 IR 87"] {
            for dryRun in [true, false] {
                var dataset = original
                #expect(throws: DICOMTextEncodingError.self) {
                    try TagEditor().applyCheckedChanges(to: &dataset, sets: ["SpecificCharacterSet=\(declaration)"],
                        deletes: [], deletePrivate: false, sourceDataSet: nil, copyTags: [], verbose: false, dryRun: dryRun)
                }
                #expect(dataset.write() == original.write())
            }
        }
        var legal = original
        _ = try TagEditor().applyCheckedChanges(to: &legal, sets: ["SpecificCharacterSet=\\ISO 2022 IR 87"],
            deletes: [], deletePrivate: false, sourceDataSet: nil, copyTags: [], verbose: false, dryRun: false)
        let read = try roundTrip(legal).dataSet
        #expect(read.string(for: .specificCharacterSet) == "\\ISO 2022 IR 87")
        #expect(read.string(for: .patientName) == "山田^太郎")
        #expect(read[.patientName]?.valueData.contains(0x1B) == true)
    }

    @Test("Edited SOP class and instance agree with File Meta and actual encoded group length")
    func identitySynchronization() throws {
        let original = DICOMFile.create(dataSet: DataSet(), sopInstanceUID: "2.25.1")
        let newClass = "1.2.840.10008.5.1.4.1.1.2"
        let newInstance = "2.25.222222222"
        let originalClass = try #require(original.dataSet.string(for: .sopClassUID))
        // Independent class-only and instance-only fixtures prevent one edit
        // from accidentally masking the other synchronization path.
        let cases = [(["SOPClassUID=\(newClass)"], newClass, "2.25.1"),
                     (["SOPInstanceUID=\(newInstance)"], originalClass, newInstance)]
        for (sets, expectedClass, expectedInstance) in cases {
            var dataset = original.dataSet
            _ = try TagEditor().applyCheckedChanges(to: &dataset, sets: sets, deletes: [],
                deletePrivate: false, sourceDataSet: nil, copyTags: [], verbose: false, dryRun: false)
            var meta = original.fileMetaInformation
            meta.setUInt32(1, for: .fileMetaInformationGroupLength)
            let file = DICOMFile(fileMetaInformation: meta, dataSet: dataset).synchronizingMediaStorageUIDs()
            let decoded = try DICOMFile.read(from: file.write())
            #expect(decoded.dataSet.string(for: .sopClassUID) == expectedClass)
            #expect(decoded.fileMetaInformation.string(for: .mediaStorageSOPClassUID) == expectedClass)
            #expect(decoded.dataSet.string(for: .sopInstanceUID) == expectedInstance)
            #expect(decoded.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID) == expectedInstance)
            var others = decoded.fileMetaInformation
            others.remove(tag: .fileMetaInformationGroupLength)
            #expect(decoded.fileMetaInformation.uint32(for: .fileMetaInformationGroupLength) == UInt32(others.write().count))
        }
        // Identity equality does not establish that this synthetic dataset satisfies a CT IOD.
    }

    @Test("File writer recomputes stale meta group length even without an identity change")
    func staleGroupLength() throws {
        let original = DICOMFile.create(dataSet: DataSet())
        var meta = original.fileMetaInformation
        meta.setUInt32(1, for: .fileMetaInformationGroupLength)
        let decoded = try DICOMFile.read(from: DICOMFile(fileMetaInformation: meta, dataSet: original.dataSet).write())
        var others = decoded.fileMetaInformation
        others.remove(tag: .fileMetaInformationGroupLength)
        #expect(decoded.fileMetaInformation.uint32(for: .fileMetaInformationGroupLength) == UInt32(others.write().count))
    }
}
