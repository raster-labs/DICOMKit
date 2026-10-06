//
// PrintConformanceTests.swift
// DICOMNetworkTests
//
// Pins the DICOM 2026a values verified for the Print Management Service
// Class: the N-ACTION response shape (PS3.4 Tables H.4-3 / H.4-8), the
// service-specific status codes (Tables H.4-4 / H.4-9), the DIMSE-N codes
// (PS3.7 §10.1.4.1.10, Annex C), meta SOP Class membership (Tables
// H.3.2.2.1-1 / H.3.2.2.2-1 / H.3.3.2-1), the colour pixel module (PS3.3
// Table C.13-5), the Print Job module (Table C.13-8) and CS-legal Execution
// Status Info.
//

import XCTest
import DICOMCore
@testable import DICOMNetwork

// MARK: - Status codes and classification

final class PrintConformanceStatusCodeTests: XCTestCase {

    /// PS3.4 Table H.4-4: C600 is "Film Session SOP Instance hierarchy does
    /// not contain Film Box SOP Instances", C601 the print-queue-full failure.
    func testFilmSessionStatusCodesAndText() {
        XCTAssertEqual(PrintSCPStatus.filmSessionPrinting.rawValue, 0xC600)
        XCTAssertEqual(
            PrintSCPStatus.filmSessionPrinting.explanation,
            "Failed: Film Session SOP Instance hierarchy does not contain Film Box SOP Instances")
        XCTAssertEqual(PrintSCPStatus.printQueueFull.rawValue, 0xC601)
        XCTAssertEqual(
            PrintSCPStatus.printQueueFull.explanation,
            "Failed: Unable to create Print Job SOP Instance; print queue is full")
    }

    /// The codes with no public case: Tables H.4-4 / H.4-9 / H.4.2.2.1.2-1
    /// and PS3.7.
    func testWireStatusConstants() {
        XCTAssertEqual(PrintSCPWireStatus.filmSessionEmptyPage, 0xB602)
        XCTAssertEqual(PrintSCPWireStatus.filmBoxEmptyPage, 0xB603)
        XCTAssertEqual(PrintSCPWireStatus.imageDecimated, 0xB60A)
        XCTAssertEqual(PrintSCPWireStatus.filmBoxPrintQueueFull, 0xC602)
        XCTAssertEqual(PrintSCPWireStatus.unprintedFilmBoxExists, 0xC616)
        XCTAssertEqual(PrintSCPWireStatus.noSuchAction, 0x0123)
        XCTAssertEqual(PrintSCPWireStatus.unrecognizedOperation, 0x0211)
    }

    /// The SCU must treat the empty-page codes as warnings (the film printed)
    /// and the DIMSE-N codes as failures.
    func testWireStatusClassification() {
        XCTAssertTrue(DIMSEStatus.from(0xB602).isWarning)
        XCTAssertTrue(DIMSEStatus.from(0xB603).isSuccessOrWarning)
        XCTAssertTrue(DIMSEStatus.from(0xB60A).isWarning)
        XCTAssertTrue(DIMSEStatus.from(0xC600).isFailure)
        XCTAssertTrue(DIMSEStatus.from(0xC602).isFailure)
        XCTAssertTrue(DIMSEStatus.from(0xC616).isFailure)
        XCTAssertTrue(DIMSEStatus.from(0x0123).isFailure)
        XCTAssertTrue(DIMSEStatus.from(0x0211).isFailure)
    }

    /// PS3.3 Table C.13-8: Execution Status Info is CS with the Defined Terms
    /// INSUFFIC MEMORY (memory) and implementation terms otherwise — never
    /// the error's free text.
    func testExecutionStatusInfoIsACSDefinedTerm() {
        struct Sink: Error, CustomStringConvertible { let description: String }
        let memory = PrintSCPAssociation.executionStatusInfo(
            for: Sink(description: "Out of memory rendering 14x17 film"))
        XCTAssertEqual(memory, "INSUFFIC MEMORY")

        let other = PrintSCPAssociation.executionStatusInfo(
            for: Sink(description: "Disk sink failed: “/tmp/film.png” — permission denied"))
        XCTAssertEqual(other, "PRINT FAILURE")

        for term in [memory, other] {
            XCTAssertLessThanOrEqual(term.count, 16, "CS is at most 16 characters")
            XCTAssertTrue(term.allSatisfy { $0.isUppercase || $0.isNumber || $0 == " " || $0 == "_" },
                          "CS repertoire: \(term)")
        }
    }
}

