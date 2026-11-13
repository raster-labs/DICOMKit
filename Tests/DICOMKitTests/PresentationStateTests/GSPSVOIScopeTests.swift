import Foundation
import XCTest
import DICOMCore
@testable import DICOMKit

final class GSPSVOIScopeTests: XCTestCase {
    private let sourceA = "1.2.826.0.1.3680043.10.511.901"
    private let sourceB = "1.2.826.0.1.3680043.10.511.902"
    private let ctClass = "1.2.840.10008.5.1.4.1.1.2"

    private func sequence(_ tag: Tag, _ items: [SequenceItem]) -> DataElement {
        DataElement(tag: tag, vr: .SQ, length: 0xFFFFFFFF,
                    valueData: Data(), sequenceItems: items)
    }

    private func reference(sop: String, frames: String? = "1", sopClass: String? = nil) -> SequenceItem {
        var elements = [
            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: sopClass ?? ctClass),
            DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: sop)
        ]
        if let frames {
            elements.append(.string(tag: .referencedFrameNumber, vr: .IS, value: frames))
        }
        return SequenceItem(elements: elements)
    }

    private func window(center: String = "40", width: String = "400",
                        scope: DataElement? = nil) -> SequenceItem {
        var elements = [
            DataElement.string(tag: .windowCenter, vr: .DS, value: center),
            DataElement.string(tag: .windowWidth, vr: .DS, value: width)
        ]
        if let scope { elements.append(scope) }
        return SequenceItem(elements: elements)
    }

    private func fixture(_ items: [SequenceItem]?) -> DataSet {
        var dataSet = DataSet()
        dataSet.setString(GrayscalePresentationStateBuilder.sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.826.0.1.3680043.10.511.999", for: .sopInstanceUID, vr: .UI)
        dataSet[.referencedSeriesSequence] = sequence(.referencedSeriesSequence, [
            SequenceItem(elements: [
                .string(tag: .seriesInstanceUID, vr: .UI, value: "1.2.826.0.1.3680043.10.511.900"),
                sequence(.referencedImageSequence, [reference(sop: sourceA)])
            ])
        ])
        // A fallback must never disguise a present, unsupported Softcopy VOI.
        dataSet.setString("999", for: .windowCenter, vr: .DS)
        dataSet.setString("2000", for: .windowWidth, vr: .DS)
        if let items { dataSet[.softcopyVOILUTSequence] = sequence(.softcopyVOILUTSequence, items) }
        return dataSet
    }

    private func rejects(_ dataSet: DataSet, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try GrayscalePresentationStateParser().parse(dataSet: dataSet), file: file, line: line) {
            guard case GrayscalePresentationStateParser.ParseError.unsupportedVOILUT = $0 else {
                return XCTFail("Expected explicit unsupported VOI error, got \($0)", file: file, line: line)
            }
        }
    }

    private func table() -> SequenceItem {
        SequenceItem(elements: [
            DataElement(tag: .lutDescriptor, vr: .US, length: 6, valueData: Data([2, 0, 0, 0, 8, 0])),
            DataElement(tag: .lutData, vr: .OW, length: 4, valueData: Data([0, 0, 255, 0]))
        ])
    }

    func testSingleUnscopedLUTPreserved() throws {
        let dataSet = fixture([SequenceItem(elements: [sequence(.voiLUTSequence, [table()])])])
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.voiLUT, .lut(LUTData(numberOfEntries: 2, firstValueMapped: 0,
                                                bitsPerEntry: 8, data: [0, 255])))
    }

    func testRejectsScopedLUT() {
        rejects(fixture([SequenceItem(elements: [
            sequence(.voiLUTSequence, [table()]),
            sequence(.referencedImageSequence, [reference(sop: sourceB, frames: "2")])
        ])]))
    }

    func testRejectsMultipleOrEmptyLUTTables() {
        for tables in [[table(), table()], []] {
            rejects(fixture([SequenceItem(elements: [sequence(.voiLUTSequence, tables)])]))
        }
    }

    func testRejectsWindowAndLUTConflict() {
        rejects(fixture([window(scope: sequence(.voiLUTSequence, [table()]))]))
    }

    func testAlternatePresentationClassesCannotEraseScope() {
        for sopClass in ["1.2.840.10008.5.1.4.1.1.11.2", "1.2.840.10008.5.1.4.1.1.11.3"] {
            var dataSet = fixture([window(scope: sequence(.referencedImageSequence,
                                                          [reference(sop: sourceB)]))])
            dataSet.setString(sopClass, for: .sopClassUID, vr: .UI)
            rejects(dataSet)
        }
    }

    private func references(_ images: [SequenceItem]) -> DataSet {
        var dataSet = fixture([window()])
        dataSet[.referencedSeriesSequence] = sequence(.referencedSeriesSequence, [
            SequenceItem(elements: [
                .string(tag: .seriesInstanceUID, vr: .UI, value: "1.2.826.0.1.3680043.10.511.900"),
                sequence(.referencedImageSequence, images)
            ])
        ])
        return dataSet
    }

    private func rejectsReference(_ dataSet: DataSet, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try GrayscalePresentationStateParser().parse(dataSet: dataSet), file: file, line: line) {
            guard case GrayscalePresentationStateParser.ParseError.invalidReference = $0 else {
                return XCTFail("Expected explicit invalid reference error, got \($0)", file: file, line: line)
            }
        }
    }

    func testReferenceRejectsMalformedPresentFrameRestrictions() {
        for frames in ["2\\BAD", "", " ", "\\2", "2\\", "1\\\\2", "0", "-1", "2147483648", "1.0", "\t2"] {
            rejectsReference(references([reference(sop: sourceA, frames: frames)]))
        }
    }

    func testReferenceRejectsWrongFrameVR() {
        var elements = reference(sop: sourceA).elements
        elements[.referencedFrameNumber] = .string(tag: .referencedFrameNumber, vr: .LO, value: "1")
        rejectsReference(references([SequenceItem(elements: elements)]))
    }

    func testReferenceRejectsIncompleteImagesWithoutShrinkingCardinality() {
        let valid = reference(sop: sourceA)
        for tag: Tag in [.referencedSOPInstanceUID, .referencedSOPClassUID] {
            for replacement: DataElement? in [nil, .string(tag: tag, vr: .UI, value: ""),
                                              .string(tag: tag, vr: .LO, value: sourceB),
                                              .string(tag: tag, vr: .UI, value: "1.2\\1.3")] {
                var elements = reference(sop: sourceB).elements
                elements[tag] = replacement
                let incomplete = SequenceItem(elements: elements)
                rejectsReference(references([valid, incomplete]))
                rejectsReference(references([incomplete, valid]))
            }
        }
    }

    func testReferenceRejectsIncompleteSeriesWithoutShrinkingCardinality() throws {
        let valid = try XCTUnwrap(fixture(nil)[.referencedSeriesSequence]?.sequenceItems?.first)
        for replacement: DataElement? in [nil, .string(tag: .seriesInstanceUID, vr: .UI, value: ""),
                                          .string(tag: .seriesInstanceUID, vr: .LO, value: sourceB)] {
            var elements = valid.elements
            elements[.seriesInstanceUID] = replacement
            var dataSet = fixture([window()])
            dataSet[.referencedSeriesSequence] = sequence(.referencedSeriesSequence,
                                                         [valid, SequenceItem(elements: elements)])
            rejectsReference(dataSet)
        }
    }

    func testReferenceRejectsMissingEmptyOrMalformedImageSequence() throws {
        let valid = try XCTUnwrap(fixture(nil)[.referencedSeriesSequence]?.sequenceItems?.first)
        for replacement: DataElement? in [nil, sequence(.referencedImageSequence, []),
            DataElement(tag: .referencedImageSequence, vr: .UN, length: 0, valueData: Data())] {
            var elements = valid.elements
            elements[.referencedImageSequence] = replacement
            var dataSet = fixture([window()])
            dataSet[.referencedSeriesSequence] = sequence(.referencedSeriesSequence,
                                                         [SequenceItem(elements: elements)])
            rejectsReference(dataSet)
        }
    }

    func testReferenceRejectsEmptyOrMalformedSeriesSequence() {
        for replacement in [sequence(.referencedSeriesSequence, []),
            DataElement(tag: .referencedSeriesSequence, vr: .UN, length: 0, valueData: Data())] {
            var dataSet = fixture([window()])
            dataSet[.referencedSeriesSequence] = replacement
            rejectsReference(dataSet)
        }
    }

    func testReferencePreservesAllImagesAndExplicitFrames() throws {
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: references([
            reference(sop: sourceA, frames: "1\\2"), reference(sop: sourceB, frames: nil)
        ]))
        XCTAssertEqual(parsed.referencedSeries.count, 1)
        XCTAssertEqual(parsed.referencedSeries[0].referencedImages.count, 2)
        XCTAssertEqual(parsed.referencedSeries[0].referencedImages[0].referencedFrameNumbers, [1, 2])
        XCTAssertEqual(parsed.referencedSeries[0].referencedImages[1].sopInstanceUID, sourceB)
        XCTAssertNil(parsed.referencedSeries[0].referencedImages[1].referencedFrameNumbers)
    }

    func testReferenceRejectsMixedSOPClassesWithinSeries() {
        rejectsReference(references([reference(sop: sourceA),
            reference(sop: sourceB, sopClass: "1.2.840.10008.5.1.4.1.1.4")]))
    }

    func testReferenceRejectsUnrepresentedSegmentRestriction() {
        var elements = reference(sop: sourceA).elements
        elements[.referencedSegmentNumber] = DataElement(
            tag: .referencedSegmentNumber, vr: .US, length: 2, valueData: Data([1, 0]))
        rejectsReference(references([SequenceItem(elements: elements)]))
    }

    func testRejectsContradictorySOPIdentity() {
        for ref in [reference(sop: sourceB, frames: "2"),
                    reference(sop: sourceA, sopClass: "1.2.840.10008.5.1.4.1.1.4")] {
            rejects(fixture([window(scope: sequence(.referencedImageSequence, [ref]))]))
        }
    }

    func testRejectsContradictoryOrMalformedFrameScope() {
        for frames in ["2", "1\\2", "0", "bad"] {
            rejects(fixture([window(scope: sequence(.referencedImageSequence,
                                                   [reference(sop: sourceA, frames: frames)]))]))
        }
    }

    func testRejectsEvenMatchingExplicitScopeRatherThanErasingIt() {
        for frames: String? in ["1", nil] {
            rejects(fixture([window(scope: sequence(.referencedImageSequence,
                                                   [reference(sop: sourceA, frames: frames)]))]))
        }
    }

    func testRejectsMultipleVOIItemsInEitherOrder() {
        let first = window()
        let second = window(center: "80", scope: sequence(.referencedImageSequence,
                                                         [reference(sop: sourceB, frames: "2")]))
        for items in [[first, second], [second, first], [first, window(center: "80")]] {
            rejects(fixture(items))
        }
    }

    func testRejectsEmptyOrMalformedReferencedImageSequence() {
        let malformed = DataElement(tag: .referencedImageSequence, vr: .UN, length: 2, valueData: Data([0, 0]))
        for scope in [sequence(.referencedImageSequence, []), malformed] {
            rejects(fixture([window(scope: scope)]))
        }
    }

    func testRejectsMalformedSoftcopySequenceWithoutTopLevelFallback() {
        rejects(fixture([]))
        var dataSet = fixture(nil)
        dataSet[.softcopyVOILUTSequence] = DataElement(
            tag: .softcopyVOILUTSequence, vr: .UN, length: 2, valueData: Data([0, 0]))
        rejects(dataSet)
        dataSet[.softcopyVOILUTSequence] = DataElement(
            tag: .softcopyVOILUTSequence, vr: .SQ, length: 0, valueData: Data())
        rejects(dataSet)
    }

    func testRejectsMissingVOIWithoutTopLevelFallback() {
        rejects(fixture([SequenceItem(elements: [])]))
        rejects(fixture([SequenceItem(elements: [.string(tag: .windowCenter, vr: .DS, value: "40")])]))
        var wrongVR = window().elements
        wrongVR[.windowCenter] = .string(tag: .windowCenter, vr: .LO, value: "40")
        rejects(fixture([SequenceItem(elements: wrongVR)]))
        for center in ["NaN", "inf", "bad"] { rejects(fixture([window(center: center)])) }
    }

    func testRejectsMultipleWindowPairsRatherThanSelectingFirst() {
        rejects(fixture([window(center: "40\\80", width: "400\\800")]))
        rejects(fixture([window(center: "40", width: "400\\800")]))
    }

    func testSingleUnscopedWindowPreservesRelationshipScope() throws {
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: fixture([window()]))
        XCTAssertEqual(parsed.voiLUT, .window(center: 40, width: 400, explanation: nil, function: .linear))
        let image = try XCTUnwrap(parsed.referencedSeries.first?.referencedImages.first)
        XCTAssertEqual(image.sopInstanceUID, sourceA)
        XCTAssertEqual(image.referencedFrameNumbers, [1])
    }

    func testAbsentSoftcopySequenceRetainsLegacyFallback() throws {
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: fixture(nil))
        XCTAssertEqual(parsed.voiLUT, .window(center: 999, width: 2000, explanation: nil, function: .linear))
    }
}