// MARK: - Encoder

final class PrintConformanceEncoderTests: XCTestCase {

    /// PS3.4 Tables H.4-3 / H.4-8: Referenced Print Job Sequence (2100,0500)
    /// with Referenced SOP Class UID = Print Job SOP Class and the job UID.
    func testPrintJobReferenceRoundTripsInBothVRs() throws {
        for explicitVR in [true, false] {
            let data = PrintSCPEncoder.printJobReference(printJobUID: "1.2.3.4", explicitVR: explicitVR)
            let set = try PrintDatasetReader(explicitVR: explicitVR).parse(data)
            let item = try XCTUnwrap(set.firstItem(of: .referencedPrintJobSequence))
            XCTAssertEqual(item.string(for: .referencedSOPClassUID), printJobSOPClassUID)
            XCTAssertEqual(item.string(for: .referencedSOPInstanceUID), "1.2.3.4")
        }
    }

    /// PS3.3 Table C.13-8: the Print Job module is Execution Status, Execution
    /// Status Info, Creation Date/Time, Print Priority, Printer Name and
    /// Originator (AE). Number of Copies is not in it.
    func testPrintJobAttributesMatchTableC13_8() throws {
        let job = PrintSCPJobRecord(
            printJobUID: "1.2.200", filmBoxUID: "1.2.201", filmSessionUID: "1.2.202",
            executionStatus: "DONE", executionStatusInfo: "NORMAL",
            printPriority: .high, numberOfCopies: 2)
        let data = PrintSCPEncoder.printJobAttributes(
            job, printerName: "EMULATOR-1", originator: "MODALITY_1", explicitVR: true)
        let set = try PrintDatasetReader(explicitVR: true).parse(data)

        XCTAssertEqual(set.string(for: .executionStatus), "DONE")
        XCTAssertEqual(set.string(for: .executionStatusInfo), "NORMAL")
        XCTAssertNotNil(set.string(for: .creationDate))
        XCTAssertNotNil(set.string(for: .creationTime))
        XCTAssertEqual(set.string(for: .printPriority), "HIGH")
        XCTAssertEqual(set.string(for: .printerName), "EMULATOR-1")
        XCTAssertEqual(set.string(for: .originatingPrintManagement), "MODALITY_1")
        XCTAssertEqual(set.elements[.originatingPrintManagement]?.vr, .AE)
        XCTAssertFalse(set.contains(.numberOfCopies))
    }
}

// MARK: - Colour pixel module (PS3.3 Table C.13-5)

final class PrintConformanceColorPixelModuleTests: XCTestCase {

    private let configuration = PrintSCPConfiguration(aeTitle: "DCMPRINT", port: 0)

    /// 2×2 RGB with every sample distinct, so a planar/interleaved mix-up
    /// shows up in the bytes.
    private let interleaved = Data([
        1, 2, 3,   4, 5, 6,
        7, 8, 9,   10, 11, 12
    ])
    private let planar = Data([
        1, 4, 7, 10,   // R plane
        2, 5, 8, 11,   // G plane
        3, 6, 9, 12    // B plane
    ])

    private func colorItem(pixels: Data, bitsAllocated: UInt16 = 8,
                           planarConfiguration: UInt16? = nil) -> PrintAttributeSet {
        var set = PrintAttributeSet()
        set.insert(DataElement.uint16(tag: .samplesPerPixel, value: 3))
        set.insert(DataElement.string(tag: .photometricInterpretation, vr: .CS, value: "RGB"))
        if let planarConfiguration {
            set.insert(DataElement.uint16(tag: .planarConfiguration, value: planarConfiguration))
        }
        set.insert(DataElement.uint16(tag: .rows, value: 2))
        set.insert(DataElement.uint16(tag: .columns, value: 2))
        set.insert(DataElement.uint16(tag: .bitsAllocated, value: bitsAllocated))
        set.insert(DataElement.uint16(tag: .bitsStored, value: 8))
        set.insert(DataElement.uint16(tag: .highBit, value: 7))
        set.insert(DataElement.uint16(tag: .pixelRepresentation, value: 0))
        set.insert(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        return set
    }

    /// Table C.13-5, Basic Color Image Sequence: Bits Allocated is 8 only.
    func testColorBoxRejectsBitsAllocated16() {
        let pixels = Data(count: 2 * 2 * 3 * 2)
        XCTAssertThrowsError(try PrintSCPParser.parsePixelModule(
            colorItem(pixels: pixels, bitsAllocated: 16, planarConfiguration: 1),
            isColor: true, configuration: configuration)) { error in
            XCTAssertEqual((error as? PrintSCPFailure)?.status, .invalidAttributeValue)
        }
    }

    /// Table C.13-5, Basic Grayscale Image Sequence: Bits Allocated 16 stays
    /// legal for 12-in-16 grayscale.
    func testGrayscaleBoxStillAcceptsBitsAllocated16() throws {
        var set = PrintAttributeSet()
        set.insert(DataElement.uint16(tag: .samplesPerPixel, value: 1))
        set.insert(DataElement.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        set.insert(DataElement.uint16(tag: .rows, value: 2))
        set.insert(DataElement.uint16(tag: .columns, value: 2))
        set.insert(DataElement.uint16(tag: .bitsAllocated, value: 16))
        set.insert(DataElement.uint16(tag: .bitsStored, value: 12))
        set.insert(DataElement.uint16(tag: .highBit, value: 11))
        set.insert(DataElement.uint16(tag: .pixelRepresentation, value: 0))
        set.insert(DataElement(tag: .pixelData, vr: .OW, length: 8, valueData: Data(count: 8)))
        let parsed = try PrintSCPParser.parsePixelModule(set, isColor: false, configuration: configuration)
        XCTAssertEqual(parsed.image.bitsAllocated, 16)
        XCTAssertTrue(parsed.notes.isEmpty)
    }

    /// Planar Configuration 1 (the enumerated value) is de-interleaved into
    /// the color-by-pixel layout `PrintImageData` carries, with no note.
    func testPlanarConfiguration1IsDeinterleaved() throws {
        let parsed = try PrintSCPParser.parsePixelModule(
            colorItem(pixels: planar, planarConfiguration: 1),
            isColor: true, configuration: configuration)
        XCTAssertEqual(parsed.image.pixelData, interleaved)
        XCTAssertTrue(parsed.notes.isEmpty)
    }

    /// An absent Planar Configuration is taken at the enumerated value 1 and
    /// the sender is told in the log.
    func testAbsentPlanarConfigurationDefaultsTo1WithANote() throws {
        let parsed = try PrintSCPParser.parsePixelModule(
            colorItem(pixels: planar, planarConfiguration: nil),
            isColor: true, configuration: configuration)
        XCTAssertEqual(parsed.image.pixelData, interleaved)
        XCTAssertEqual(parsed.notes.count, 1)
        XCTAssertTrue(parsed.notes[0].contains("Planar Configuration (0028,0006) is absent"))
        XCTAssertTrue(parsed.notes[0].contains("Table C.13-5"))
    }

    /// Planar Configuration 0 is not enumerated; the pixels are honoured as
    /// sent and the sender is told.
    func testPlanarConfiguration0IsHonouredWithANote() throws {
        let parsed = try PrintSCPParser.parsePixelModule(
            colorItem(pixels: interleaved, planarConfiguration: 0),
            isColor: true, configuration: configuration)
        XCTAssertEqual(parsed.image.pixelData, interleaved)
        XCTAssertEqual(parsed.notes.count, 1)
        XCTAssertTrue(parsed.notes[0].contains("Planar Configuration (0028,0006) is 0"))
    }

    func testPlanarConfigurationOtherThan0Or1IsInvalid() {
        XCTAssertThrowsError(try PrintSCPParser.parsePixelModule(
            colorItem(pixels: interleaved, planarConfiguration: 2),
            isColor: true, configuration: configuration)) { error in
            XCTAssertEqual((error as? PrintSCPFailure)?.status, .invalidAttributeValue)
        }
    }

    /// The SCU side of the same table: the Basic Color Image Sequence is sent
    /// color-by-plane.
    func testSCUConvertsColorByPixelToColorByPlane() {
        let descriptor = PrintImageData(
            pixelData: interleaved, rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0, photometricInterpretation: "RGB")
        XCTAssertEqual(DICOMPrintService.colorByPlane(interleaved, descriptor: descriptor), planar)

        // Grayscale is left alone.
        let gray = PrintImageData(
            pixelData: Data([1, 2, 3, 4]), rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7)
        XCTAssertEqual(DICOMPrintService.colorByPlane(Data([1, 2, 3, 4]), descriptor: gray), Data([1, 2, 3, 4]))
    }

    func testPlanarRoundTripIsLossless() {
        let descriptor = PrintImageData(
            pixelData: interleaved, rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0, photometricInterpretation: "RGB")
        let onTheWire = DICOMPrintService.colorByPlane(interleaved, descriptor: descriptor)
        XCTAssertEqual(
            PrintSCPParser.interleaved(fromPlanar: onTheWire, pixelCount: 4, bytesPerSample: 1),
            interleaved)
    }
}

// MARK: - SCU data-set walker: Explicit VR length rule (D276)

final class PrintConformanceDataSetWalkerTests: XCTestCase {

    /// D276: the SCU's data-set walker (`extractStringValue`, reached here through
    /// `parsePrinterStatus`) used a literal 10-VR list for the 32-bit length rule
    /// that omitted OV, SV and UV, so an element of one of those VRs ahead of the
    /// wanted tag was read with a 16-bit length and derailed the walk. PS3.5 2026a
    /// 7.1.2 / Table 7.1-1: all VRs other than the 21 of Table 7.1-2 carry 2
    /// reserved bytes and a 32-bit Value Length; the walker now uses DICOMCore's
    /// `VR.uses32BitLength`.
    func testWalkerSkipsOVSVUVElementsWithThirtyTwoBitLength() {
        let eightBytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let sixteenBytes = eightBytes + eightBytes
        for vr in [VR.OV, .SV, .UV] {
            let elements = [
                // Any element sorted ahead of (2110,0010): private tag, VR under test.
                DataElement(tag: Tag(group: 0x0009, element: 0x1001), vr: vr, length: 16, valueData: sixteenBytes),
                DataElement.string(tag: .manufacturer, vr: .LO, value: "ACME"),
                DataElement.string(tag: Tag(group: 0x2110, element: 0x0010), vr: .CS, value: "NORMAL"),
                DataElement.string(tag: Tag(group: 0x2110, element: 0x0030), vr: .LO, value: "LASER1")
            ]
            let data = PrintSCPEncoder.serialize(elements, explicitVR: true)
            let status = DICOMPrintService.parsePrinterStatus(from: data, explicitVR: true)
            XCTAssertEqual(status.status, "NORMAL", "\(vr)")
            XCTAssertEqual(status.printerName, "LASER1", "\(vr)")
            XCTAssertEqual(status.manufacturer, "ACME", "\(vr)")
        }
    }

    /// The 16-bit VRs of PS3.5 Table 7.1-2 still walk correctly, and the data set's
    /// Implicit VR form is unaffected (its length is always 32-bit, 7.1.3).
    func testWalkerStillReadsSixteenBitAndImplicitVRElements() {
        let elements = [
            DataElement.string(tag: Tag(group: 0x0008, element: 0x0016), vr: .UI, value: "1.2.840.10008.5.1.1.16"),
            DataElement.string(tag: Tag(group: 0x2110, element: 0x0010), vr: .CS, value: "WARNING"),
            DataElement.string(tag: Tag(group: 0x2110, element: 0x0020), vr: .CS, value: "FILM JAM")
        ]
        for explicitVR in [true, false] {
            let data = PrintSCPEncoder.serialize(elements, explicitVR: explicitVR)
            let status = DICOMPrintService.parsePrinterStatus(from: data, explicitVR: explicitVR)
            XCTAssertEqual(status.status, "WARNING")
            XCTAssertEqual(status.statusInfo, "FILM JAM")
        }
    }
}

// MARK: - SCU parsing of the N-ACTION response

final class PrintConformanceNActionResponseTests: XCTestCase {

    /// PS3.4 Tables H.4-3 / H.4-8: the job UID comes from Referenced Print
    /// Job Sequence (2100,0500) in the data set.
    func testJobUIDIsReadFromReferencedPrintJobSequence() {
        for explicitVR in [true, false] {
            let data = PrintSCPEncoder.printJobReference(printJobUID: "1.2.826.0.1.7", explicitVR: explicitVR)
            XCTAssertEqual(
                DICOMPrintService.printJobUID(inActionResponse: data, explicitVR: explicitVR),
                "1.2.826.0.1.7")
        }
    }

    /// No data set, an empty data set, or a data set without the sequence
    /// means the SCP created no Print Job: nil, never a fallback.
    func testMissingSequenceYieldsNil() {
        XCTAssertNil(DICOMPrintService.printJobUID(inActionResponse: nil, explicitVR: true))
        XCTAssertNil(DICOMPrintService.printJobUID(inActionResponse: Data(), explicitVR: true))
        let unrelated = PrintSCPEncoder.serialize(
            [DataElement.string(tag: .printerName, vr: .LO, value: "X")], explicitVR: true)
        XCTAssertNil(DICOMPrintService.printJobUID(inActionResponse: unrelated, explicitVR: true))
    }
}

// MARK: - Meta SOP Class membership

final class PrintConformanceMetaClassTests: XCTestCase {

    private func negotiate(accepting acceptedIDs: Set<UInt8>,
                           colorMode: PrintColorMode = .grayscale) throws -> PrintContextResolver {
        let proposed = try PrintPresentationContexts.propose(colorMode: colorMode)
        let accepted = proposed.map { context in
            acceptedIDs.contains(context.id)
                ? AcceptedPresentationContext(id: context.id, result: .acceptance,
                                              transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
                : AcceptedPresentationContext(id: context.id, result: .abstractSyntaxNotSupported)
        }
        let acceptPDU = AssociateAcceptPDU(
            calledAETitle: try AETitle("PRINTER"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: accepted,
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3",
            implementationVersionName: nil)
        let negotiated = NegotiatedAssociation(acceptPDU: acceptPDU, localMaxPDUSize: 16384)
        return try PrintContextResolver(negotiated: negotiated, proposed: proposed, colorMode: colorMode)
    }

    /// PS3.4 Table H.3.3.2-1: Print Job, Presentation LUT and Annotation Box
    /// are optional SOP Classes with their own presentation contexts. With
    /// only the meta context accepted they are unsupported.
    func testOptionalClassesAreNotCoveredByTheMetaContext() throws {
        let contexts = try negotiate(accepting: [PrintPresentationContexts.ID.meta])
        for optional in [printJobSOPClassUID, presentationLUTSOPClassUID, basicAnnotationBoxSOPClassUID] {
            XCTAssertFalse(contexts.supports(optional), optional)
            XCTAssertThrowsError(try contexts.contextID(for: optional)) { error in
                guard case DICOMNetworkError.sopClassNotSupported(let uid) = error else {
                    return XCTFail("Expected sopClassNotSupported, got \(error)")
                }
                XCTAssertEqual(uid, optional)
            }
        }
    }

    /// With their own contexts accepted, the optional classes route to them
    /// (IDs 11 / 13 / 15) even though the meta context is also there.
    func testOptionalClassesRouteToTheirOwnContexts() throws {
        let contexts = try negotiate(accepting: [
            PrintPresentationContexts.ID.meta,
            PrintPresentationContexts.ID.printJob,
            PrintPresentationContexts.ID.presentationLUT,
            PrintPresentationContexts.ID.annotationBox
        ])
        XCTAssertEqual(try contexts.contextID(for: printJobSOPClassUID), PrintPresentationContexts.ID.printJob)
        XCTAssertEqual(try contexts.contextID(for: presentationLUTSOPClassUID), PrintPresentationContexts.ID.presentationLUT)
        XCTAssertEqual(try contexts.contextID(for: basicAnnotationBoxSOPClassUID), PrintPresentationContexts.ID.annotationBox)
        XCTAssertTrue(contexts.supports(basicAnnotationBoxSOPClassUID))
        // The four members still ride the meta context.
        XCTAssertEqual(try contexts.contextID(for: basicFilmSessionSOPClassUID), PrintPresentationContexts.ID.meta)
        XCTAssertEqual(try contexts.contextID(for: printerSOPClassUID), PrintPresentationContexts.ID.meta)
    }

    /// Table H.3.2.2.2-1: the colour meta class carries the Basic Color Image
    /// Box, not the grayscale one; Table H.3.2.2.1-1 the reverse.
    func testEachMetaClassCoversOnlyItsOwnImageBox() throws {
        let color = try negotiate(accepting: [PrintPresentationContexts.ID.meta], colorMode: .color)
        XCTAssertEqual(try color.contextID(for: basicColorImageBoxSOPClassUID), PrintPresentationContexts.ID.meta)
        XCTAssertFalse(color.supports(basicGrayscaleImageBoxSOPClassUID))

        let gray = try negotiate(accepting: [PrintPresentationContexts.ID.meta], colorMode: .grayscale)
        XCTAssertEqual(try gray.contextID(for: basicGrayscaleImageBoxSOPClassUID), PrintPresentationContexts.ID.meta)
        XCTAssertFalse(gray.supports(basicColorImageBoxSOPClassUID))
    }
}

#if canImport(Network)

// MARK: - SCP wire behaviour (raw DIMSE)

/// A delegate that refuses every film with a chosen error and remembers the
/// job UIDs it was told about, so the job can be N-GET afterwards.
private actor RefusingPrintHandler: PrintSCPDelegate {
    struct SinkError: Error, CustomStringConvertible { let description: String }
    let message: String
    private(set) var failedJobUIDs: [String] = []

    init(message: String) { self.message = message }

    func didReceiveFilm(_ film: ReceivedFilm) async throws {
        throw SinkError(description: message)
    }

    func didFail(error: Error, forPrintJob printJobUID: String?) async {
        if let printJobUID { failedJobUIDs.append(printJobUID) }
    }
}

final class PrintConformanceSCPTests: XCTestCase {

    private var server: DICOMPrintServer!
    private var scu: RawPrintSCU!
    private var handler: CollectingPrintHandler!
    private static let calledAE = "DCMPRINT"

    override func setUp() async throws {
        try await super.setUp()
        handler = CollectingPrintHandler()
        server = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle(Self.calledAE), port: 0),
            delegate: handler)
        try await server.start()
        scu = try RawPrintSCU(port: await server.boundPort, calledAE: Self.calledAE)
        try await scu.connect()
    }

    override func tearDown() async throws {
        await scu?.release()
        scu = nil
        await server?.stop()
        server = nil
        handler = nil
        try await super.tearDown()
    }

    private func status(_ message: AssembledMessage) -> UInt16 {
        message.commandSet.status?.rawValue ?? 0xFFFF
    }

    private func createSession() async throws -> String {
        let response = try await scu.nCreate(sopClass: basicFilmSessionSOPClassUID)
        XCTAssertEqual(status(response), 0x0000)
        return try XCTUnwrap(response.commandSet.affectedSOPInstanceUID)
    }

    private func createFilmBox() async throws -> (String, [String]) {
        let response = try await scu.nCreate(
            sopClass: basicFilmBoxSOPClassUID,
            elements: [DataElement.string(tag: .imageDisplayFormat, vr: .ST, value: "STANDARD\\1,1")])
        XCTAssertEqual(status(response), 0x0000)
        let uid = try XCTUnwrap(response.commandSet.affectedSOPInstanceUID)
        let set = try PrintDatasetReader(explicitVR: true).parse(try XCTUnwrap(response.dataSet))
        let boxes = set.items(for: .referencedImageBoxSequence)
            .compactMap { $0.string(for: .referencedSOPInstanceUID) }
        return (uid, boxes)
    }

    private func fillImageBox(_ uid: String) async throws {
        let item = SequenceItem(elements: [
            DataElement.uint16(tag: .samplesPerPixel, value: 1),
            DataElement.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
            DataElement.uint16(tag: .rows, value: 2),
            DataElement.uint16(tag: .columns, value: 2),
            DataElement.uint16(tag: .bitsAllocated, value: 8),
            DataElement.uint16(tag: .bitsStored, value: 8),
            DataElement.uint16(tag: .highBit, value: 7),
            DataElement.uint16(tag: .pixelRepresentation, value: 0),
            DataElement.data(tag: .pixelData, vr: .OW, data: Data([1, 2, 3, 4]))
        ])
        let response = try await scu.nSet(
            sopClass: basicGrayscaleImageBoxSOPClassUID, sopInstance: uid,
            elements: [
                DataElement.uint16(tag: .imageBoxPosition, value: 1),
                DataElement(tag: .preformattedGrayscaleImageSequence, vr: .SQ, length: 0,
                            valueData: Data(), sequenceItems: [item])
            ])
        XCTAssertEqual(status(response), 0x0000)
    }

    private func printJobUID(in response: AssembledMessage) throws -> String {
        let set = try PrintDatasetReader(explicitVR: true).parse(try XCTUnwrap(response.dataSet))
        let item = try XCTUnwrap(set.firstItem(of: .referencedPrintJobSequence))
        XCTAssertEqual(item.string(for: .referencedSOPClassUID), printJobSOPClassUID)
        return try XCTUnwrap(item.string(for: .referencedSOPInstanceUID))
    }

    /// PS3.4 Table H.4-4, C600.
    func testFilmSessionNActionWithNoFilmBoxesIsC600() async throws {
        let sessionUID = try await createSession()
        let response = try await scu.nAction(
            sopClass: basicFilmSessionSOPClassUID, sopInstance: sessionUID)
        XCTAssertEqual(status(response), 0xC600)
        XCTAssertNil(response.dataSet)
        let films = await handler.films
        XCTAssertTrue(films.isEmpty)
    }

    /// PS3.4 Table H.4-4, B602: the empty film box is printed as an empty
    /// page and the Print Job is still created.
    func testFilmSessionNActionWithEmptyFilmBoxIsB602() async throws {
        let sessionUID = try await createSession()
        _ = try await createFilmBox()
        let response = try await scu.nAction(
            sopClass: basicFilmSessionSOPClassUID, sopInstance: sessionUID)
        XCTAssertEqual(status(response), 0xB602)
        let films = await handler.films
        XCTAssertEqual(films.count, 1)
        XCTAssertEqual(films.first?.filledImageBoxes.count, 0)
        let jobUID = try printJobUID(in: response)
        XCTAssertEqual(films.first?.printJobUID, jobUID)
    }

    /// PS3.4 Table H.4-3 and PS3.7 N-ACTION-RSP: the response names the Film
    /// Session the action was invoked on, and the job in (2100,0500).
    func testFilmSessionNActionResponseNamesTheSessionAndReferencesTheJob() async throws {
        let sessionUID = try await createSession()
        let (_, imageBoxes) = try await createFilmBox()
        try await fillImageBox(try XCTUnwrap(imageBoxes.first))
        let response = try await scu.nAction(
            sopClass: basicFilmSessionSOPClassUID, sopInstance: sessionUID)
        XCTAssertEqual(status(response), 0x0000)
        XCTAssertEqual(response.commandSet.affectedSOPClassUID, basicFilmSessionSOPClassUID)
        XCTAssertEqual(response.commandSet.affectedSOPInstanceUID, sessionUID)
        let jobUID = try printJobUID(in: response)
        let films = await handler.films
        XCTAssertEqual(films.first?.printJobUID, jobUID)
    }

    /// PS3.4 Table H.4-9, B603, with the job referenced.
    func testFilmBoxNActionWithNoImagesIsB603AndReferencesTheJob() async throws {
        _ = try await createSession()
        let (filmBoxUID, _) = try await createFilmBox()
        let response = try await scu.nAction(
            sopClass: basicFilmBoxSOPClassUID, sopInstance: filmBoxUID)
        XCTAssertEqual(status(response), 0xB603)
        XCTAssertEqual(response.commandSet.affectedSOPClassUID, basicFilmBoxSOPClassUID)
        XCTAssertEqual(response.commandSet.affectedSOPInstanceUID, filmBoxUID)
        let jobUID = try printJobUID(in: response)

        // The job exists and is DONE: an empty page is a printed page.
        let job = try await scu.nGet(sopClass: printJobSOPClassUID, sopInstance: jobUID)
        XCTAssertEqual(status(job), 0x0000)
        let attributes = try PrintDatasetReader(explicitVR: true).parse(try XCTUnwrap(job.dataSet))
        XCTAssertEqual(attributes.string(for: .executionStatus), "DONE")
    }

    /// PS3.7 Annex C: an operation the Service Class does not define is
    /// "Unrecognized operation" (0211H). An SCU pushing N-EVENT-REPORT at a
    /// printer is the realistic case.
    func testUnrecognizedDIMSEOperationIs0211() async throws {
        var command = CommandSet()
        command.setCommand(.nEventReportRequest)
        command.setMessageID(77)
        command.setAffectedSOPClassUID(printerSOPClassUID)
        command.setAffectedSOPInstanceUID(printerSOPInstanceUID)
        command.setEventTypeID(1)
        command.setHasDataSet(false)
        let response = try await scu.send(command)
        XCTAssertEqual(response.commandSet.command, .nEventReportResponse)
        XCTAssertEqual(status(response), 0x0211)
    }
}

/// The failed-print path needs a refusing delegate, so it gets its own server.
final class PrintConformanceFailedJobTests: XCTestCase {

    private func run(message: String) async throws -> String {
        let handler = RefusingPrintHandler(message: message)
        let server = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle("DCMPRINT"), port: 0),
            delegate: handler)
        try await server.start()
        let scu = try RawPrintSCU(port: await server.boundPort, calledAE: "DCMPRINT")
        try await scu.connect()

        let session = try await scu.nCreate(sopClass: basicFilmSessionSOPClassUID)
        let box = try await scu.nCreate(
            sopClass: basicFilmBoxSOPClassUID,
            elements: [DataElement.string(tag: .imageDisplayFormat, vr: .ST, value: "STANDARD\\1,1")])
        XCTAssertEqual(session.commandSet.status?.rawValue, 0x0000)
        let filmBoxUID = try XCTUnwrap(box.commandSet.affectedSOPInstanceUID)

        let action = try await scu.nAction(sopClass: basicFilmBoxSOPClassUID, sopInstance: filmBoxUID)
        XCTAssertEqual(action.commandSet.status?.rawValue, PrintSCPStatus.processingFailure.rawValue)
        // The failure response carries no Referenced Print Job Sequence; the
        // delegate was told the job UID instead.
        XCTAssertNil(action.dataSet)
        let failedJobUIDs = await handler.failedJobUIDs
        let jobUID = try XCTUnwrap(failedJobUIDs.first)

        let job = try await scu.nGet(sopClass: printJobSOPClassUID, sopInstance: jobUID)
        XCTAssertEqual(job.commandSet.status?.rawValue, 0x0000)
        let attributes = try PrintDatasetReader(explicitVR: true).parse(try XCTUnwrap(job.dataSet))
        XCTAssertEqual(attributes.string(for: .executionStatus), "FAILURE")
        let info = try XCTUnwrap(attributes.string(for: .executionStatusInfo))

        await scu.release()
        await server.stop()
        return info
    }

    /// PS3.3 Table C.13-8: a FAILURE job reports a CS Defined Term, not the
    /// sink's error text.
    func testFailedJobReportsImplementationTerm() async throws {
        let info = try await run(message: "Disk sink refused “film.png”: permission denied")
        XCTAssertEqual(info, "PRINT FAILURE")
    }

    func testMemoryFailureReportsInsufficMemory() async throws {
        let info = try await run(message: "Out of memory composing the sheet")
        XCTAssertEqual(info, "INSUFFIC MEMORY")
    }
}

// MARK: - Loopback and mock-SCP behaviour

final class PrintConformanceLoopbackTests: XCTestCase {

    /// PS3.3 Table C.13-5 end to end: the SCU sends the colour box
    /// color-by-plane with Planar Configuration 1, the SCP hands the delegate
    /// the color-by-pixel samples it was given — every sample distinct so a
    /// layout mistake on either side would show.
    func testColorImageRoundTripsThroughThePlanarWireLayout() async throws {
        let handler = CollectingPrintHandler()
        let server = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle("DCMPRINT"), port: 0),
            delegate: handler)
        try await server.start()
        defer { Task { await server.stop() } }

        let pixels = Data((0..<(4 * 4 * 3)).map { UInt8($0) })
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 4, columns: 4,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0,
            photometricInterpretation: "RGB")
        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: await server.boundPort,
                callingAETitle: "TEST_SCU", calledAETitle: "DCMPRINT",
                timeout: 15, colorMode: .color),
            images: [pixels], options: .default, imageDescriptors: [descriptor])
        XCTAssertTrue(result.success, result.errorMessage ?? "")

        let films = await handler.films
        let film = try XCTUnwrap(films.first)
        XCTAssertEqual(film.imageBoxes.first?.sopClassUID, basicColorImageBoxSOPClassUID)
        XCTAssertEqual(film.imageBoxes.first?.image?.pixelData, pixels)
    }

    /// The SCU takes the job UID from (2100,0500) and never from the command
    /// set's Affected SOP Instance UID, which is the Film Box.
    func testWorkflowRecordsTheReferencedPrintJob() async throws {
        let scp = MockPrintSCP()
        try await scp.start()
        defer { Task { await scp.stop() } }

        let pixels = Data([0, 64, 128, 255])
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7)
        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: await scp.port,
                callingAETitle: "TEST_SCU", calledAETitle: "MOCK_SCP", timeout: 10),
            images: [pixels], imageDescriptors: [descriptor])
        XCTAssertEqual(result.printJobUID, "1.2.826.0.1.3680043.9.mock.job.1")
        XCTAssertNotEqual(result.printJobUID, result.filmBoxUIDs.first)
    }

    /// An SCP that answers the Printer N-GET with no data set has said
    /// nothing about its state; that is UNKNOWN, not NORMAL.
    func testPrinterNGetWithoutDataSetIsUnknown() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.omitPrinterStatusDataSet = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let status = try await DICOMPrintService.getPrinterStatus(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: await scp.port,
                callingAETitle: "TEST_SCU", calledAETitle: "MOCK_SCP", timeout: 10))
        XCTAssertEqual(status.status, "UNKNOWN")
        XCTAssertFalse(status.isNormal)
        XCTAssertNil(status.statusInfo)
    }
}

#endif
